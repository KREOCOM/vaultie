import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';
import '../services/auth_service.dart';
import '../user_session.dart';
import 'login_screen.dart';
import 'onb_ai_chat.dart';
import 'onb_banks.dart';
import 'onb_connect.dart';
import 'onb_features.dart';
import 'onb_intro.dart';
import 'onb_invest.dart';
import 'onb_month.dart';
import 'onb_overview.dart';
import 'landing.dart';
import 'verify_email_screen.dart';

/// Dev preview: force the onboarding chain to show from the splash even for a
/// user who already onboarded, so it can be reviewed on the device.
///
/// Tied to the build mode rather than left as a hand-flipped `true`. It was a
/// plain boolean checked at [_goNext] with no release guard, so shipping it in
/// the on position would have replayed the whole intro on EVERY launch for every
/// user and never let anyone reach their dashboard — and the only thing standing
/// between that and the App Store was remembering to flip it on the day.
///
/// `kDebugMode` keeps it on for `flutter run` (debug) preview, but OFF for
/// profile builds — which is how real bank connections actually get tested on
/// a device (debug builds crash on a home-screen tap; profile is the only
/// viable on-device test mode). `!kReleaseMode` used to gate this instead,
/// which also caught profile builds — silently forcing the full onboarding
/// chain, including a fresh bank connection, on every cold start of every
/// profile-mode test session, indistinguishable from a real persistence bug.
const bool kPreviewOnboarding = kDebugMode;

/// TEMP (dev): every onboarding page taps its own "Toliau" after this delay, so
/// the whole chain can be walked and screenshotted on a rack of simulators
/// without a finger. Set to null to disable. Remove with [kPreviewOnboarding].
Duration? kOnbAutoAdvance;

/// System bars fully transparent — no status/nav bar background colour of
/// their own — so the page's own dark background runs continuously behind
/// them and only the (white) time/battery/gesture-pill glyphs float on top.
/// Without `Contrast: false`, Android draws its own translucent scrim behind
/// those glyphs for legibility on an unknown background; against a page that
/// is ALREADY dark enough for white icons, that scrim is what showed up as a
/// visibly different-coloured strip at the very top and bottom instead of one
/// continuous background.
const kOnbStatusBarStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

/// Applies [kOnbStatusBarStyle] on Android ONLY. iOS's status bar was never
/// styled here before — it was already correct on the build already
/// submitted to App Review — so this must not touch it. Android-only because
/// the scrim [kOnbStatusBarStyle] fixes is an Android system-bar behaviour;
/// iOS has no equivalent to fix.
Widget wrapOnbStatusBar(Widget child) => Platform.isAndroid
    ? AnnotatedRegion<SystemUiOverlayStyle>(
        value: kOnbStatusBarStyle, child: child)
    : child;

