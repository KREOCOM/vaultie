// STANDALONE — 2026-08-17. Boots straight into the real onboarding chain
// (the exact same widgets SplashScreen shows a new user, in the exact same
// order) with no Firebase auth check, no Hive "onboarded" flag, no splash
// hold — for reviewing/reworking onboarding's design without walking
// through a real login or waiting through the 2.4s splash every reload.
// Bootstrap below is a trimmed copy of main.dart's — only what the
// onboarding chain actually touches.
//
// Run with:
//   flutter run -t lib/main_onboarding_preview.dart
//
// To remove: delete this file. Nothing elsewhere is gated on it.
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'main.dart' show HiveBoxes, navigatorKey;
import 'models/subscription.dart';
import 'services/banking_deep_links.dart';
import 'services/feature_flags.dart';
import 'services/fx_rates.dart';
import 'services/local_crypto.dart';
import 'services/purchase_service.dart';
import 'screens/login_screen.dart';
import 'screens/onb_ai_chat.dart';
import 'screens/onb_banks.dart';
import 'screens/onb_connect.dart';
import 'screens/onb_features.dart';
import 'screens/onb_intro.dart';
import 'screens/onb_invest.dart';
import 'screens/onb_month.dart';
import 'screens/onb_overview.dart';
import 'screens/preview/dashboard_preview.dart';

Future<Box<T>> _openBox<T>(String name) async {
  try {
    return await Hive.openBox<T>(name, encryptionCipher: LocalCrypto.cipher);
  } catch (_) {
    return Hive.openBox<T>('${name}_fallback', bytes: Uint8List(0));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  try {
    await Hive.initFlutter();
  } catch (_) {}
  try {
    if (!Hive.isAdapterRegistered(SubscriptionAdapter().typeId)) {
      Hive.registerAdapter(SubscriptionAdapter());
    }
  } catch (_) {}
  await LocalCrypto.init();
  await _openBox<Subscription>(HiveBoxes.subscriptions);
  await _openBox<dynamic>(HiveBoxes.settings);
  await _openBox<dynamic>(HiveBoxes.cancellations);
  await _openBox<dynamic>(HiveBoxes.monthlyStats);
  await _openBox<dynamic>(HiveBoxes.dashboard);
  try {
    await FxRates.instance.init();
  } catch (_) {}
  try {
    AppPrefs.load();
  } catch (_) {}
  // 2026-08-19: was forced to English here for a one-off translation-
  // coverage check (see the i18n.dart entries added that day). Back to
  // null — the normal auto-detected device locale — now that check is
  // done; flip it again the same way if another pass is ever needed.
  AppPrefs.setLocale(null);

  // Without this the onboarding demo falls back to DashboardPreview's
  // pre-redesign legacy branch (old "Pradžia" header, the retired
  // Skenuoti kvitą/Dalybos banners, etc.) instead of the current shipped
  // design every real user sees — main.dart sets the same flag for the
  // production app itself.
  designPreviewPalette = true;
  designPreviewFakeRecurring = true;

  // 2026-08-20: this trimmed bootstrap used to stop at the onboarding
  // chain's own last screen — going past it (real sign-in → real paywall →
  // real bank connect) hit three gaps main.dart's boot normally covers:
  //
  //   1. PurchaseService was never initialised, so `isPremium` stayed at
  //      its constructor default (false) regardless of the signed-in
  //      account's real entitlement — harmless for the paywall itself
  //      (it's just shown), but see BankConnectScreen's own gate below.
  //   2. FeatureFlags was never loaded, so `bankingEnabled` stayed at its
  //      hard-coded default (false) and BankConnectScreen refused to
  //      connect anything ("Bank connection is temporarily unavailable").
  //   3. BankingDeepLinks was never wired to a navigatorKey. Most banks'
  //      OAuth consent returns inside the same ASWebAuthenticationSession
  //      and never needed this — but a bank that hands off to its own app
  //      (SEB, Swedbank — see banking_deep_links.dart's own doc comment)
  //      relaunches Vaultie via the vaultie:// / universal-link callback
  //      instead, and with nothing listening for it here, that callback's
  //      single-use code was just dropped — the user lands back on
  //      whatever the OS put them on (their bank's app, or Safari) with no
  //      route back into Vaultie. That's the "ismeta mane iš appso" bug.
  //
  // Real (not mocked) PurchaseService, so a real signed-in account's real
  // entitlement resolves exactly as it does live.
  try {
    await PurchaseService.instance.init().timeout(const Duration(seconds: 4));
  } catch (_) {}
  FeatureFlags.instance.loadCached();
  FeatureFlags.instance.init();
  BankingDeepLinks.instance.init(navigatorKey);

  runApp(const _OnboardingPreviewApp());
}

class _OnboardingPreviewApp extends StatelessWidget {
  const _OnboardingPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      // Without these, Flutter's OWN Localizations.localeOf(context) — what
      // real screens past onboarding read via `_isLt`-style checks, e.g.
      // BankConnectScreen — falls back to the device's raw system language
      // instead of AppPrefs/tr()'s resolved one. That's how onboarding (all
      // tr()) read correctly in Lithuanian while "Connect your bank" (an
      // `_isLt` check) still showed English on the exact same run — main.dart
      // sets these on its own MaterialApp for the same reason.
      locale: effectiveLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Same chain SplashScreen._goNext() builds for a brand-new user, all
      // the way through to the paywall entry point (LoginScreen — the
      // paywall itself sits behind a real/demo sign-in, same as it does
      // live).
      home: const OnbIntro(
        next: OnbBanks(
          next: OnbMonth(
            next: OnbOverview(
              next: OnbAiChat(
                next: OnbInvest(
                  next: OnbFeatures(next: OnbConnect(next: LoginScreen())),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
