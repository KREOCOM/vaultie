import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';

/// Free users may track this many subscriptions before hitting the paywall.
const int kFreeSubscriptionLimit = 3;

/// The plans offered on the paywall.
enum PlanId { monthly, lifetime }

/// A purchasable plan. Prices live here so a real billing backend (RevenueCat)
/// can later populate them from live store products instead of hard-coding.
class PurchasePlan {
  const PurchasePlan({required this.id, required this.price});

  final PlanId id;
  final String price;

  bool get isLifetime => id == PlanId.lifetime;
}

/// Outcome of a purchase or restore attempt.
enum PurchaseStatus { success, cancelled, notFound, error }

class PurchaseResult {
  const PurchaseResult(this.status, [this.message]);

  final PurchaseStatus status;
  final String? message;

  bool get isSuccess => status == PurchaseStatus.success;
}

/// Abstraction over in-app purchases / entitlements.
///
/// The rest of the app talks only to this interface — never to a billing SDK
/// directly — so RevenueCat can be dropped in later by writing a
/// `RevenueCatPurchaseService implements PurchaseService` and swapping
/// [instance] in `main()`. No paywall or gating code needs to change.
abstract class PurchaseService {
  /// App-wide instance. To go live, replace the mock here:
  ///   `PurchaseService.instance = RevenueCatPurchaseService();`
  static PurchaseService instance = MockPurchaseService();

  /// Plans shown on the paywall (single source of truth for pricing).
  static const List<PurchasePlan> plans = [
    PurchasePlan(id: PlanId.monthly, price: '€2.99'),
    PurchasePlan(id: PlanId.lifetime, price: '€30'),
  ];

  static PurchasePlan planFor(PlanId id) => plans.firstWhere((p) => p.id == id);

  /// Loads any persisted entitlement. Call once at startup.
  Future<void> init();

  /// Whether the user currently has premium (unlimited) access.
  bool get isPremium;

  /// Reactive view of [isPremium] for widgets that rebuild on change.
  ValueListenable<bool> get isPremiumListenable;

  /// Attempts to purchase [id]; grants premium on success.
  Future<PurchaseResult> purchase(PlanId id);

  /// Restores a previous purchase, if any.
  Future<PurchaseResult> restore();
}

/// On-device mock. Grants premium after a short fake "store round-trip" and
/// persists it in the Hive settings box so it survives restarts. No real money
/// changes hands — this exists purely so the paywall flow is fully wired up
/// until RevenueCat is integrated.
class MockPurchaseService implements PurchaseService {
  static const _premiumKey = 'premium';

  final ValueNotifier<bool> _premium = ValueNotifier<bool>(false);

  Box get _box => Hive.box(HiveBoxes.settings);

  @override
  Future<void> init() async {
    _premium.value = _box.get(_premiumKey, defaultValue: false) as bool;
  }

  @override
  bool get isPremium => _premium.value;

  @override
  ValueListenable<bool> get isPremiumListenable => _premium;

  @override
  Future<PurchaseResult> purchase(PlanId id) async {
    // Simulate a store round-trip so the UI's busy state is exercised.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    await _box.put(_premiumKey, true);
    _premium.value = true;
    return const PurchaseResult(PurchaseStatus.success);
  }

  @override
  Future<PurchaseResult> restore() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_box.get(_premiumKey, defaultValue: false) as bool) {
      _premium.value = true;
      return const PurchaseResult(PurchaseStatus.success);
    }
    return const PurchaseResult(PurchaseStatus.notFound);
  }
}
