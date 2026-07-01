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
  });

  final String id;
  final String name;
  final double cost;
  final BillingCycle billingCycle;
  final String category;
  final DateTime nextBillingDate;
  final int colorValue;

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

  Subscription copyWith({
    String? name,
    double? cost,
    BillingCycle? billingCycle,
    String? category,
    DateTime? nextBillingDate,
    int? colorValue,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      cost: cost ?? this.cost,
      billingCycle: billingCycle ?? this.billingCycle,
      category: category ?? this.category,
      nextBillingDate: nextBillingDate ?? this.nextBillingDate,
      colorValue: colorValue ?? this.colorValue,
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
    );
  }

  @override
  void write(BinaryWriter writer, Subscription obj) {
    writer
      ..writeByte(7)
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
      ..write(obj.colorValue);
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
