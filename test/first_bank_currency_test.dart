import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/screens/bank_connect_screen.dart';

/// Connecting a Norwegian bank first used to leave the display currency at
/// its untouched EUR default — every figure, including the person's own
/// kroner balance, showed converted to euros with nothing to say why.
/// detectFirstBankCurrency() is the pure part of the fix: given the accounts
/// a first bank connection returned, what (if anything) the display currency
/// should switch to.
void main() {
  Map<String, dynamic> acct(String currency) => {
        'uid': 'u',
        'iban': 'LT00',
        'name': 'Acc',
        'currency': currency,
      };

  test('a single NOK account switches to NOK', () {
    expect(detectFirstBankCurrency([acct('NOK')]), 'NOK');
  });

  test('an all-EUR connection detects nothing — EUR is already the default',
      () {
    expect(detectFirstBankCurrency([acct('EUR'), acct('EUR')]), isNull);
  });

  test('no accounts at all detects nothing', () {
    expect(detectFirstBankCurrency(const []), isNull);
  });

  test('mixed currencies pick the majority by account count', () {
    // 1 EUR + 2 NOK — a Revolut-style multi-wallet connect.
    expect(
      detectFirstBankCurrency([acct('EUR'), acct('NOK'), acct('NOK')]),
      'NOK',
    );
  });

  test('a tie picks whichever currency was seen first', () {
    expect(
      detectFirstBankCurrency([acct('SEK'), acct('NOK')]),
      'SEK',
    );
  });

  test('currency codes are case-insensitive', () {
    expect(detectFirstBankCurrency([acct('nok')]), 'NOK');
  });

  test('a blank or missing currency field is ignored, not miscounted', () {
    expect(
      detectFirstBankCurrency([acct(''), acct('NOK'), acct('NOK')]),
      'NOK',
    );
  });

  test('an exotic currency the picker has no live rate for detects nothing',
      () {
    // currencyByCode() falls back to its EUR entry for anything it doesn't
    // carry — switching the display currency to a code the picker can't
    // actually resolve a name or symbol for would be worse than staying EUR.
    expect(detectFirstBankCurrency([acct('XYZ')]), isNull);
  });
}
