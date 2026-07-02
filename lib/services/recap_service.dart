import 'package:hive/hive.dart';

import '../main.dart';
import '../models/subscription.dart';

/// A snapshot of one month's subscription spend, used by the Monthly Recap.
class MonthlyRecap {
  MonthlyRecap({
    required this.month,
    required this.total,
    required this.count,
    required this.topName,
    required this.topCost,
    required this.prevTotal,
  });

  /// Month key, e.g. "2026-07".
  final String month;
  final double total; // monthly recurring cost that month
  final int count;
  final String? topName; // most expensive subscription
  final double topCost;
  final double? prevTotal; // month-before total, or null when unavailable

  int get monthNumber => int.tryParse(month.split('-').last) ?? 1;

  /// Per-day cost, matching the app's "per day" definition (yearly / 365).
  double get perDay => total * 12 / 365;

  /// Signed % change vs the previous month, or null when there's no comparison.
  double? get changePercent {
    final p = prevTotal;
    if (p == null || p <= 0) return null;
    return (total - p) / p * 100;
  }
}

String _monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Stores per-month spend snapshots (in the `monthlyStats` box) and decides
/// when to surface the recap of the just-ended month.
///
/// The app keeps no historical charge data, so each launch snapshots the
/// *current* month's live state; when a new month begins, the prior month's
/// last snapshot is what the recap shows (an approximation, not a statement).
class RecapService {
  static Box get _stats => Hive.box(HiveBoxes.monthlyStats);
  static Box get _settings => Hive.box(HiveBoxes.settings);

  /// Snapshots this month's spend from the live subscriptions. Safe to call on
  /// every launch — it just overwrites the current month's entry.
  static void recordCurrentMonth(List<Subscription> subs) {
    Subscription? top;
    for (final s in subs) {
      if (top == null || s.monthlyCost > top.monthlyCost) top = s;
    }
    _stats.put(_monthKey(DateTime.now()), {
      'total': subs.fold<double>(0, (sum, s) => sum + s.monthlyCost),
      'count': subs.length,
      'topName': top?.name,
      'topCost': top?.monthlyCost ?? 0.0,
    });
  }

  /// Last month's recap if it exists and hasn't been shown this month yet.
  static MonthlyRecap? pendingRecap() {
    final now = DateTime.now();
    if (_settings.get('lastRecapMonth') == _monthKey(now)) return null;

    final prevKey = _monthKey(DateTime(now.year, now.month - 1, 1));
    final prev = _stats.get(prevKey);
    if (prev == null) return null;
    final prevMap = Map<String, dynamic>.from(prev as Map);

    final prevPrev =
        _stats.get(_monthKey(DateTime(now.year, now.month - 2, 1)));
    final double? prevTotal = prevPrev == null
        ? null
        : (Map<String, dynamic>.from(prevPrev as Map)['total'] as num)
            .toDouble();

    return MonthlyRecap(
      month: prevKey,
      total: (prevMap['total'] as num).toDouble(),
      count: (prevMap['count'] as num).toInt(),
      topName: prevMap['topName'] as String?,
      topCost: (prevMap['topCost'] as num?)?.toDouble() ?? 0,
      prevTotal: prevTotal,
    );
  }

  /// Marks the recap as shown for the current month so it appears only once.
  static void markShown() {
    _settings.put('lastRecapMonth', _monthKey(DateTime.now()));
  }
}
