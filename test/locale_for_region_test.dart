import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultie/app_prefs.dart';

/// Osvaldas' real complaint: many Lithuanians pick "English (United Kingdom)"
/// or "English (United States)" as their iPhone's Language, and iOS bundles
/// that choice together with Region unless the person separately corrects it
/// — most never do. So checking only the device's TOP preferred locale
/// (`.locale`) frequently misreads a Lithuanian's own phone as British or
/// American, and the app opened in English for someone who never chose that.
///
/// localeForRegion() now scans the WHOLE preferred-locale list (`.locales`),
/// because Lithuanian very often survives in it as a secondary entry (kept
/// for the keyboard/autocorrect) even when a non-LT language sits first, and
/// a Lithuanian Region can independently survive there too. This pins that
/// widening without a network call, an IP lookup, or any new data leaving
/// the device — purely from what the OS already reports.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Locale run(List<Locale> deviceLocales) {
    final binding = TestWidgetsFlutterBinding.instance;
    final original = binding.platformDispatcher.locales;
    binding.platformDispatcher.localesTestValue = deviceLocales;
    addTearDown(() => binding.platformDispatcher.localesTestValue = original);
    return localeForRegion();
  }

  test('a phone with only Lithuanian gets Lithuanian', () {
    expect(run([const Locale('lt', 'LT')]).languageCode, 'lt');
  });

  test('a phone with only English (US), no LT anywhere, gets English', () {
    expect(run([const Locale('en', 'US')]).languageCode, 'en');
  });

  test(
      'English (UK) as PRIMARY but Lithuanian still in the list — the exact '
      'regression — still gets Lithuanian', () {
    // This is the real-world shape: the phone's top locale is en_GB (Language
    // = English (UK), which iOS bundled Region = UK together with), but
    // Lithuanian is still present further down the preference list.
    expect(
      run([const Locale('en', 'GB'), const Locale('lt', 'LT')]).languageCode,
      'lt',
    );
  });

  test('Region alone still says Lithuania even with an English language '
      'first — also still gets Lithuanian', () {
    // Language = English, but Region never got changed off Lithuania.
    expect(run([const Locale('en', 'LT')]).languageCode, 'lt');
  });

  test('a genuinely foreign phone (no LT language, no LT region anywhere) '
      'still gets English, unchanged from before', () {
    expect(
      run([const Locale('en', 'GB'), const Locale('fr', 'FR')]).languageCode,
      'en',
    );
  });

  test('an empty locale list never throws — falls back to English', () {
    expect(run(const []).languageCode, 'en');
  });
}