/// Branded splash shown for ~2 seconds on launch, then fades into the app.
///
/// New users land on onboarding; returning users (who have already completed
/// it) go straight to the auth screen — the splash just gates both paths.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.hasOnboarded});

  static const route = '/splash';

  /// Whether onboarding has been completed before, controlling where we go next.
  final bool hasOnboarded;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _wordmark = 'Vaultie';

  // 2026-08-17 v2: v1 typed "Vaultie" out letter by letter — didn't land
  // ("nelabai patiko"). This instead lets the whole word MATERIALISE out of
  // a dim, unfocused state into full brightness/sharpness ("iš
  // prieblandos") — opacity and blur both ease from "barely there" to
  // clear together, rather than characters appearing one at a time.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..forward();

  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.22, curve: Curves.easeOut),
  );

  late final Animation<double> _wordmarkReveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.22, 0.7, curve: Curves.easeOut),
  );

  late final Animation<double> _taglineFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Hold the splash for 2.4s (the typing animation alone takes ~1.7s),
    // then fade-transition to the next screen.
    _timer = Timer(const Duration(milliseconds: 2400), _goNext);
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    // Something already took over the navigator — stand down.
    //
    // A bank that hands off to its own app (SEB, Swedbank) returns through a
    // universal link. If iOS killed Vaultie while the user was in the bank app,
    // that link COLD-LAUNCHES us: BankingDeepLinks picks the authorisation code
    // up and pushes BankCallbackScreen, typically within a fraction of a second
    // because the Firebase session restores fast for a returning user.
    //
    // This timer then fired at T+2s and called pushReplacement, which replaces
    // the navigator's TOPMOST route — by then the callback screen. The user was
    // dropped into onboarding and the connection vanished, having already spent
    // a single-use code, so retrying cost a whole new bank consent.
    //
    // It only bit when the app had actually been terminated in the background,
    // which is why it never reproduced in testing: a warm hand-off never runs
    // this method at all.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    // New users see onboarding; a signed-in & verified user goes straight to
    // the dashboard; a signed-in but unverified user resumes at the verify
    // screen; everyone else lands on the auth screen.
    final auth = AuthService();
    // Google and Apple accounts are verified by the provider. Apple's private
    // relay addresses in particular can report emailVerified=false forever, so
    // routing them to the email-verification screen locked them out of their own
    // app on the SECOND launch: that screen only polls reloadUser(), which never
    // flips, and its only exit is "use a different account". auth_screen.dart
    // already skips the gate for exactly this reason — this is the same rule,
    // applied where the app actually starts.
    final verified =
        auth.isEmailVerified || auth.isGoogleUser || auth.isAppleUser;
    // Deliberately gated on the stored flag alone, never on "is signed in".
    // Firebase keeps its session in the Keychain, which survives deleting the
    // app, so a signed-in user is NOT proof that onboarding was ever seen — on
    // a reinstall it would skip the whole intro. main() clears that leftover
    // session on a fresh install; this just trusts the flag.
    // Before showing a returning user's data, make sure the local vault belongs
    // to them (wipes it if a different account owned this device).
    if (widget.hasOnboarded && auth.isLoggedIn && verified) {
      await ensureLocalDataForCurrentUser();
      if (!mounted) return;
    }
    final Widget next;
    // AppPrefs.forcePreviewOnboarding: dev-only, set from Settings → 🔧 Dev.
    // Needed on top of `!widget.hasOnboarded` because OnbConnect marks
    // onboarding done again the moment its own "Toliau" is tapped — see that
    // flag's own doc for why the plain one-shot reset wasn't enough.
    if (kPreviewOnboarding ||
        AppPrefs.forcePreviewOnboarding ||
        !widget.hasOnboarded) {
      // Scene pages, each running the real app inside the artwork's phone,
      // then the bank connect. The pre-scene onboarding screens are gone.
      // An earlier bank-tiles page (OnbWelcome) briefly held this slot — the
      // tiles moved too fast to read and the intro was a page longer than it
      // needed to be — before onb_banks.dart's own bank-coverage page (see
      // below) replaced it. OnbWelcome has since been deleted.
      next = const OnbIntro(
        // 2026-08-17: bank-coverage page inserted here — see onb_banks.dart's
        // own doc for why every page after it bumped its own dotIndex by one.
        // 2026-08-18: OnbBudget ("Nepraleisk nė vienos prenumeratos") removed
        // from the chain entirely — dotCount is 6 throughout again.
        // 2026-09-01: OnbInvest inserted — dotCount bumped to 7.
        // 2026-09-02: moved from right after OnbMonth to right before
        // OnbFeatures (dotIndex 3 → 5; OnbOverview/OnbAiChat each shifted
        // one earlier to fill the gap) — per explicit request.
        next: OnbBanks(
          next: OnbMonth(
            next: OnbOverview(
              next: OnbAiChat(
                next: OnbInvest(
                  // Everything the intro had no room to demonstrate — the
                  // budget, the lock, reminders, recap, currencies —
                  // immediately before the ask, while still deciding.
                  next: OnbFeatures(next: OnbConnect(next: LoginScreen())),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (auth.isLoggedIn) {
      next = verified ? await landingAfterAuth() : const VerifyEmailScreen();
    } else {
      next = const LoginScreen();
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Vaultie" is a brand name and stays untranslated; only the tagline below
    // follows the app's language.
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Scaffold(
      // 2026-08-17: same off-center RadialGradient formula as Home's hero
      // and the Finansų Agentas banner (see dashboard_preview.dart's
      // _topBanner) — a bright spot near one corner fading toward a deep
      // navy, in place of the old centred glow-on-flat-blue. Confirmed live
      // on device as the "prabangu" look; see the [[vaultie-hero-gradient-premium]]
      // memory for the full formula/rationale.
      backgroundColor: const Color(0xFF081A4D),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -1.0),
            radius: 1.6,
            colors: [Color(0xFF3E63FF), Color(0xFF081A4D)],
            stops: [0.0, 0.65],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The mark alone, on transparent — the full icon would put a
              // blue tile on a blue field and disappear into it.
              FadeTransition(
                opacity: _logoFade,
                child: Image.asset(
                  'assets/icon/logo_mark.png',
                  width: 132,
                  height: 132,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 28),
              // Materialises out of a dim, unfocused state into full
              // brightness/sharpness together — opacity and blur ease in on
              // the same curve, so it reads as the word coming into focus
              // "iš prieblandos" rather than being typed or just fading in.
              AnimatedBuilder(
                animation: _wordmarkReveal,
                builder: (_, __) {
                  final t = _wordmarkReveal.value;
                  return Opacity(
                    opacity: t,
                    child: ImageFiltered(
                      imageFilter:
                          ui.ImageFilter.blur(sigmaX: (1 - t) * 7, sigmaY: (1 - t) * 7),
                      child: const Text(
                        _wordmark,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _taglineFade,
                child: Text(
                  isLt ? 'Išmanesni pinigų įpročiai' : 'Smarter money habits',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
