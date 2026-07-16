import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'content_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/subscription.dart';
import 'services/dashboard_store.dart';
import 'services/feature_flags.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'services/recap_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/verify_email_screen.dart';

/// Vaultie brand palette. The hero colour is the deep "vault green".
class VaultieColors {
  static const Color primary = Color(0xFF174E35);
  static const Color primaryDark = Color(0xFF0E3322);
  static const Color primaryLight = Color(0xFF2E6B4D);
  static const Color accent = Color(0xFF8BD3A7);
  static const Color surface = Color(0xFFF4F8F5); // page background (light)
  static const Color card = Color(0xFFFFFFFF); // cards / sheets / dialogs
  static const Color ink = Color(0xFF11231A); // primary text
  static const Color subtle = Color(0xFF6B7E74); // secondary text
  static const Color line = Color(0xFFE1E8E3); // borders / dividers
  static const Color brightGreen = Color(0xFF4CAF72); // green accent (fixed)
  static const Color danger = Color(0xFFD9534F);
}

/// Box names used across the app.
class HiveBoxes {
  static const String subscriptions = 'subscriptions';
  static const String settings = 'settings';

  /// Records of cancelled subscriptions ({monthly, date, name}), used by the
  /// dashboard savings tracker to total up what cancelling has saved.
  static const String cancellations = 'cancellations';

  /// Per-month spend snapshots for the Monthly Recap.
  static const String monthlyStats = 'monthlyStats';

  /// The last bank-scan dashboard payload, so the app opens straight into the
  /// dashboard instead of forcing a re-connect (see DashboardStore).
  static const String dashboard = 'dashboard';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  // Initialise Hive and register the (hand-written) Subscription adapter.
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(SubscriptionAdapter().typeId)) {
    Hive.registerAdapter(SubscriptionAdapter());
  }
  final subsBox = await Hive.openBox<Subscription>(HiveBoxes.subscriptions);
  final settings = await Hive.openBox(HiveBoxes.settings);
  await Hive.openBox(HiveBoxes.cancellations);
  await Hive.openBox(HiveBoxes.monthlyStats);
  await Hive.openBox(HiveBoxes.dashboard);
  // Load persisted language/currency preferences into their notifiers.
  AppPrefs.load();

  // Existing users (who already have tracked payments) skip the first-run
  // "How would you like to start?" choice screen — it's for fresh installs.
  if (!AppPrefs.onboardingComplete && subsBox.isNotEmpty) {
    await AppPrefs.setOnboardingComplete(true);
  }

  // TEST HARNESS (debug only). Remove before release.
  // Review mode: force the onboarding flow (Landing → … → Two paths → Account →
  // Paywall) to show on launch so we can walk it. Flip `onboarded` back to true
  // to land straight on the dashboard again.
  if (!kReleaseMode) {
    // Debug + profile only (never release). Mock billing so the forced premium
    // flag sticks (RevenueCat would overwrite it), land on the dashboard, and
    // enable the bank flow for testing. Remove this whole block before release.
    PurchaseService.instance = MockPurchaseService();
    await settings.put('premium', true);
    await settings.put('onboarded', true);
  }

  await NotificationService.instance.init();
  // Configures RevenueCat and resolves the "Vaultie Pro" entitlement so premium
  // gating is correct from the first frame.
  await PurchaseService.instance.init();

  // Fetch remote feature flags (e.g. the banking kill-switch) in the background
  // — not awaited so a slow network can't delay the first frame; the UI updates
  // reactively when the flags arrive.
  FeatureFlags.instance.init();

  // (Re)schedule payment reminders from the LIVE recurring bills (dashboard
  // `subs`), not the old stale imported-subscription records. Runs on each launch
  // so reminders survive past renewals, reinstalls, and OS-cleared notifications,
  // and always reflect the latest scan (next due from the real last charge).
  // Same language rule as the UI: manual choice, else device Region.
  final isLithuanian = effectiveLocale().languageCode == 'lt';
  await _rescheduleFromDashboard(isLithuanian: isLithuanian);

  // Snapshot this month's spend so the Monthly Recap has data to show later.
  RecapService.recordCurrentMonth(subsBox.values.toList());

  runApp(
      VaultieApp(hasOnboarded: settings.get('onboarded', defaultValue: false)));
}

