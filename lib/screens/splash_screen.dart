import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

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
    duration: const Duration(milliseconds: 700),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeIn,
  );

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Hold the splash for 2s, then fade-transition to the next screen.
    _timer = Timer(const Duration(seconds: 2), _goNext);
  }

  void _goNext() {
    if (!mounted) return;
    // New users see onboarding; otherwise a signed-in user goes straight to
    // the dashboard, and everyone else to the auth screen.
    final Widget next;
    if (!widget.hasOnboarded) {
      next = const OnboardingScreen();
    } else if (AuthService().isLoggedIn) {
      next = const DashboardScreen();
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
      backgroundColor: VaultieColors.primary, // #174E35
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo: white "V" in a rounded square.
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: VaultieColors.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'V',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Vaultie',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Smarter money habits',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
