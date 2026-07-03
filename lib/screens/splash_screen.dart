import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../user_session.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';
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
    // Before showing a returning user's data, make sure the local vault belongs
    // to them (wipes it if a different account owned this device).
    if (widget.hasOnboarded && auth.isLoggedIn && auth.isEmailVerified) {
      await ensureLocalDataForCurrentUser();
      if (!mounted) return;
    }
    final Widget next;
    if (!widget.hasOnboarded) {
      next = const OnboardingScreen();
    } else if (auth.isLoggedIn) {
      next = auth.isEmailVerified
          ? const DashboardScreen()
          : const VerifyEmailScreen();
    } else {
      next = const AuthScreen();
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // dark charcoal
      body: Container(
        // Subtle green radial glow behind the logo.
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.1),
            radius: 0.9,
            colors: [Color(0x662E6B4D), Color(0x001A1A1A)],
            stops: [0.0, 0.75],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo: the app icon, clipped to a rounded square.
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 132,
                    height: 132,
                    fit: BoxFit.cover,
                  ),
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
                  'Smarter money habits',
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
