import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../user_session.dart';
import 'auth_screen.dart';
import 'onboarding/account_screen.dart';
import 'onboarding_choice_screen.dart';

/// Standalone login / sign-up for returning-but-signed-out users (after sign
/// out, account deletion, or a launch when not signed in). Reuses the new
/// onboarding [AccountScreen] design so the login experience is consistent
/// with the rest of the app. Google/Apple sign in inline; email opens the
/// existing email form ([AuthScreen]).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const route = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AccountScreen(
          onGoogle: () => _social(_auth.signInWithGoogle,
              fail: _isLt
                  ? 'Nepavyko prisijungti su Google.'
                  : 'Google sign-in failed.'),
          onApple: () => _social(_auth.signInWithApple,
              fail: _isLt
                  ? 'Nepavyko prisijungti su Apple.'
                  : 'Apple sign-in failed.'),
          onEmail: _email,
          onSignIn: _email,
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          ),
      ],
    );
  }
}
