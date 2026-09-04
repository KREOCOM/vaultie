import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/logic/display_currency.dart';

const _rates = {'USD': 1.08, 'GBP': 0.85, 'NOK': 11.4};

void main() {
  group('the rate and the symbol move together', () {
    test('a known currency converts and carries its own symbol', () {
      final d = resolveDisplayCurrency('USD', r'$', _rates);
      expect(d.rate, 1.08);
      expect(d.symbol, r'$');
      expect(d.converted, isTrue);
    });

    test('EUR is the base and never needs a rate', () {
      final d = resolveDisplayCurrency('EUR', '€', const {});
      expect(d.rate, 1.0);
      expect(d.symbol, '€');
      expect(d.converted, isTrue);
    });

    test('no rate means euros AND the euro sign — never a foreign sign on an '
        'unconverted number', () {
      // This is the "7 049 € shown as 7 049 £" failure: wrong by a fifth and
      // stated as confidently as a correct number.
      final d = resolveDisplayCurrency('GBP', '£', const {});
      expect(d.rate, 1.0);
      expect(d.symbol, '€');
      expect(d.converted, isFalse);
    });

    test('a broken feed is not a currency', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final d = resolveDisplayCurrency('USD', r'$', {'USD': bad});
        expect(d.converted, isFalse, reason: 'rate $bad must not be used');
        expect(d.rate, 1.0);
        expect(d.symbol, '€');
      }
    });

    test('an unconverted result never claims the chosen symbol', () {
      for (final code in ['USD', 'GBP', 'JPY', 'PLN']) {
        final d = resolveDisplayCurrency(code, 'X', const {});
        expect(d.symbol, '€');
        expect(d.rate, 1.0);
      }
    });

    test('case and padding do not change the answer', () {
      expect(resolveDisplayCurrency(' usd ', r'$', _rates).rate, 1.08);
      expect(resolveDisplayCurrency('', '€', _rates).converted, isTrue);
    });
  });

  group('the picker only offers what can work', () {
    test('a currency with a rate is offered', () {
      expect(canDisplayCurrency('NOK', _rates), isTrue);
      expect(canDisplayCurrency('EUR', const {}), isTrue);
    });

    test('a currency without a rate is not', () {
      // Offering it and then quietly staying in euros is the failure this
      // guards: the user taps, nothing changes, nothing explains it.
      expect(canDisplayCurrency('JPY', _rates), isFalse);
      expect(canDisplayCurrency('USD', const {}), isFalse);
    });
  });
}
