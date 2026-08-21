import 'dart:async';
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
import 'screens/preview/dashboard_preview.dart' show designPreviewPalette;
import 'services/app_lock.dart';
import 'services/auth_service.dart';
import 'screens/lock_screen.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'models/subscription.dart';
import 'services/dashboard_store.dart';
import 'services/banking_deep_links.dart';
import 'services/feature_flags.dart';
import 'services/local_crypto.dart';
import 'services/fx_rates.dart';
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

/// Opens a Hive box, recreating it if it is corrupt. A box left half-written by a
/// crash or low-storage event, or one whose adapter shape changed across an app
/// update, would otherwise throw here — before [runApp] — and brick the app in a
/// launch crash-loop whose only exit is delete-and-reinstall (wiping ALL local
/// data). Dropping one bad box loses only that box's cache, which the app re-fetches
/// from the bank; the app still boots.
Future<Box<T>> _openBoxSafe<T>(String name) async {
  final cipher = LocalCrypto.cipher;
  try {
    return await Hive.openBox<T>(name, encryptionCipher: cipher);
  } catch (e, s) {
    // Try ONCE more before destroying anything. A box that is genuinely corrupt
    // fails again immediately; a file still locked by a process that has just
    // died, or an open that lost a race with low storage, opens fine on the
    // second attempt. Deleting on the first failure treats those as corruption —
    // and for the subscriptions box that means the user's own edits, which no
    // amount of re-syncing brings back.
    try {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final retry = await Hive.openBox<T>(name, encryptionCipher: cipher);
      try {
        await FirebaseCrashlytics.instance.recordError(e, s,
            reason: 'Hive box "$name" failed once, opened on retry');
      } catch (_) {}
      return retry;
    } catch (_) {/* really is broken — fall through and rebuild it */}
    try {
      await FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'Hive box "$name" corrupt — recreating');
    } catch (_) {}
    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (_) {}
    try {
      return await Hive.openBox<T>(name, encryptionCipher: cipher);
    } catch (_) {
      // The retry failed too — disk full, or the store is unwritable. Returning
      // an in-memory box keeps the app BOOTING: this session cannot persist, but
      // an unguarded throw here happens before runApp, so it was a launch crash
      // on every start with no route back except deleting the app.
      //
      // `bytes:` is what makes it memory-only — it never touches the disk that
      // just refused us, so this last step cannot fail the same way.
      return Hive.openBox<T>('${name}_fallback', bytes: Uint8List(0));
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything from here to runApp runs BEFORE the first frame, so anything that
  // throws is a launch crash — and a launch crash repeats on every start, with
  // no screen, no message and no way out but deleting the app and losing the
  // local vault with it. So each step below is allowed to fail on its own and
  // leave the app degraded rather than dead.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Sign-in and crash reporting will be unavailable this session; the local
    // vault and the UI still work, and the next launch retries.
  }

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
  try {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(kReleaseMode);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    // No crash reporting this session. Losing the reports is a bad trade for
    // losing the launch.
  }

  try {
    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  } catch (_) {/* the app is portrait by design anyway */}

  // Initialise Hive and register the (hand-written) Subscription adapter.
  try {
    await Hive.initFlutter();
  } catch (_) {
    // path_provider can fail to give a documents directory. The box opens below
    // then fall back to memory rather than bringing the launch down.
  }
  try {
    if (!Hive.isAdapterRegistered(SubscriptionAdapter().typeId)) {
      Hive.registerAdapter(SubscriptionAdapter());
    }
  } catch (_) {/* already registered by a hot restart */}
  // The local boxes hold a year of real bank transactions, so they are encrypted
  // with a Keychain-held key. This must run BEFORE any box is opened, and the
  // one-time migration must run before that — an existing plaintext box cannot
  // be opened with a cipher, it has to be read and rewritten.
  await LocalCrypto.init();
  if (LocalCrypto.cipher != null && !await LocalCrypto.migrated) {
    var ok = await LocalCrypto.migrateBox<Subscription>(HiveBoxes.subscriptions);
    for (final b in const [
      HiveBoxes.settings,
      HiveBoxes.cancellations,
      HiveBoxes.monthlyStats,
      HiveBoxes.dashboard,
    ]) {
      ok = await LocalCrypto.migrateBox<dynamic>(b) && ok;
    }
    // Only claim it if EVERY box came across; a partial pass retries next launch
    // rather than leaving one box readable and calling the job done.
    if (ok) await LocalCrypto.markMigrated();
  }
  final subsBox = await _openBoxSafe<Subscription>(HiveBoxes.subscriptions);
  final settings = await _openBoxSafe<dynamic>(HiveBoxes.settings);
  await _openBoxSafe<dynamic>(HiveBoxes.cancellations);
  await _openBoxSafe<dynamic>(HiveBoxes.monthlyStats);
  await _openBoxSafe<dynamic>(HiveBoxes.dashboard);
  // Live FX rates (EUR-based, ECB daily, cached) — loaded before AppPrefs.load()
  // so applyDisplayCurrency() can point Money at the chosen currency's rate.
  try {
    await FxRates.instance.init();
  } catch (_) {
    // Rates fall back to the cached table (or 1:1 EUR); a bad stored value must
    // not stop the app from opening.
  }
  // Load persisted language/currency preferences into their notifiers. Guarded so
  // a single corrupt/wrong-typed setting can never crash the launch.
  try {
    AppPrefs.load();
  } catch (e, s) {
    try {
      await FirebaseCrashlytics.instance
          .recordError(e, s, reason: 'AppPrefs.load failed at boot');
    } catch (_) {}
  }
  // When a fresh rate table lands, reapply it to the current display currency.
  FxRates.instance.rates.addListener(AppPrefs.applyDisplayCurrency);

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
    try {
      await settings.put(_kInstalled, true);
    } catch (_) {
      // If the write fails the next launch simply signs out again — wasteful,
      // but survivable. Throwing here would kill the very first launch after
      // install, which is the one launch nobody would ever get past.
    }
  }

  // ⚠️ TEMP TEST BYPASS — lets a tester (wife's Swedbank run) get past the paywall
  // WITHOUT an App Store purchase she can't complete. Forces the Vaultie Pro
  // entitlement so the paywall auto-advances, but does NOT touch `onboarded`, so
  // she still walks onboarding and connects her bank. Pairs with the server-side
  // _require_premium bypass. REVERT BOTH before any real release.
  const kBypassPaywall = false;
  // ignore: dead_code
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

  // Both make network calls; a hung server must not freeze the branded splash
  // with no spinner on a slow/flaky connection. Bound the wait — the futures keep
  // running in the background, and PurchaseService.init seeds premium from the
  // cached flag synchronously before its network round-trips, so gating is still
  // correct from the first frame.
  // Concurrently, not one after the other. They are independent, and run in
  // sequence their two timeouts add up: on a slow or flaky connection that is
  // ten seconds of an iOS launch budget that is only about twenty — and iOS
  // kills an app that hasn't drawn its first frame by then. (Under `flutter
  // run` this never showed, because an attached debugger disables that
  // watchdog; the app only died when launched from the home screen.)
  await Future.wait([
    NotificationService.instance
        .init()
        .timeout(const Duration(seconds: 4))
        .catchError((Object _) {}),
    // Configures RevenueCat and resolves the "Vaultie Pro" entitlement.
    PurchaseService.instance
        .init()
        .timeout(const Duration(seconds: 4))
        .catchError((Object _) {}),
  ]);

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

  // TEMPORARY (2026-08-14): the in-progress Home redesign, on Osvaldas's own
  // real device with his real bank data, at his explicit request — normally
  // only main_design_preview.dart's sandbox sets this. Flip back to false
  // (or delete these two lines) once the redesign is done, and before any
  // App Store build.
  designPreviewPalette = true;

  runApp(VaultieApp(hasOnboarded: AppPrefs.onboarded));

  // Deliberately AFTER runApp, and not awaited. Neither of these has anything
  // to say to the first screen: one re-schedules payment reminders (a platform
  // call per bill, unbounded), the other writes a spend snapshot for the Monthly
  // Recap. Held in front of runApp they spent the launch budget on work nobody
  // is waiting to see, which is how the app ended up being killed at launch.
  unawaited(_rescheduleFromDashboard(isLithuanian: isLithuanian));
  RecapService.recordCurrentMonth(subsBox.values.toList());
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
          // Also clamp the system text scale: the dashboard uses many fixed-height
          // rows, and an unbounded accessibility font (2x+) overflowed them with
          // "BOTTOM OVERFLOWED" stripes and clipped controls. 1.3x keeps larger
          // text legible without breaking the layout.
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
              child: _LockGate(child: child ?? const SizedBox.shrink()),
            );
          },
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
      // Cover real content the instant the app leaves the foreground, not on
      // return. Locking only on resume left the entire backgrounded interval —
      // and the OS app-switcher snapshot taken during it — showing whatever
      // screen (real transactions, balances) was on screen when it was
      // backgrounded.
      if (_shouldLock && !_locked) {
        setState(() => _locked = true);
      }
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
