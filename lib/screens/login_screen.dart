import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/auth_service.dart';
import '../user_session.dart';
import 'auth_screen.dart';
import 'legal_screen.dart';
import 'landing.dart';

/// Standalone login / sign-up for returning-but-signed-out users, and the
/// screen the onboarding hands off to.
///
/// This used to render `onboarding/AccountScreen`, which is built on the older
/// green `VT` identity — dark green brand, green-black ink, a green-tinted
/// ground. Against the blue logo and the blue onboarding it read as a different
/// product. The design here is deliberately plain: the real sign-in screen is
/// still to be designed, and nothing should be worth keeping by accident.
///
/// **The sign-in itself is untouched.** Google, Apple and email call exactly the
/// same handlers as before, and `AccountScreen` is left in place for the old
/// OnboardingFlow, so nothing had to be deleted to change how this looks.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const route = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

const _ink = Color(0xFF061439);
const _sub = Color(0xFF5C6A85);
const _brand = Color(0xFF2F6BFF);
const _paper = Color(0xFFFDFDFE);
const _hair = Color(0xFFE3E9F2);

class _LoginScreenState extends State<LoginScreen> {
  late final _auth = AuthService();
  bool _busy = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  Future<void> _social(Future<Object?> Function() signIn,
      {required String fail}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cred = await signIn();
      if (cred == null) return; // user cancelled
      if (!mounted) return;
      await ensureLocalDataForCurrentUser();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => landingAfterAuth()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(fail)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _email() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );

  void _openLegal({required bool terms}) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => terms ? LegalScreen.terms(isLt) : LegalScreen.privacy(isLt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 62,
                      height: 62,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A2260).withValues(alpha: 0.16),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(tr('Sukurk paskyrą'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: _ink, fontSize: 26, fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 10),
                  Text(
                    tr('Prisijunk per Google, Apple arba el. paštą.\nTai užtruks mažiau nei minutę.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _sub, fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 30),
                  _button(
                    label: tr('Tęsti su Google'),
                    bg: Colors.white,
                    fg: _ink,
                    border: _hair,
                    leading: Image.asset('assets/icon/google_g.png', width: 20, height: 20),
                    onTap: () => _social(_auth.signInWithGoogle,
                        fail: _isLt ? 'Nepavyko prisijungti su Google.' : 'Google sign-in failed.'),
                  ),
                  const SizedBox(height: 12),
                  _button(
                    label: tr('Tęsti su Apple'),
                    bg: Colors.black,
                    fg: Colors.white,
                    leading: const Icon(Icons.apple, color: Colors.white, size: 23),
                    onTap: () => _social(_auth.signInWithApple,
                        fail: _isLt ? 'Nepavyko prisijungti su Apple.' : 'Apple sign-in failed.'),
                  ),
                  const SizedBox(height: 12),
                  _button(
                    label: tr('Tęsti su el. paštu'),
                    bg: _brand,
                    fg: Colors.white,
                    leading: const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 20),
                    onTap: _email,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_rounded, size: 12, color: _sub),
                      const SizedBox(width: 5),
                      Text(tr('Šifruota · Privatūs duomenys · GDPR'),
                          style: const TextStyle(
                              color: _sub, fontSize: 11.5, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _terms(),
                ],
              ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required Color bg,
    required Color fg,
    required Widget leading,
    required VoidCallback onTap,
    Color? border,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(15),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  /// Kept verbatim from the previous screen — the terms and privacy links are a
  /// store requirement, not decoration.
  Widget _terms() {
    const base = TextStyle(color: _sub, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w500);
    final link = base.copyWith(color: _brand, fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: tr('Tęsdamas sutinki su ')),
        TextSpan(
            text: tr('Sąlygomis'),
            style: link,
            recognizer: TapGestureRecognizer()..onTap = () => _openLegal(terms: true)),
        TextSpan(text: tr(' ir ')),
        TextSpan(
            text: tr('Privatumo politika'),
            style: link,
            recognizer: TapGestureRecognizer()..onTap = () => _openLegal(terms: false)),
        const TextSpan(text: '.'),
      ]),
      textAlign: TextAlign.center,
      style: base,
    );
  }
}
