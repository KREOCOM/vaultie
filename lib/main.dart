import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app_prefs.dart';
import 'content_theme.dart';
import 'services/app_lock.dart';
import 'services/auth_service.dart';
import 'screens/lock_screen.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/subscription.dart';
import 'services/dashboard_store.dart';
import 'services/banking_deep_links.dart';
import 'services/feature_flags.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'services/recap_service.dart';
import 'screens/auth_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/verify_email_screen.dart';

/// Vaultie brand palette. The hero colour is the brand blue.
///
/// These are the app-wide defaults behind [ThemeData] — dialogs, text fields,
/// buttons and pickers inherit them, so anything a screen doesn't colour itself
/// is coloured here. They were the old green identity long after the logo,
/// splash and onboarding had gone blue, which is how green kept surfacing in
/// dialogs and input fields on otherwise-blue screens. Values match the blue
/// screens: ink/subtle/line from onb_paywall, brand blue from login_screen.
class VaultieColors {
  static const Color primary = Color(0xFF003DE1);
  static const Color primaryDark = Color(0xFF002B9E);
  static const Color primaryLight = Color(0xFF2F6BFF);
  static const Color accent = Color(0xFF9CBBFF);
  static const Color surface = Color(0xFFFCFCFD); // page background (light)
  static const Color card = Color(0xFFFFFFFF); // cards / sheets / dialogs
  static const Color ink = Color(0xFF0B1533); // primary text
  static const Color subtle = Color(0xFF4C5B7D); // secondary text
  static const Color line = Color(0xFFE6EAF2); // borders / dividers
  static const Color brightBlue = Color(0xFF0A4DFD); // accent (fixed)
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

/// Set on first launch after an install. Its absence is what identifies a fresh
/// install, since Hive is wiped on delete but the Keychain is not.
const String _kInstalled = 'installed';

/// App-wide navigator, so the banking deep-link handler can present the resume
/// screen without a BuildContext of its own.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Crash reporting, wired before anything else can throw.
  //
  // Until this existed the app had no way to tell anyone that it had broken:
  // an uncaught exception printed to a console nobody is attached to, and the
  // only signal that something was wrong on a user's phone was whether they
  // bothered to write in. Both handlers matter — FlutterError catches errors
  // inside the widget tree, PlatformDispatcher catches everything outside it
  // (async gaps, platform channels), which is where the interesting ones live.
  // Debug builds report nothing: local crashes are already visible, and they
  // would drown the real reports.
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(kReleaseMode);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

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

  // A fresh install must start genuinely fresh. Deleting an iOS app clears its
  // Hive data but NOT the Keychain, and Firebase keeps its session there — so
  // without this, a reinstalled app silently opens already signed in as the
  // previous user, skipping onboarding and handing them an account that may not
  // be theirs. An empty settings box means "never launched on this install", so
  // that is where the leftover session gets cleared.
  if (!settings.containsKey(_kInstalled)) {
    try {
      await AuthService().signOut();
    } catch (_) {
      // No session, or plugins unavailable — nothing to clear either way.
    }
    await settings.put(_kInstalled, true);
  }

  // ⚠️ TEMP TEST BYPASS — lets a tester (wife's Swedbank run) get past the paywall
  // WITHOUT an App Store purchase she can't complete. Forces the Vaultie Pro
  // entitlement so the paywall auto-advances, but does NOT touch `onboarded`, so
  // she still walks onboarding and connects her bank. Pairs with the server-side
  // _require_premium bypass. REVERT BOTH before any real release.
  // ignore: dead_code
  const kBypassPaywall = true;
  if (kBypassPaywall) {
    PurchaseService.instance = MockPurchaseService();
    await settings.put('premium', true);
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
    await AppPrefs.setOnboarded(true);
  }

  await NotificationService.instance.init();
  // Configures RevenueCat and resolves the "Vaultie Pro" entitlement so premium
  // gating is correct from the first frame.
  await PurchaseService.instance.init();

  // Catch a bank's callback when it returns as an app link (a bank that hands
  // off to its own app). No-op for every other launch. Not awaited.
  BankingDeepLinks.instance.init(navigatorKey);

  // Last known flag values first, so an offline launch doesn't look like a
  // kill-switch. The live fetch below overwrites them a moment later.
  FeatureFlags.instance.loadCached();
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

  runApp(VaultieApp(hasOnboarded: AppPrefs.onboarded));
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
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          // Gate every route behind the PIN/Face ID lock when the user set one.
          builder: (context, child) => _LockGate(child: child ?? const SizedBox.shrink()),
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
                    color: VaultieColors.brightBlue, width: 2),
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
          home: SplashScreen(hasOnboarded: hasOnboarded),
          routes: {
            AuthScreen.route: (_) => const AuthScreen(),
            VerifyEmailScreen.route: (_) => const VerifyEmailScreen(),
          },
        );
      },
    );
  }
}

/// Wraps the whole app: shows the [LockScreen] over everything while a PIN is
/// set and the app is "locked" — on cold start, and again after it returns from
/// the background. Unlocking just hides the overlay; the app underneath was
/// there all along.
class _LockGate extends StatefulWidget {
  const _LockGate({required this.child});
  final Widget child;
  @override
  State<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<_LockGate> with WidgetsBindingObserver {
  /// A PIN protects a signed-in vault, so it only makes sense while someone is
  /// signed in. It used to cover the sign-in screens too, and the PIN keys are
  /// cleared only *after* a successful sign-in — so one user signing out with a
  /// PIN set left the next person facing a lock screen they could not answer,
  /// in front of the login they needed to reach to clear it. Reinstalling was
  /// the only way out.
  static bool get _shouldLock => AppLock.isPinSet && AuthService().isLoggedIn;

  bool _locked = _shouldLock;
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed) {
      // The biometric sheet backgrounds the app while it is up. Re-locking on
      // that resume would undo the unlock that just happened and prompt again.
      if (AppLock.biometricInFlight) {
        _wasBackgrounded = false;
        return;
      }
      if (_wasBackgrounded && _shouldLock && !_locked) {
        setState(() => _locked = true);
      }
      _wasBackgrounded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          LockScreen(onUnlocked: () => setState(() => _locked = false)),
      ],
    );
  }
}
