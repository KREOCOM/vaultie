/// What to display amounts in, decided in ONE place.
///
/// Amounts are stored in EUR everywhere. Turning them into what the user sees is
/// two numbers that must never be chosen independently: the EUR→currency rate,
/// and the symbol printed after it. Setting them separately is how "7 049 €"
/// once appeared as "7 049 £" — the untouched euro figure under a pound sign,
/// wrong by a fifth and stated as confidently as a correct number.
class DisplayCurrency {
  const DisplayCurrency({
    required this.code,
    required this.rate,
    required this.symbol,
    required this.converted,
  });

  final String code;

  /// Multiply a stored EUR amount by this to get the displayed amount.
  final double rate;

  /// Printed after the amount. Always the symbol of the currency the number is
  /// ACTUALLY in — never the one the user asked for while the number stayed EUR.
  final String symbol;

  /// Whether the user's chosen currency could actually be applied. False means
  /// we are showing euros because no rate was available; the UI must say so
  /// rather than let the choice look like it took effect.
  final bool converted;
}

const _eur = DisplayCurrency(
    code: 'EUR', rate: 1.0, symbol: '€', converted: true);

/// Resolve the display currency for [code] against the known [rates]
/// (EUR→code). [symbol] is the symbol for [code] from the catalogue.
///
/// Falling back to euros is always TRUTHFUL — the stored amounts are euros — so
/// the fallback is safe. What is not safe is doing it quietly, which is why the
/// result carries [DisplayCurrency.converted] instead of the caller having to
/// re-derive whether the choice worked.
DisplayCurrency resolveDisplayCurrency(
    String code, String symbol, Map<String, double> rates) {
  final c = code.trim().toUpperCase();
  if (c.isEmpty || c == 'EUR') return _eur;
  final rate = rates[c];
  // A non-positive or non-finite rate is a broken feed, not a currency: using it
  // would turn every amount into 0 or NaN.
  if (rate == null || !rate.isFinite || rate <= 0) {
    return DisplayCurrency(
        code: c, rate: 1.0, symbol: '€', converted: false);
  }
  return DisplayCurrency(
      code: c, rate: rate, symbol: symbol, converted: true);
}

/// Whether the app can actually show amounts in [code] right now. The currency
/// picker uses this so a user is never offered a choice that would silently do
/// nothing.
bool canDisplayCurrency(String code, Map<String, double> rates) =>
    resolveDisplayCurrency(code, '?', rates).converted;
