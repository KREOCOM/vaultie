import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'content_theme.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/subscription.dart';
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
  // Load persisted language/currency preferences into their notifiers.
  AppPrefs.load();

  await NotificationService.instance.init();
  // Configures RevenueCat and resolves the "Vaultie Pro" entitlement so premium
  // gating is correct from the first frame.
  await PurchaseService.instance.init();

  // Roll any lapsed renewal dates forward to their next cycle and (re)schedule
  // every subscription's reminders. Runs on each launch so reminders survive
  // past renewals, app reinstalls, and OS-cleared notifications.
  // Same language rule as the UI: manual choice, else device Region.
  final isLithuanian = effectiveLocale().languageCode == 'lt';
  await _rescheduleReminders(subsBox, isLithuanian: isLithuanian);

  // Snapshot this month's spend so the Monthly Recap has data to show later.
  RecapService.recordCurrentMonth(subsBox.values.toList());

  runApp(
      VaultieApp(hasOnboarded: settings.get('onboarded', defaultValue: false)));
}

/// Launch-time pass: advances elapsed billing dates and (re)schedules reminders
/// for every subscription. Failures are swallowed per-subscription so a single
/// bad record can never block app startup.
Future<void> _rescheduleReminders(
  Box<Subscription> box, {
  required bool isLithuanian,
}) async {
  final now = DateTime.now();
  for (final sub in box.values.toList()) {
    try {
      final rolled = sub.rolledForwardBillingDate(now);
      final effective = rolled.isAtSameMomentAs(sub.nextBillingDate)
          ? sub
          : sub.copyWith(nextBillingDate: rolled);
      if (!identical(effective, sub)) {
        await box.put(sub.id, effective);
      }
      await NotificationService.instance
          .scheduleForSubscription(effective, isLithuanian: isLithuanian);
    } catch (_) {
      // Never let one subscription's scheduling failure abort startup.
    }
  }
}

class VaultieApp extends StatelessWidget {
  const VaultieApp({super.key, required this.hasOnboarded});

  final bool hasOnboarded;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: VaultieColors.primary,
        primary: VaultieColors.primary,
        secondary: VaultieColors.primaryLight,
        surface: VaultieColors.card,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: VaultieColors.surface,
    );

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
        applyContentTheme(AppPrefs.darkMode.value);
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
              bodyColor: VaultieColors.ink,
              displayColor: VaultieColors.ink,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: VaultieColors.surface,
              foregroundColor: VaultieColors.ink,
              elevation: 0,
              centerTitle: false,
            ),
            cardTheme: CardThemeData(
              color: VaultieColors.card,
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
              fillColor: VaultieColors.card,
              hintStyle: const TextStyle(color: VaultieColors.subtle),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: VaultieColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: VaultieColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                    color: VaultieColors.brightGreen, width: 2),
              ),
            ),
            // Date picker: dark surface, filled green OK, outlined Cancel.
            datePickerTheme: DatePickerThemeData(
              backgroundColor: VaultieColors.card,
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
                foregroundColor: VaultieColors.subtle,
                side: const BorderSide(color: VaultieColors.line),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            dialogTheme:
                const DialogThemeData(backgroundColor: VaultieColors.card),
            bottomSheetTheme:
                const BottomSheetThemeData(backgroundColor: VaultieColors.card),
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
