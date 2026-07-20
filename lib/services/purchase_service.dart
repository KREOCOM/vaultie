import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../main.dart';

/// Free users may track this many subscriptions before hitting the paywall.
const int kFreeSubscriptionLimit = 5;

/// The plans offered on the paywall.
///
/// The one-time "lifetime" plan is retired: at €29.99 it undercut the €39.99
/// yearly plan, so nobody would ever have bought the subscription. The product
/// still exists in App Store Connect so previous buyers keep their access —
/// their entitlement is "Vaultie Pro" like everyone else's, and [restore] is
/// entitlement-based, so it works without the plan appearing here.
enum PlanId { monthly, yearly }

/// A purchasable plan. Prices live here so a real billing backend (RevenueCat)
/// can later populate them from live store products instead of hard-coding.
class PurchasePlan {
  const PurchasePlan({required this.id, required this.price});

  final PlanId id;
  final String price;

  bool get isYearly => id == PlanId.yearly;
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
  /// App-wide instance. Backed by RevenueCat in production; swap for
  /// [MockPurchaseService] in tests or offline previews.
  static PurchaseService instance = RevenueCatPurchaseService();

  /// Fallback plan prices shown on the paywall before live store prices load
  /// (and if offerings can't be fetched). The live, localized prices from
  /// [priceString] take precedence when available.
  static const List<PurchasePlan> plans = [
    PurchasePlan(id: PlanId.monthly, price: '€4.99'),
    PurchasePlan(id: PlanId.yearly, price: '€39.99'),
  ];

  static PurchasePlan planFor(PlanId id) => plans.firstWhere((p) => p.id == id);

  /// Configures billing and loads the current entitlement. Call once at startup.
  Future<void> init();

  /// Whether the user currently has premium (unlimited) access.
  bool get isPremium;

  /// Reactive view of [isPremium] for widgets that rebuild on change.
  ValueListenable<bool> get isPremiumListenable;

  /// Live, localized store price for [id] (e.g. "\$2.99"), or null if offerings
  /// haven't loaded — callers fall back to the static [plans] price.
  String? priceString(PlanId id);

  /// Length in days of the free trial the store actually offers on [id], or
  /// null if there is none.
  ///
  /// Read from the live store product rather than a hand-set flag, so the
  /// paywall advertises a trial exactly when one really exists. Promising a
  /// free trial that isn't configured in App Store Connect is a Guideline
  /// 3.1.2 rejection, and a flag someone forgot to flip is how that happens.
  int? freeTrialDays(PlanId id);

  /// Attempts to purchase [id]; grants premium on success.
  Future<PurchaseResult> purchase(PlanId id);

  /// Restores a previous purchase, if any.
  Future<PurchaseResult> restore();

  /// Associates billing with the signed-in app account [uid] (or signs out when
  /// null) so the premium entitlement follows the *account*, not the device.
  /// Refreshes the cached premium state to match.
  Future<void> setUser(String? uid);
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
  String? priceString(PlanId id) => null; // fall back to static plan prices

  @override
  int? freeTrialDays(PlanId id) => null; // no store, so no offer to report

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

  @override
  Future<void> setUser(String? uid) async {
    // Local mock: premium is just the cached flag (cleared on account wipe).
    _premium.value = _box.get(_premiumKey, defaultValue: false) as bool;
  }
}

/// Live [PurchaseService] backed by RevenueCat.
///
/// Entitlement "Vaultie Pro" gates premium. Products are matched to our
/// [PlanId]s by their store identifiers (see [_productIds]). Prices and the
/// purchasable packages come from the current RevenueCat offering, so pricing
/// is controlled in the RevenueCat dashboard rather than hard-coded.
class RevenueCatPurchaseService implements PurchaseService {
  /// Entitlement identifier configured in the RevenueCat dashboard.
  static const _entitlementId = 'Vaultie Pro';

  /// Store product identifiers, mapped to our plan enum. These must match the
  /// product IDs in App Store Connect exactly, and both products must sit in
  /// the current RevenueCat offering or [purchase] returns [notFound].
  ///
  /// The retired `...pro.lifetime` product is deliberately absent: it stays
  /// purchasable-in-name-only for past buyers but must never appear as an
  /// option, so it is left unmapped and simply ignored in the offering.
  static const _productIds = {
    'com.kreocom.vaultie.pro.monthly': PlanId.monthly,
    'com.kreocom.vaultie.pro.yearly': PlanId.yearly,
  };

  /// RevenueCat public SDK keys. iOS is live now; add the Android key when
  /// Android ships.
  static const _iosApiKey = 'appl_JazDoCzvsSABSIIooMqzkqKorso';

  static const _premiumKey = 'premium';

  final ValueNotifier<bool> _premium = ValueNotifier<bool>(false);

  /// Purchasable package + localized price per plan, from the current offering.
  final Map<PlanId, rc.Package> _packages = {};
  final Map<PlanId, String> _prices = {};

  /// Free-trial length per plan, in days, for plans whose store product carries
  /// a zero-price introductory offer.
  final Map<PlanId, int> _trialDays = {};

  Box get _box => Hive.box(HiveBoxes.settings);

