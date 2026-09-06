import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/screens/preview/dashboard_preview.dart';

/// Lithuanian number agreement.
///
/// The accounts list printed "1 tuščios" — plural after 1 — which reads as
/// broken Lithuanian to every native speaker, on a screen they open to check
/// their own money. English needs no agreement so it was never noticed, and the
/// same shape of bug is waiting anywhere else a count meets a noun.
///
/// The rule the language actually uses:
///   ends in 1, except 11        → singular      (1, 21, 31, 101)
///   ends in 2–9, except 12–19   → plural        (2, 9, 22, 39)
///   everything else             → genitive      (0, 10–19, 20, 30, 111)
void main() {
  String f(int n) => ltPlural(n, 'tuščia', 'tuščios', 'tuščių');

  group('singular — ends in 1 but is not 11', () {
    for (final n in [1, 21, 31, 41, 101, 121, 1001]) {
      test('$n', () => expect(f(n), 'tuščia'));
    }
  });

  group('plural — ends in 2–9, outside the teens', () {
    for (final n in [2, 3, 9, 22, 29, 33, 104, 1002]) {
      test('$n', () => expect(f(n), 'tuščios'));
    }
  });

  group('genitive — zero, the teens, and every round ten', () {
    // The teens are the trap: 11 ends in 1 and 12–19 end in 2–9, so a naive
    // "last digit" rule gets all nine of them wrong.
    for (final n in [0, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 30, 100, 111, 1011]) {
      test('$n', () => expect(f(n), 'tuščių'));
    }
  });

  test('the exact case seen in the app', () {
    // "3 sąsk. · 1 tuščios" was the bug; it must read "1 tuščia".
    expect(f(1), 'tuščia');
    expect(f(3), 'tuščios');
  });

  test('works for any noun, not just this one', () {
    expect(ltPlural(1, 'diena', 'dienos', 'dienų'), 'diena');
    expect(ltPlural(11, 'diena', 'dienos', 'dienų'), 'dienų');
    expect(ltPlural(22, 'diena', 'dienos', 'dienų'), 'dienos');
  });
}
