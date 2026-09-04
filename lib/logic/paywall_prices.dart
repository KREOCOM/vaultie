import 'package:intl/intl.dart';

/// The money figures shown on the paywall, all in ONE currency.
///
/// Lives outside the paywall widget so it can be tested. The figures used to be
/// `const` arithmetic on hard-coded euro constants while the plan price itself
/// came from the store, which outside the eurozone put "3,33 €/mo" and
/// "Sutaupai 19,89 €" directly underneath a plan the App Store was showing as
/// "$5.99" — three currencies describing one purchase. A price is a number plus
/// a currency and the two must travel together.
class PaywallPrices {
  const PaywallPrices({
    required this.monthly,
    required this.yearly,
    required this.currency,
  });

  /// Live store prices when BOTH plans have loaded, otherwise [fallback].
  ///
  /// Both are required on purpose: deriving "you save" from a live yearly price
  /// and a hard-coded monthly one invents a discount that is not on offer.
  factory PaywallPrices.from({
    required double? monthly,
    required double? yearly,
    required String? currency,
    required PaywallPrices fallback,
  }) {
    if (monthly != null && yearly != null && monthly > 0 && yearly > 0) {
      return PaywallPrices(
        monthly: monthly,
        yearly: yearly,
        currency: currency ?? fallback.currency,
      );
    }
    return fallback;
  }

  final double monthly;
  final double yearly;
  final String currency;

  double get yearOfMonthly => monthly * 12;
  double get saving => yearOfMonthly - yearly;
  double get yearlyPerMonth => yearly / 12;

  /// Percent saved by paying yearly. Clamped at 0: a store that prices the
  /// yearly plan ABOVE twelve monthly charges must not advertise a negative
  /// discount as if it were one.
  int get discount {
    if (yearOfMonthly <= 0 || saving <= 0) return 0;
    return (saving / yearOfMonthly * 100).round();
  }

  /// Formats in the STORE's currency, in the app's language, so a derived figure
  /// reads like the store's own price rather than a euro amount pasted under it.
  String format(double v, String locale) =>
      NumberFormat.simpleCurrency(locale: locale, name: currency).format(v);
}
