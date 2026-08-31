import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../app_prefs.dart';
import '../models/subscription.dart';
import '../services/dashboard_store.dart';

DateTime _addMonthsClamped(DateTime d, int months) {
  final zb = d.month - 1 + months;
  final y = d.year + zb ~/ 12;
  final m = zb % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day < lastDay ? d.day : lastDay);
}

// 2026-09-01: real bug, found in audit — 'biweekly' and 'semiannual' had no
// case here and silently fell into `default` (advance by 1 month), so both
// were mis-scheduled AND mis-predicted by a whole cycle. Both cadences are
// real, expected values (see _cleanCadence's allow-list and chargeFor's own
// per-cadence conversions nearby) — this is the engine that decides both
// when the reminder fires and what the Sąskaitos due-date chart shows, so
// the bug affected both at once. models/subscription.dart's older
// BillingCycleX.advanceFrom already had both cases right (14 days /
// _addMonths(6)) — this mirrors that exact convention.
DateTime _advanceCycle(DateTime d, String cycle) {
  switch (cycle) {
    case 'weekly':
      return d.add(const Duration(days: 7));
    case 'biweekly':
      return d.add(const Duration(days: 14));
    case 'quarterly':
      return _addMonthsClamped(d, 3);
    case 'semiannual':
      return _addMonthsClamped(d, 6);
    case 'yearly':
      return _addMonthsClamped(d, 12);
    default:
      return _addMonthsClamped(d, 1);
  }
}

/// The single source of truth for "when is this recurring item due next" —
/// used both to schedule the actual reminder (below) and to draw the
/// Sąskaitos due-date chart (subs_bills_live.dart), so what the chart shows
/// and when the reminder fires can never drift apart.
///
/// Starts from the last REAL charge + one cycle, rolled forward past today
/// (a bank charging a day early/late one cycle shifts this prediction by
/// that same day — see DashboardStore.recurringDueDayOverrides' own doc).
/// If the user has corrected this item's day-of-month, that wins outright.
DateTime? predictedDueDate(String sid, {
  required String? lastChargeIso,
  required String cycle,
  DateTime? today,
}) {
  final last = lastChargeIso != null ? DateTime.tryParse(lastChargeIso) : null;
  if (last == null) return null;
  final now = today ?? DateTime.now();
  final t = DateTime(now.year, now.month, now.day);
  var due = _advanceCycle(last, cycle);
  var guard = 0;
  while (due.isBefore(t) && guard++ < 24) {
    due = _advanceCycle(due, cycle);
  }
  final overrideDay = sid.isEmpty ? null : DashboardStore.recurringDueDayOverrides()[sid];
  if (overrideDay != null) {
    final lastDayOfMonth = DateTime(due.year, due.month + 1, 0).day;
    due = DateTime(due.year, due.month, overrideDay > lastDayOfMonth ? lastDayOfMonth : overrideDay);
  }
  return due;
}

