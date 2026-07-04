import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app_prefs.dart';
import '../models/subscription.dart';

/// Schedules local "payment due soon" reminders.
///
/// For each expense we fire a single reminder ~24 hours before its next
/// billing date (at 10:00 the day before), so the user gets one clear heads-up
/// per payment rather than a barrage. Scheduling is idempotent — calling
/// [scheduleForSubscription] again clears the old reminder first, so it doubles
/// as the "edit" path.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'renewal_reminders';
  static const _channelName = 'Renewal reminders';
  static const _channelDescription =
      'Reminders before your subscriptions renew';

  /// Days-before-renewal we schedule a reminder for. A single 1-day (~24h)
  /// heads-up per expense.
  static const List<int> _remindOffsets = [1];

  /// The hour of day (local) reminders fire at.
  static const int _remindHour = 10;

  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Leave tz.local at its default (UTC) if the device zone can't resolve.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS/macOS: request alert/badge/sound authorisation on init.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );

    // Android 13+ requires a runtime prompt to post notifications.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    // iOS requires an explicit authorisation request too.
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  /// Stable, collision-spaced id per (subscription, reminder offset).
  /// `daysBefore` is always 1–3, so the `*4` blocks never overlap.
  int _notifId(String subId, int daysBefore) =>
      (subId.hashCode & 0x1FFFFFFF) * 4 + daysBefore;

  String _body(String name, String amount, int days, bool isLithuanian) {
    if (isLithuanian) {
      final when = days == 1 ? 'rytoj' : 'po $days d.';
      return '$name · $amount – mokėjimas $when';
    }
    final when = days == 1 ? 'tomorrow' : 'in $days days';
    return '$name · $amount – due $when';
  }

  /// (Re)schedules the 3/2/1-day reminders for [sub]. Safe to call on add and
  /// on edit — existing reminders for this subscription are cancelled first.
  Future<void> scheduleForSubscription(
    Subscription sub, {
    required bool isLithuanian,
  }) async {
    await init();
    await cancelForSubscription(sub.id);

    // Respect the user's Settings notifications preference.
    if (!AppPrefs.notificationsEnabled) return;

    final amount =
        sub.isEstimated ? '~${formatMoney(sub.cost)}' : formatMoney(sub.cost);
    final now = tz.TZDateTime.now(tz.local);
    for (final daysBefore in _remindOffsets) {
      final remindDay =
          sub.nextBillingDate.subtract(Duration(days: daysBefore));
      final scheduled = tz.TZDateTime(
        tz.local,
        remindDay.year,
        remindDay.month,
        remindDay.day,
        _remindHour,
      );
      // Don't schedule reminders that are already in the past.
      if (!scheduled.isAfter(now)) continue;

      await _plugin.zonedSchedule(
        id: _notifId(sub.id, daysBefore),
        scheduledDate: scheduled,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Vaultie 🔔',
        body: _body(sub.name, amount, daysBefore, isLithuanian),
      );
    }
  }

  /// Cancels all reminders previously scheduled for a subscription id. Covers
  /// legacy offsets (older versions scheduled 3/2/1-day reminders) so upgrading
  /// to the single 24h reminder doesn't leave stale notifications behind.
  Future<void> cancelForSubscription(String subId) async {
    for (final daysBefore in const [3, 2, 1]) {
      await _plugin.cancel(id: _notifId(subId, daysBefore));
    }
  }

  /// Cancels every scheduled reminder — used when notifications are turned off.
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// True on iOS when notification permission was requested (we do so at launch
  /// in [init]) and the user did NOT grant it — i.e. explicitly denied. Returns
  /// false when permission is granted, the state can't be determined, or on a
  /// non-iOS platform. Used to decide whether to show the "reminders off"
  /// banner (which must not appear before the user has ever been asked).
  Future<bool> isPermissionDenied() async {
    await init();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios == null) return false;
    final options = await ios.checkPermissions();
    return options != null && !options.isEnabled;
  }
}
