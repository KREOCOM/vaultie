import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../user_session.dart';
import 'login_screen.dart';
import 'landing.dart';

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
  bool _resending = false; // true only while a resend request is in flight
  bool _checking = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  @override
  void initState() {
    super.initState();
    // Poll periodically; clicking the link happens out-of-app, so we can't
    // rely on a callback to tell us it's done. The resend button is always
    // available (no countdown) — Firebase rate-limits abuse on its side.
    _poll = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkVerified(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
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
        await ensureLocalDataForCurrentUser();
        if (!mounted) return;
        final landing = await landingAfterAuth();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => landing),
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
    } on FirebaseAuthException catch (e) {
      // reloadUser() can throw (network-request-failed, user-token-expired,
      // user-disabled). Uncaught it escaped into the 4s poll timer and the
      // button's onPressed → an unhandled async error logged as FATAL every 4s.
      // Stop polling on a terminal auth state; otherwise just swallow (or, on a
      // manual tap, say it couldn't check).
      const terminal = {'user-disabled', 'user-token-expired', 'user-not-found'};
      if (terminal.contains(e.code)) _poll?.cancel();
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isLt
                ? 'Nepavyko patikrinti. Bandykite dar kartą.'
                : "Couldn't check. Please try again.")));
      }
    } catch (_) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_isLt
                ? 'Nepavyko patikrinti. Bandykite dar kartą.'
                : "Couldn't check. Please try again.")));
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _resend() async {
    final isLt = _isLt;
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await _auth.sendEmailVerification();
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    final email = _auth.currentUser?.email ?? '';
    return Scaffold(
      // Shared with login_screen: this gate sits BETWEEN two dark screens, so
      // its own cream background made sign-up flash dark → light → dark.
      backgroundColor: authPaper,
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
                style: const TextStyle(
                    color: authInk,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                      color: authSub, fontSize: 13.5, height: 1.45),
                  children: [
                    TextSpan(
                      text: isLt
                          ? 'Išsiuntėme patvirtinimo nuorodą į\n'
                          : 'We sent a verification link to\n',
                    ),
                    TextSpan(
                      text: email,
                      style: const TextStyle(
                        color: authInk,
                        fontWeight: FontWeight.w700,
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
                  color: authSub,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              // Firebase's default emails often land in spam; nudge the user to
              // check there and mark it "Not spam" so future links are clickable.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // Amber carried onto the dark ground as a translucent wash
                  // rather than the cream panel it was: a solid light block here
                  // reads as a second background, which is what made this screen
                  // look like a different app.
                  color: const Color(0x1FF0C674),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x66F0C674)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.report_gmailerrorred_outlined,
                        color: Color(0xFFF0C674), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isLt
                            ? 'Nerandi laiško? Patikrink šlamšto (Spam) aplanką ir pažymėk „Ne šlamštas".'
                            : "Can't find it? Check your Spam folder and mark it \"Not spam\".",
                        style: const TextStyle(
                            color: Color(0xFFEBD9AE),
                            fontSize: 12.5,
                            height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed:
                    _checking ? null : () => _checkVerified(showFeedback: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: authBrand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF1B2A55),
                  disabledForegroundColor: authSub,
                  minimumSize: const Size.fromHeight(54),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                child: Text(isLt ? 'Patvirtinau' : "I've verified"),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _resending ? null : _resend,
                style: OutlinedButton.styleFrom(
                  foregroundColor: authInk,
                  minimumSize: const Size.fromHeight(54),
                  // A brand-blue hairline on near-black is almost invisible;
                  // the secondary action needs a border that can be seen.
                  side: const BorderSide(color: Color(0x3DFFFFFF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
                child: Text(isLt ? 'Siųsti dar kartą' : 'Resend email'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _signOut,
                child: Text(
                  isLt ? 'Naudoti kitą paskyrą' : 'Use a different account',
                  style: const TextStyle(color: authSub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
