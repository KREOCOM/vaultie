import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/logic/paywall_prices.dart';

const _fallback =
    PaywallPrices(monthly: 4.99, yearly: 39.99, currency: 'EUR');

void main() {
  group('which prices win', () {
    test('live store prices are used when both plans have loaded', () {
      final p = PaywallPrices.from(
          monthly: 5.99, yearly: 49.99, currency: 'USD', fallback: _fallback);
      expect(p.monthly, 5.99);
      expect(p.yearly, 49.99);
      expect(p.currency, 'USD');
    });

    test('one live price alone falls back — a mixed pair invents a discount',
        () {
      // Live yearly 49.99 against the hard-coded monthly 4.99 would advertise a
      // 16% saving that is not on offer anywhere.
      final p = PaywallPrices.from(
          monthly: null, yearly: 49.99, currency: 'USD', fallback: _fallback);
      expect(p.monthly, _fallback.monthly);
      expect(p.yearly, _fallback.yearly);
      expect(p.currency, 'EUR');
    });

    test('zero or missing prices fall back', () {
      final zero = PaywallPrices.from(
          monthly: 0, yearly: 49.99, currency: 'USD', fallback: _fallback);
      expect(zero.currency, 'EUR');
      final none = PaywallPrices.from(
          monthly: null, yearly: null, currency: null, fallback: _fallback);
      expect(none.monthly, 4.99);
    });

    test('a live price with no currency code keeps the fallback currency', () {
      final p = PaywallPrices.from(
          monthly: 5.99, yearly: 49.99, currency: null, fallback: _fallback);
      expect(p.currency, 'EUR');
    });
  });

  group('derived figures', () {
    test('every figure comes from the SAME pair of prices', () {
      const p = PaywallPrices(monthly: 5.99, yearly: 49.99, currency: 'USD');
      expect(p.yearOfMonthly, closeTo(71.88, 0.001));
      expect(p.saving, closeTo(21.89, 0.001));
      expect(p.yearlyPerMonth, closeTo(4.1658, 0.001));
      expect(p.discount, 30);
    });

    test('the EUR fallback still produces the advertised 33%', () {
      expect(_fallback.discount, 33);
    });

    test('a yearly plan that costs MORE never shows a negative discount', () {
      const p = PaywallPrices(monthly: 1.00, yearly: 99.00, currency: 'EUR');
      expect(p.saving, lessThan(0));
      expect(p.discount, 0);
    });
  });

  group('formatting', () {
    test('derived figures carry the store currency, not a pasted euro sign', () {
      const p = PaywallPrices(monthly: 5.99, yearly: 49.99, currency: 'USD');
      final s = p.format(p.yearlyPerMonth, 'en_US');
      expect(s, contains('4.17'));
      expect(s, isNot(contains('€')));
    });

    test('EUR formats as euro', () {
      final s = _fallback.format(_fallback.yearlyPerMonth, 'lt');
      expect(s, contains('3,33'));
    });
  });
}
