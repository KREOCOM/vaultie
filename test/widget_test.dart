// Localization smoke tests for Vaultie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vaultie/l10n/app_localizations.dart';
import 'package:vaultie/screens/onboarding_screen.dart';

void main() {
  testWidgets('shows the image onboarding with a localized CTA',
      (WidgetTester tester) async {
    // Pump OnboardingScreen directly: the real app boots through SplashScreen,
    // which does Firebase/Hive work that isn't wired up under `flutter test`.
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OnboardingScreen(),
    ));
    await tester.pump();

    // 3-screen image PageView; screen 1 shows the English "Continue →" CTA by
    // default (the test locale resolves to en).
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Continue →'), findsOneWidget);

    // The bundled artwork isn't available to `flutter test`, so drain any
    // "unable to load asset" errors it raises.
    while (tester.takeException() != null) {}
  });

  testWidgets('resolves Lithuanian strings for a Lithuanian locale',
      (WidgetTester tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('lt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l = AppLocalizations.of(context);
        return const SizedBox();
      }),
    ));

    expect(l.onboard1Title, 'Kur dingsta jūsų pinigai?');
    expect(l.continueLabel, 'Tęsti');
    expect(l.saveToVault, 'Išsaugoti');

    // Lithuanian plural forms (one / few / other).
    expect(l.activeSubscriptions(1), '1 aktyvi prenumerata');
    expect(l.activeSubscriptions(3), '3 aktyvios prenumeratos');
    expect(l.activeSubscriptions(10), '10 aktyvių prenumeratų');
  });

  testWidgets('falls back to English for an unsupported locale',
      (WidgetTester tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l = AppLocalizations.of(context);
        return const SizedBox();
      }),
    ));

    expect(l.continueLabel, 'Continue');
  });
}
