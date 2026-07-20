import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../user_session.dart';
import 'login_screen.dart';
import 'onb_chat.dart';
import 'onb_connect.dart';
import 'onb_intro.dart';
import 'onb_month.dart';
import 'onb_planning.dart';
import 'onb_security.dart';
import 'onb_welcome.dart';
import 'onboarding_choice_screen.dart';
import 'verify_email_screen.dart';

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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  // Subtle fade-in for the logo + wordmark as the splash appears.
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Hold the splash for 2s, then fade-transition to the next screen.
    _timer = Timer(const Duration(seconds: 2), _goNext);
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    // New users see onboarding; a signed-in & verified user goes straight to
    // the dashboard; a signed-in but unverified user resumes at the verify
    // screen; everyone else lands on the auth screen.
    final auth = AuthService();
    // Deliberately gated on the stored flag alone, never on "is signed in".
    // Firebase keeps its session in the Keychain, which survives deleting the
    // app, so a signed-in user is NOT proof that onboarding was ever seen — on
    // a reinstall it would skip the whole intro. main() clears that leftover
    // session on a fresh install; this just trusts the flag.
    // Before showing a returning user's data, make sure the local vault belongs
    // to them (wipes it if a different account owned this device).
    if (widget.hasOnboarded && auth.isLoggedIn && auth.isEmailVerified) {
      await ensureLocalDataForCurrentUser();
      if (!mounted) return;
    }
    final Widget next;
    if (!widget.hasOnboarded) {
      // The five-screen onboarding built on top of the real dashboards. The
      // old OnboardingFlow is still in the tree, unused from here.
      next = const OnbIntro(
        next: OnbWelcome(
          next: OnbMonth(
            next: OnbPlanning(
              next: OnbSecurity(
                next: OnbChat(
                  next: OnbConnect(next: LoginScreen()),
                ),
              ),
            ),
          ),
        ),
      );
    } else if (auth.isLoggedIn) {
      next = auth.isEmailVerified
          ? landingAfterAuth()
          : const VerifyEmailScreen();
    } else {
      next = const LoginScreen();
    }
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
      // Brand blue, taken from the logo itself (#0144FB), with a lighter glow
      // behind the mark. The previous deep green was left over from an older
      // identity and clashed with both the new logo and the blue used across
      // onboarding and the dashboard.
      backgroundColor: const Color(0xFF0736C9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.35),
            radius: 0.95,
            colors: [Color(0xFF0144FB), Color(0x000736C9)],
            stops: [0.0, 0.78],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The mark alone, on transparent — the full icon would put a
                // blue tile on a blue field and disappear into it.
                Image.asset(
                  'assets/icon/logo_mark.png',
                  width: 132,
                  height: 132,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 28),
                const Text(
                  'Vaultie',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isLt ? 'Išmanesni pinigų įpročiai' : 'Smarter money habits',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
