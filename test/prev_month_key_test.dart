import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/screens/preview/dashboard_preview.dart';

/// The real bug: tapping "Santaupų norma" while browsing April in Overview
/// always opened June's figures. Both the Overview badge and the detail
/// screen computed "last month" as `monthKeys[monthKeys.length - 2]` — a
/// fixed "second-to-last in the whole dataset" — instead of the month right
/// before whichever one was actually on screen. That was only ever correct
/// when the browsed month happened to be the newest one.
void main() {
  const months = ['2026-02', '2026-03', '2026-04', '2026-05', '2026-06'];

  test('the month right before the newest one (the case that always worked)', () {
    expect(prevMonthKey(months, '2026-06'), '2026-05');
  });

  test('the month right before an EARLIER browsed month — the bug', () {
    // Browsing April must yield March, never May (the dataset's fixed
    // second-to-last, which is what the old code always returned here).
    expect(prevMonthKey(months, '2026-04'), '2026-03');
    expect(prevMonthKey(months, '2026-05'), '2026-04');
  });

  test('the first month in the list has no month before it', () {
    expect(prevMonthKey(months, '2026-02'), isNull);
  });

  test('a key not present in the list has no month before it', () {
    // indexOf returns -1 for a miss; must not wrap around to the last month.
    expect(prevMonthKey(months, '2099-01'), isNull);
  });

  test('a single-month dataset has no previous month', () {
    expect(prevMonthKey(const ['2026-06'], '2026-06'), isNull);
  });

  test('an empty month list never throws', () {
    expect(prevMonthKey(const [], '2026-06'), isNull);
  });
}