/// Launch-time pass: (re)schedules payment reminders from the persisted dashboard
/// recurring bills. Cancels every prior reminder (including the old stale
/// imported-subscription ones) and re-schedules only the live, active,
/// user-kept bills with a real next-due date. Never blocks startup.
Future<void> _rescheduleFromDashboard({required bool isLithuanian}) async {
  try {
    final dash = DashboardStore.load();
    final subs = (dash?['subs'] as Map?)?.cast<String, dynamic>();
    final items = ((subs?['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    await NotificationService.instance.scheduleFromRecurring(
      items,
      excluded: DashboardStore.recurringExcluded(),
      included: DashboardStore.recurringIncluded(),
      isLithuanian: isLithuanian,
    );
  } catch (_) {
    // Never let reminder scheduling abort startup.
  }
}

class VaultieApp extends StatelessWidget {
  const VaultieApp({super.key, required this.hasOnboarded});

  final bool hasOnboarded;

  @override
  Widget build(BuildContext context) {
    // Rebuild the app when the user changes language, currency or the light/dark
    // content theme in Settings.
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppPrefs.locale,
        AppPrefs.currency,
        AppPrefs.budget,
        AppPrefs.darkMode
      ]),
      builder: (context, _) {
        // Refresh the content palette (dashboard/analytics/settings/add) for the
        // current choice before building; auth/splash keep their own colours.
        final isDark = AppPrefs.darkMode.value;
        applyContentTheme(isDark);
        // Dark is the primary theme, so the app's BASE ThemeData must follow the
        // dark preference — otherwise dialogs, bottom sheets and text fields
        // (which read the app theme, not the dashboard's private tokens) stay
        // light: a white field with light text that vanishes. Build with the
        // right brightness + surfaces AFTER applyContentTheme sets the palette.
        final base = ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: VaultieColors.primary,
            primary: VaultieColors.primary,
            secondary: VaultieColors.primaryLight,
            surface: isDark ? cCard : VaultieColors.card,
            brightness: isDark ? Brightness.dark : Brightness.light,
          ),
          scaffoldBackgroundColor: isDark ? cBg : VaultieColors.surface,
        );
        return MaterialApp(
          title: 'Vaultie',
          debugShowCheckedModeBanner: false,
          // Localization: ships English (default) and Lithuanian. The language is
          // the manual Settings choice if set, otherwise the device Region (LT →
          // Lithuanian, anywhere else → English).
          locale: effectiveLocale(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: base.copyWith(
            textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
              bodyColor: cInk,
              displayColor: cInk,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: cBg,
              foregroundColor: cInk,
              elevation: 0,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              color: cCard,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              margin: EdgeInsets.zero,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: VaultieColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: cCard,
              hintStyle: TextStyle(color: cSubtle),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                    color: VaultieColors.brightGreen, width: 2),
              ),
            ),
            // Date picker: dark surface, filled green OK, outlined Cancel.
            datePickerTheme: DatePickerThemeData(
              backgroundColor: cCard,
              confirmButtonStyle: TextButton.styleFrom(
                backgroundColor: VaultieColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              cancelButtonStyle: TextButton.styleFrom(
                foregroundColor: cSubtle,
                side: BorderSide(color: cLine),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            dialogTheme: DialogThemeData(backgroundColor: cCard),
            bottomSheetTheme: BottomSheetThemeData(backgroundColor: cCard),
          ),
          // Always launch into the branded splash; it decides where to go next.
          home: SplashScreen(hasOnboarded: hasOnboarded),
          routes: {
            OnboardingScreen.route: (_) => const OnboardingScreen(),
            AuthScreen.route: (_) => const AuthScreen(),
            VerifyEmailScreen.route: (_) => const VerifyEmailScreen(),
            DashboardScreen.route: (_) => const DashboardScreen(),
            PaywallScreen.route: (_) => const PaywallScreen(),
            SettingsScreen.route: (_) => const SettingsScreen(),
          },
        );
      },
    );
  }
}
