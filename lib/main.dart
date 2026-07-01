import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/subscription.dart';
import 'services/notification_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/splash_screen.dart';

/// Vaultie brand palette. The hero colour is the deep "vault green".
class VaultieColors {
  static const Color primary = Color(0xFF174E35);
  static const Color primaryDark = Color(0xFF0E3322);
  static const Color primaryLight = Color(0xFF2E6B4D);
  static const Color accent = Color(0xFF8BD3A7);
  static const Color surface = Color(0xFFF4F8F5);
  static const Color card = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF11231A);
  static const Color subtle = Color(0xFF6B7E74);
  static const Color danger = Color(0xFFD9534F);
}

/// Box names used across the app.
class HiveBoxes {
  static const String subscriptions = 'subscriptions';
  static const String settings = 'settings';
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
  await Hive.openBox<Subscription>(HiveBoxes.subscriptions);
  final settings = await Hive.openBox(HiveBoxes.settings);

  await NotificationService.instance.init();

  runApp(VaultieApp(hasOnboarded: settings.get('onboarded', defaultValue: false)));
}

/// Debug-only preview hook (no effect unless the dart-define is passed).
const bool _kShowOnboarding = bool.fromEnvironment('SHOW_ONBOARDING');

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

    return MaterialApp(
      title: 'Vaultie',
      debugShowCheckedModeBanner: false,
      // Localization: ships English (default) and Lithuanian. Flutter resolves
      // the device locale against [supportedLocales]; anything that isn't
      // Lithuanian falls back to the first supported locale (English).
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8E3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1E8E3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: VaultieColors.primary, width: 2),
          ),
        ),
      ),
      // Always launch into the branded splash; it decides where to go next.
      // `--dart-define=SHOW_ONBOARDING=true` forces the intro flow even after
      // it's been completed — handy for previewing onboarding on a device.
      home: SplashScreen(hasOnboarded: !_kShowOnboarding && hasOnboarded),
      routes: {
        OnboardingScreen.route: (_) => const OnboardingScreen(),
        AuthScreen.route: (_) => const AuthScreen(),
        DashboardScreen.route: (_) => const DashboardScreen(),
      },
    );
  }
}
