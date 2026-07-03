import 'package:hive/hive.dart';

/// How often a subscription is billed.
enum BillingCycle { weekly, monthly, quarterly, yearly }

extension BillingCycleX on BillingCycle {
  String get label => switch (this) {
        BillingCycle.weekly => 'Weekly',
        BillingCycle.monthly => 'Monthly',
        BillingCycle.quarterly => 'Quarterly',
        BillingCycle.yearly => 'Yearly',
      };

  /// Multiplier to normalise a single charge into a monthly figure.
  double get monthlyFactor => switch (this) {
        BillingCycle.weekly => 52 / 12,
        BillingCycle.monthly => 1,
        BillingCycle.quarterly => 1 / 3,
        BillingCycle.yearly => 1 / 12,
      };

  /// Days between charges — used to advance [Subscription.nextBillingDate].
  int get approxDays => switch (this) {
        BillingCycle.weekly => 7,
        BillingCycle.monthly => 30,
        BillingCycle.quarterly => 91,
        BillingCycle.yearly => 365,
      };

  /// [from] advanced by exactly one billing cycle.
  ///
  /// Uses calendar arithmetic (not [approxDays]) so a charge on the 15th stays
  /// on the 15th. For monthly/quarterly/yearly cycles the day-of-month is
  /// clamped to the last day of the target month, so a charge on the 29th–31st
  /// never overflows into the next month (Jan 31 + 1 month → Feb 28/29, not
  /// early March).
  DateTime advance(DateTime from) => switch (this) {
        BillingCycle.weekly => from.add(const Duration(days: 7)),
        BillingCycle.monthly => _addMonths(from, 1),
        BillingCycle.quarterly => _addMonths(from, 3),
        BillingCycle.yearly => _addMonths(from, 12),
      };
}

/// Adds [months] calendar months to [from], clamping the day-of-month to the
/// last valid day of the target month. Without this, `DateTime` overflows a
/// too-large day into the following month (e.g. Feb 31 → March 3), which would
/// silently skip a billing month for subscriptions charged on the 29th–31st.
DateTime _addMonths(DateTime from, int months) {
  final zeroBasedMonth = from.month - 1 + months;
  final year = from.year + zeroBasedMonth ~/ 12;
  final month = zeroBasedMonth % 12 + 1;
  // Day 0 of the *next* month resolves to the last day of the target month.
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = from.day < lastDay ? from.day : lastDay;
  return DateTime(year, month, day);
}

/// A single recurring subscription tracked in the vault.
///
/// The Hive [TypeAdapter] is hand-written below ([SubscriptionAdapter]) so the
/// project compiles and runs without invoking build_runner. If you prefer
/// generated adapters, annotate this class with @HiveType / @HiveField and run
/// `dart run build_runner build`.
class Subscription {
  Subscription({
    required this.id,
    required this.name,
    required this.cost,
    required this.billingCycle,
    required this.category,
    required this.nextBillingDate,
    this.colorValue = 0xFF174E35,
    this.isEstimated = false,
    this.notes,
    this.logoDomain,
  });

  final String id;
  final String name;
  final double cost;
  final BillingCycle billingCycle;
  final String category;
  final DateTime nextBillingDate;
  final int colorValue;

  /// True when [cost] is an approximation of a variable bill (e.g. utilities
  /// that change month to month). The amount is still used in totals; the UI
  /// just marks it as an estimate ("~€60").
  final bool isEstimated;

  /// Optional free-text note the user attached to this expense.
  final String? notes;

  /// Optional brand domain (e.g. "netflix.com") used to fetch a logo. When set,
  /// the avatar shows that brand logo; otherwise it falls back to the category
  /// icon. Keeps generic bills (rent, insurance) from guessing a wrong logo.
  final String? logoDomain;

  /// Cost normalised to a per-month figure for analytics.
  double get monthlyCost => cost * billingCycle.monthlyFactor;

  /// Cost normalised to a per-year figure.
  double get yearlyCost => monthlyCost * 12;

  int get daysUntilRenewal {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(
      nextBillingDate.year,
      nextBillingDate.month,
      nextBillingDate.day,
    );
    return due.difference(today).inDays;
  }

  /// The next billing date that is today or later, rolling any elapsed cycles
  /// forward. Returns [nextBillingDate] unchanged when it hasn't passed yet.
  ///
  /// Used by the launch-time reschedule pass so a subscription whose renewal
  /// date has slipped into the past advances to its next real occurrence.
  DateTime rolledForwardBillingDate([DateTime? now]) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    var d = nextBillingDate;
    // Guard against pathological loops; 1000 weekly cycles is ~19 years.
    var guard = 0;
    while (DateTime(d.year, d.month, d.day).isBefore(today) && guard++ < 1000) {
      d = billingCycle.advance(d);
    }
    return d;
  }

  Subscription copyWith({
    String? name,
    double? cost,
    BillingCycle? billingCycle,
    String? category,
    DateTime? nextBillingDate,
    int? colorValue,
    bool? isEstimated,
    String? notes,
    String? logoDomain,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      cost: cost ?? this.cost,
      billingCycle: billingCycle ?? this.billingCycle,
      category: category ?? this.category,
      nextBillingDate: nextBillingDate ?? this.nextBillingDate,
      colorValue: colorValue ?? this.colorValue,
      isEstimated: isEstimated ?? this.isEstimated,
      notes: notes ?? this.notes,
      logoDomain: logoDomain ?? this.logoDomain,
    );
  }
}

/// Hand-written Hive adapter for [Subscription].
class SubscriptionAdapter extends TypeAdapter<Subscription> {
  @override
  final int typeId = 1;

  @override
  Subscription read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    return Subscription(
      id: fields[0] as String,
      name: fields[1] as String,
      cost: fields[2] as double,
      billingCycle: BillingCycle.values[fields[3] as int],
      category: fields[4] as String,
      nextBillingDate: DateTime.fromMillisecondsSinceEpoch(fields[5] as int),
      colorValue: fields[6] as int? ?? 0xFF174E35,
      // Fields 7–9 were added later; older records default them.
      isEstimated: fields[7] as bool? ?? false,
      notes: fields[8] as String?,
      logoDomain: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Subscription obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.cost)
      ..writeByte(3)
      ..write(obj.billingCycle.index)
      ..writeByte(4)
      ..write(obj.category)
      ..writeByte(5)
      ..write(obj.nextBillingDate.millisecondsSinceEpoch)
      ..writeByte(6)
      ..write(obj.colorValue)
      ..writeByte(7)
      ..write(obj.isEstimated)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.logoDomain);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionAdapter && runtimeType == other.runtimeType;
}

/// Convenient catalogue of categories used by the add/analytics screens.
class SubscriptionCategory {
  static const List<String> all = [
    'Streaming',
    'Music',
    'Software',
    'Gaming',
    'News',
    'Fitness',
    'Cloud',
    'Other',
  ];
}
