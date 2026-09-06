import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/app_prefs.dart';
import 'package:vaultie/i18n.dart';

/// Every `cat`/`sec` string dashboard.py's `_classify` can emit must have an
/// English translation, or an English-mode screen leaks Lithuanian.
///
/// Found live: "Valiutos keitimas" (currency exchange) showed up untranslated
/// in "Largest expenses" on an English-mode screen that was otherwise fully
/// English — `tr()` was already wrapping the string in dashboard_preview.dart,
/// but the map it looks up had no entry for it, so it silently fell back to
/// the Lithuanian original. "Savas pervedimas" (own-account transfer) had the
/// exact same gap and just hadn't been hit yet — same class of bug, not yet
/// hit by a real screenshot.
///
/// This list is the classification labels `_classify` can return as `cat`
/// (mirrors functions/dashboard.py — kept in sync by hand, not generated).
/// If a new one is added there, add it here AND to i18n.dart's `_en` map in
/// the same change, or it repeats this bug.
const _classifierCatLabels = [
  'Asmeninis pervedimas',
  'Atlyginimas',
  'Grynieji',
  'Grąžinimas',
  'Kita',
  'Pajamos',
  'Pervedimai',
  'Pervedimas',
  'Savas pervedimas',
  'Sąskaitos papildymas',
  'Valiutos keitimas',
];

void main() {
  setUp(() => AppPrefs.locale.value = const Locale('en'));
  tearDown(() => AppPrefs.locale.value = null);

  test('every backend classification label translates under English UI', () {
    final untranslated =
        _classifierCatLabels.where((lt) => tr(lt) == lt).toList();
    expect(untranslated, isEmpty,
        reason: 'these Lithuanian classifier labels have no entry in '
            "i18n.dart's _en map, so tr() silently passed them through "
            'unchanged: $untranslated');
  });

  test('the two labels from the live bug specifically translate', () {
    // The exact regression: both were previously missing from the _en map.
    expect(tr('Valiutos keitimas'), 'Currency exchange');
    expect(tr('Savas pervedimas'), 'Own-account transfer');
  });

  test('Lithuanian UI leaves every label as-is (tr is a no-op)', () {
    AppPrefs.locale.value = const Locale('lt');
    for (final lt in _classifierCatLabels) {
      expect(tr(lt), lt);
    }
  });
}
