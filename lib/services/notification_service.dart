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
    // Initialise WITHOUT prompting for permission — the prompt is asked at a
    // contextual moment (the onboarding reminders step) via [requestPermission],
    // not blindly at cold launch, which improves opt-in.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );

    _initialized = true;
  }

  /// Explicitly asks the OS for notification permission. Call this from a
  /// contextual moment (e.g. the onboarding reminders step) rather than at
  /// launch. Returns true if granted. Safe to call more than once — the OS only
  /// shows the system prompt the first time.
  Future<bool> requestPermission() async {
    await init();
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final ios =
        await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);
    // Android 13+ requires a runtime prompt to post notifications.
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final android = await androidImpl?.requestNotificationsPermission();
    return ios ?? android ?? false;
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

  static const _cleanCadence = {'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly'};

  DateTime _addMonths(DateTime d, int months) {
    final zb = d.month - 1 + months;
    final y = d.year + zb ~/ 12;
    final m = zb % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d.day < lastDay ? d.day : lastDay);
  }

  DateTime _advance(DateTime d, String cycle) {
    switch (cycle) {
      case 'weekly':
        return d.add(const Duration(days: 7));
      case 'quarterly':
        return _addMonths(d, 3);
      case 'yearly':
        return _addMonths(d, 12);
      default:
        return _addMonths(d, 1);
    }
  }

  /// (Re)schedules reminders from the LIVE recurring bills (dashboard `subs`),
  /// replacing the old stale-import path. For each ACTIVE, user-kept bill/
  /// subscription with a regular cadence, the next due date is computed from the
  /// REAL last charge (last + one cycle, rolled forward), so a bill you just paid
  /// reminds ~a cycle out, never "tomorrow". Reminds 2 days BEFORE, at 10:00.
  /// Skips: transfers, people, ad-hoc top-ups (irregular cadence, e.g. Pildyk),
  /// user-excluded streams, and trivial amounts. Deduplicated by name.
  ///
  /// [excluded]/[included] are the user's manager overrides (DashboardStore).
  Future<void> scheduleFromRecurring(
    List<Map<String, dynamic>> items, {
    required Set<String> excluded,
    required Set<String> included,
    required bool isLithuanian,
  }) async {
    await init();
    // One clean slate — clears every prior reminder, including the stale
    // imported-subscription ones that used to fire wrongly.
    await _plugin.cancelAll();
    if (!AppPrefs.notificationsEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    final seen = <String>{};
    for (final it in items) {
      final name = (it['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();

      // Respect the user's manager verdict; default to the backend's active bills.
      final backendActive = it['active'] == true && it['type'] != 'transfer';
      final counted = included.contains(key) || (backendActive && !excluded.contains(key));
      if (!counted) continue;

      final type = (it['type'] as String?) ?? 'subscription';
      if (type != 'subscription' && type != 'bill') continue; // never a transfer
      final cadence = ((it['cadence'] as String?) ?? '').toLowerCase();
      if (!_cleanCadence.contains(cadence)) continue; // skip ad-hoc/irregular
      final monthly = ((it['monthly'] ?? 0) as num).toDouble();
      if (monthly < 5) continue; // ignore trivial amounts
      if (!seen.add(key)) continue; // one reminder per payee

      final lastStr = it['lastCharge'] as String?;
      final last = lastStr != null ? DateTime.tryParse(lastStr) : null;
      if (last == null) continue;
      final cycle = (it['cycle'] as String?) ?? 'monthly';
      var due = _advance(last, cycle);
      var guard = 0;
      while (due.isBefore(today) && guard++ < 24) {
        due = _advance(due, cycle);
      }
      final remindDay = due.subtract(const Duration(days: 2));
      final scheduled = tz.TZDateTime(
          tz.local, remindDay.year, remindDay.month, remindDay.day, _remindHour);
      if (!scheduled.isAfter(now)) continue; // already passed → skip

      await _plugin.zonedSchedule(
        id: key.hashCode & 0x3FFFFFFF,
        scheduledDate: scheduled,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Vaultie 🔔',
        body: isLithuanian
            ? '$name · ${formatMoney(monthly)} – mokėjimas po 2 d.'
            : '$name · ${formatMoney(monthly)} – due in 2 days',
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