  String get _apiKey {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _iosApiKey;
    // Android/other platforms aren't wired up yet.
    throw UnsupportedError('RevenueCat is only configured for iOS.');
  }

  @override
  Future<void> init() async {
    // Seed from the last known entitlement so gating is correct instantly,
    // before the network round-trip resolves.
    _premium.value = _box.get(_premiumKey, defaultValue: false) as bool;

    await rc.Purchases.setLogLevel(
        kDebugMode ? rc.LogLevel.debug : rc.LogLevel.info);
    await rc.Purchases.configure(rc.PurchasesConfiguration(_apiKey));

    // Stay in sync with entitlement changes the SDK pushes (renewals,
    // expirations, purchases made elsewhere).
    rc.Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);

    try {
      _applyCustomerInfo(await rc.Purchases.getCustomerInfo());
    } catch (_) {
      // Offline at launch — keep the cached entitlement until we reconnect.
    }
    await _loadOfferings();
  }

  /// Fetches the current offering and caches each plan's package and price.
  Future<void> _loadOfferings() async {
    try {
      final offerings = await rc.Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return;
      for (final pkg in current.availablePackages) {
        final plan = _productIds[pkg.storeProduct.identifier];
        if (plan != null) {
          _packages[plan] = pkg;
          _prices[plan] = pkg.storeProduct.priceString;
          final days = _trialDaysOf(pkg.storeProduct);
          if (days != null) _trialDays[plan] = days;
        }
      }
    } catch (_) {
      // Leave prices to the static fallback if offerings can't be fetched.
    }
  }

  /// The free-trial length of [product] in days, or null if its introductory
  /// offer isn't a free trial (or there is none).
  ///
  /// Only a zero-price introductory offer counts. A discounted-but-paid intro
  /// offer is also an "introductory price" to StoreKit, and calling that a free
  /// trial on the paywall would charge people who were told they wouldn't be.
  static int? _trialDaysOf(rc.StoreProduct product) {
    final intro = product.introductoryPrice;
    if (intro == null || intro.price != 0) return null;
    final n = intro.periodNumberOfUnits;
    return switch (intro.periodUnit) {
      rc.PeriodUnit.day => n,
      rc.PeriodUnit.week => n * 7,
      rc.PeriodUnit.month => n * 30,
      rc.PeriodUnit.year => n * 365,
      _ => null,
    };
  }

  /// Reflects RevenueCat's entitlement state into [_premium] and persists it so
  /// the next cold start knows the answer before the network responds.
  void _applyCustomerInfo(rc.CustomerInfo info) {
    final active = info.entitlements.active.containsKey(_entitlementId);
    _premium.value = active;
    _box.put(_premiumKey, active);
  }

  @override
  bool get isPremium => _premium.value;

  @override
  ValueListenable<bool> get isPremiumListenable => _premium;

  @override
  String? priceString(PlanId id) => _prices[id];

  @override
  int? freeTrialDays(PlanId id) => _trialDays[id];

  @override
  Future<PurchaseResult> purchase(PlanId id) async {
    final pkg = _packages[id];
    if (pkg == null) {
      // Offerings never loaded (offline, or product not configured yet).
      return const PurchaseResult(PurchaseStatus.notFound);
    }
    try {
      final result =
          await rc.Purchases.purchase(rc.PurchaseParams.package(pkg));
      if (result.customerInfo.entitlements.active.containsKey(_entitlementId)) {
        _premium.value = true;
        await _box.put(_premiumKey, true);
        return const PurchaseResult(PurchaseStatus.success);
      }
      return const PurchaseResult(PurchaseStatus.error);
    } on PlatformException catch (e) {
      final code = rc.PurchasesErrorHelper.getErrorCode(e);
      if (code == rc.PurchasesErrorCode.purchaseCancelledError) {
        return const PurchaseResult(PurchaseStatus.cancelled);
      }
      return PurchaseResult(PurchaseStatus.error, e.message);
    }
  }

  @override
  Future<PurchaseResult> restore() async {
    try {
      final info = await rc.Purchases.restorePurchases();
      if (info.entitlements.active.containsKey(_entitlementId)) {
        _premium.value = true;
        await _box.put(_premiumKey, true);
        return const PurchaseResult(PurchaseStatus.success);
      }
      return const PurchaseResult(PurchaseStatus.notFound);
    } on PlatformException catch (e) {
      return PurchaseResult(PurchaseStatus.error, e.message);
    }
  }

  @override
  Future<void> setUser(String? uid) async {
    // Tie RevenueCat to the app account so entitlements follow the account, not
    // the device: logIn on sign-in, logOut on sign-out. Then refresh premium.
    try {
      final rc.CustomerInfo info;
      if (uid != null) {
        info = (await rc.Purchases.logIn(uid)).customerInfo;
      } else {
        info = await rc.Purchases.logOut();
      }
      _applyCustomerInfo(info);
    } catch (_) {
      // Offline, not configured, or already anonymous — fall back to the cached
      // flag (which the account wipe clears).
      _premium.value = _box.get(_premiumKey, defaultValue: false) as bool;
    }
  }
}
