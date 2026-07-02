import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';

/// Gate shown to a signed-in-but-unverified user.
///
/// A verification email is sent at registration; this screen holds the user
/// here until they click the link. It polls Firebase every few seconds (and on
/// demand) so the moment the address is verified we slip through to the
/// dashboard — no manual restart required.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  static const route = '/verify-email';

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _auth = AuthService();

  Timer? _poll;
  Timer? _cooldown;
  int _resendIn = 0; // seconds until the resend button re-enables
  bool _checking = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  @override
  void initState() {
    super.initState();
    // No on-arrival countdown: the resend button is available immediately.
    // A short cooldown only kicks in after a manual resend (anti-spam).
    // Poll periodically; clicking the link happens out-of-app, so we can't
    // rely on a callback to tell us it's done.
    _poll = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkVerified(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cooldown?.cancel();
    super.dispose();
  }

  void _startCooldown([int seconds = 60]) {
    _cooldown?.cancel();
    setState(() => _resendIn = seconds);
    _cooldown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  /// Reloads the user and, if the address is now verified, advances to the app.
  Future<void> _checkVerified({bool showFeedback = false}) async {
    if (_checking) return;
    _checking = true;
    try {
      await _auth.reloadUser();
      if (!mounted) return;
      if (_auth.isEmailVerified) {
        _poll?.cancel();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      } else if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isLt
                ? 'Dar nepatvirtinta. Patikrinkite savo el. paštą.'
                : 'Not verified yet. Please check your inbox.'),
          ),
        );
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _resend() async {
    final isLt = _isLt;
    try {
      await _auth.sendEmailVerification();
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isLt
              ? 'Patvirtinimo laiškas išsiųstas dar kartą.'
              : 'Verification email sent again.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authErrorMessage(e, isLithuanian: isLt)),
          backgroundColor: VaultieColors.danger,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    final email = _auth.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F4),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 132,
                    height: 132,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                isLt ? 'Patvirtinkite savo el. paštą' : 'Verify your email',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: VaultieColors.subtle, height: 1.4),
                  children: [
                    TextSpan(
                      text: isLt
                          ? 'Išsiuntėme patvirtinimo nuorodą į\n'
                          : 'We sent a verification link to\n',
                    ),
                    TextSpan(
                      text: email,
                      style: const TextStyle(
                        color: VaultieColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: isLt
                          ? '.\nPaspauskite nuorodą, tada grįžkite čia.'
                          : '.\nTap the link, then come back here.',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                isLt
                    ? 'Nuoroda galioja 24 valandas — patvirtinti gali bet kada.'
                    : 'The link is valid for 24 hours — verify anytime.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VaultieColors.subtle,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed:
                    _checking ? null : () => _checkVerified(showFeedback: true),
                child: Text(isLt ? 'Patvirtinau' : "I've verified"),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _resendIn > 0 ? null : _resend,
                style: OutlinedButton.styleFrom(
                  foregroundColor: VaultieColors.primary,
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: VaultieColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _resendIn > 0
                      ? (isLt
                          ? 'Siųsti dar kartą (${_resendIn}s)'
                          : 'Resend email (${_resendIn}s)')
                      : (isLt ? 'Siųsti dar kartą' : 'Resend email'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _signOut,
                child: Text(
                  isLt ? 'Naudoti kitą paskyrą' : 'Use a different account',
                  style: const TextStyle(color: VaultieColors.subtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