/// Same sid fallback dashboard_preview.dart's `_recKey` / subs_bills_live.dart's
/// `_LiveItem.sid` use — the backend's own id, else name|monthly for a payload
/// old enough to carry none. Kept in sync by convention, not by sharing code,
/// same as those two.
String recurringSidOf(Map it) {
  final sid = ((it['sid'] as String?) ?? '').trim();
  if (sid.isNotEmpty) return sid;
  final name = ((it['name'] as String?) ?? '').trim().toLowerCase();
  if (name.isEmpty) return '';
  final monthly = ((it['monthly'] ?? 0) as num).toDouble();
  return '$name|${monthly.toStringAsFixed(2)}';
}

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

  /// Budget warnings go out in the evening, not with the morning reminders —
  /// it is about the day you are still spending in, and it should not arrive in
  /// the same batch as everything else.
  static const int _budgetHour = 19;

  /// Above this, a yearly charge gets a 7-day warning as well as the 2-day one.
  /// Set where cancelling is worth the trouble: nobody reorganises their week
  /// over 15 €, and everybody wants a week's notice before 60 € goes out.
  static const double _bigChargeThreshold = 40;

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

  /// (Re)schedules reminders from the LIVE recurring bills (dashboard `subs`),
  /// replacing the old stale-import path. For each ACTIVE, user-kept bill/
  /// subscription with a regular cadence, the next due date is computed from the
  /// REAL last charge (last + one cycle, rolled forward), so a bill you just paid
  /// reminds ~a cycle out, never "tomorrow". Reminds 2 days BEFORE, at 10:00.
  /// Skips: transfers, people, ad-hoc top-ups (irregular cadence, e.g. Pildyk),
  /// user-excluded streams, and trivial amounts. Deduplicated by name.
  ///
  /// [excluded]/[included] are the user's manager overrides (DashboardStore).
  /// [consentExpiry] is when the bank access itself lapses (PSD2 re-consent,
  /// ~90 days). [spent] is the month's spending so far, against [budget].
  /// Both are optional: nothing is scheduled for them when they are unknown.
  ///
  /// This method owns the WHOLE schedule. It opens by cancelling everything, so
  /// anything scheduled elsewhere would be silently wiped the next time a scan
  /// finished — every notification the app sends has to be (re)built here.
  Future<void> scheduleFromRecurring(
    List<Map<String, dynamic>> items, {
    required Set<String> excluded,
    required Set<String> included,
    required bool isLithuanian,
    DateTime? consentExpiry,
    double? spent,
    double? budget,
  }) async {
    await init();
    // One clean slate — clears every prior reminder, including the stale
    // imported-subscription ones that used to fire wrongly.
    await _plugin.cancelAll();
    if (!AppPrefs.notificationsEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    await _scheduleMonthlyReport(now, isLithuanian);
    await _scheduleConsentExpiry(now, consentExpiry, isLithuanian);
    await _scheduleBudgetWarning(now, spent, budget, isLithuanian);
    final today = DateTime(now.year, now.month, now.day);
    final seen = <String>{};

    // First pass: filter down to the real candidates and their due dates,
    // without scheduling anything yet — the actual scheduling order below
    // needs every candidate's due date known up front (soonest first), not
    // whatever order `items` happens to arrive in.
    final candidates = <({
      String key,
      String name,
      double charge,
      String cycle,
      DateTime due
    })>[];
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

      final cycle = (it['cycle'] as String?) ?? 'monthly';
      final due = predictedDueDate(recurringSidOf(it),
          lastChargeIso: it['lastCharge'] as String?, cycle: cycle, today: today);
      if (due == null) continue;
      // What the bank will actually take, not the monthly EQUIVALENT. `monthly`
      // is a normalised figure: a 120 €/year subscription carries monthly ≈ 10,
      // and the reminder used to announce "10 € – due in 2 days" two days before
      // 120 € left the account. The amount in a reminder about money has to be
      // the amount that moves.
      final charge = chargeFor(monthly, cycle);
      candidates.add(
          (key: key, name: name, charge: charge, cycle: cycle, due: due));
    }

    // iOS caps an app at 64 pending local notifications total — silently
    // drops anything scheduled past that, with no error and no signal back
    // to the app. _scheduleMonthlyReport alone reserves 12 (a year of
    // 1st-of-month reports), consent-expiry up to 2, budget up to 1 — 15
    // worst-case — so the remaining per-bill budget is capped here rather
    // than firing zonedSchedule for every tracked bill/subscription and
    // hoping the count never crosses 64. Soonest-due first, so if the cap
    // does bind, what gets dropped is the reminder furthest away — the one
    // there's the most other opportunity (a later app open, a later sync)
    // to still catch.
    const iosPendingCap = 64;
    const reservedForScheduleWide = 15; // 12 report + 2 consent + 1 budget
    const perBillBudget = iosPendingCap - reservedForScheduleWide;
    candidates.sort((a, b) => a.due.compareTo(b.due));

    var used = 0;
    for (final c in candidates) {
      if (used >= perBillBudget) break;
      final (:key, :name, :charge, :cycle, :due) = c;

      final remindDay = due.subtract(const Duration(days: 2));
      final scheduled = tz.TZDateTime(
          tz.local, remindDay.year, remindDay.month, remindDay.day, _remindHour);
      if (scheduled.isAfter(now)) {
        await _plugin.zonedSchedule(
          id: key.hashCode & 0x3FFFFFFF,
          scheduledDate: scheduled,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          title: 'Vaultie 🔔',
          body: isLithuanian
              ? '$name · ${formatMoney(charge)} – mokėjimas po 2 d.'
              : '$name · ${formatMoney(charge)} – due in 2 days',
        );
        used++;
      }

      // A big, infrequent charge needs more than two days' notice. Two days is
      // enough to move money across; it is not enough to decide whether you
      // still want a subscription, find the cancel button and have it take
      // effect before the year renews. This is the reminder that actually saves
      // somebody money, so it is the one with room to act on.
      final infrequent = cycle == 'yearly' || cycle == 'semiannual';
      if (infrequent && charge >= _bigChargeThreshold && used < perBillBudget) {
        final earlyDay = due.subtract(const Duration(days: 7));
        final early = tz.TZDateTime(
            tz.local, earlyDay.year, earlyDay.month, earlyDay.day, _remindHour);
        if (early.isAfter(now)) {
          await _plugin.zonedSchedule(
            id: '$key#early'.hashCode & 0x3FFFFFFF,
            scheduledDate: early,
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            title: 'Vaultie 🔔',
            body: isLithuanian
                ? '$name · ${formatMoney(charge)} atsinaujina po 7 d. — dar spėji atšaukti.'
                : '$name · ${formatMoney(charge)} renews in 7 days — still time to cancel.',
          );
          used++;
        }
      }
    }
  }

  /// A single charge, from the monthly-equivalent figure and the cycle.
  @visibleForTesting
  static double chargeFor(double monthly, String cycle) => switch (cycle) {
        'yearly' => monthly * 12,
        'semiannual' => monthly * 6,
        'quarterly' => monthly * 3,
        'weekly' => monthly * 12 / 52,
        'biweekly' => monthly / 2.174,
        _ => monthly,
      };

  // Fixed ids for the schedule-wide notifications. Hashed payee ids are masked
  // to 30 bits, so these low, hand-picked numbers cannot be hit by a payee name.
  static const _idReportBase = 10;   // + month index, 10..21
  static const _idConsent7 = 30;
  static const _idConsent1 = 31;
  static const _idBudget = 40;

  /// "Last month is ready" — the first of each month, for a year ahead.
  ///
  /// On the 1st rather than the last day of the month: on the 31st the month is
  /// still running, so any total shown would be wrong by whatever is spent that
  /// evening. A report is worth reading once it is final.
  Future<void> _scheduleMonthlyReport(
      tz.TZDateTime now, bool isLithuanian) async {
    for (var i = 0; i < 12; i++) {
      final m = DateTime(now.year, now.month + 1 + i, 1);
      final at = tz.TZDateTime(tz.local, m.year, m.month, m.day, _remindHour);
      if (!at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: _idReportBase + i,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Vaultie 📊',
        body: isLithuanian
            ? 'Praėjusio mėnesio ataskaita paruošta — pažiūrėk, kur nuėjo pinigai.'
            : "Last month's report is ready — see where the money went.",
      );
    }
  }

  /// Bank access lapses after ~90 days (PSD2 re-consent). Warned at 7 days and
  /// again the day before.
  ///
  /// This is the only reminder that decides whether the app keeps working at
  /// all: when the consent runs out the bank simply stops answering, the
  /// figures quietly stop moving, and nothing on screen says why. Everything
  /// else here is a convenience; this one prevents a silent failure.
  Future<void> _scheduleConsentExpiry(
      tz.TZDateTime now, DateTime? expiry, bool isLithuanian) async {
    if (expiry == null) return;
    for (final (id, days) in [(_idConsent7, 7), (_idConsent1, 1)]) {
      final d = expiry.subtract(Duration(days: days));
      final at = tz.TZDateTime(tz.local, d.year, d.month, d.day, _remindHour);
      if (!at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Vaultie 🔗',
        body: isLithuanian
            ? (days == 1
                ? 'Rytoj baigiasi banko prieiga. Prisijunk iš naujo, kad duomenys nesustotų.'
                : 'Po 7 d. baigiasi banko prieiga — reikės prisijungti iš naujo.')
            : (days == 1
                ? 'Bank access expires tomorrow. Reconnect to keep your data flowing.'
                : 'Bank access expires in 7 days — you will need to reconnect.'),
      );
    }
  }

  /// A nudge when the month's spending is closing on the budget.
  ///
  /// Deliberately worded as "by the last check". Vaultie has no push and no
  /// background refresh, so the only spending figure it can ever schedule
  /// against is the one from the last time the app was open — by tonight it may
  /// be out of date. Claiming a live number would be a lie about somebody's
  /// money; saying which number it is costs nothing and is true.
  Future<void> _scheduleBudgetWarning(tz.TZDateTime now, double? spent,
      double? budget, bool isLithuanian) async {
    if (spent == null || budget == null || budget <= 0) return;
    final pct = spent / budget;
    if (pct < 0.8) return;
    // This evening, or tomorrow evening if the day is already past it.
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, _budgetHour);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    // Never carry the warning into a month whose spending it does not describe.
    if (at.month != now.month) return;
    final shown = (pct * 100).round();
    await _plugin.zonedSchedule(
      id: _idBudget,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: 'Vaultie 🎯',
      body: isLithuanian
          ? (pct >= 1
              ? 'Mėnesio biudžetas viršytas — pagal paskutinį patikrinimą $shown %.'
              : 'Išleista $shown % mėnesio biudžeto (pagal paskutinį patikrinimą).')
          : (pct >= 1
              ? "You're over the monthly budget — $shown % at the last check."
              : "You've used $shown % of the monthly budget (at the last check)."),
    );
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
