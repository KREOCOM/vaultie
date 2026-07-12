import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/vaultie_theme.dart';
import '../legal_screen.dart';

/// Account screen — create an account / sign in. Google, Apple or email.
/// Goes after the "Two paths" screen. Buttons follow the official brand
/// guidelines (colored Google "G" on white; white Apple mark on black).
///
/// The three sign-in callbacks are wired to AuthService at app-integration
/// time; in the standalone preview they simply advance the flow.
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.onGoogle,
    required this.onApple,
    required this.onEmail,
    this.onSignIn,
    this.onBack,
  });

  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onEmail;
  final VoidCallback? onSignIn;
  final VoidCallback? onBack;

  static const _subInk = Color(0xFF586158);

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: onBack,
      gradientBg: true,
      bottom: _signInRow(),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: c.maxHeight, minWidth: c.maxWidth),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Real app logo in a rounded-square tile.
                Center(
                  child: Container(
                    width: 54,
                    height: 54,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: VT.softShadow,
                    ),
                    child: Image.asset('assets/icon/app_icon.png',
                        fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 20),
              const Text('Sukurk paskyrą',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: VT.ink,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4)),
              const SizedBox(height: 10),
              const Text(
                'Prisijunk per Google, Apple arba el. paštą.\nTai užtruks mažiau nei minutę.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _subInk,
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 28),
              _AuthButton(
                label: 'Tęsti su Google',
                bg: Colors.white,
                fg: const Color(0xFF14231C),
                border: const Color(0xFFDBE1DC),
                onTap: onGoogle,
                leading: Image.asset('assets/icon/google_g.png',
                    width: 20, height: 20),
              ),
              const SizedBox(height: 12),
              _AuthButton(
                label: 'Tęsti su Apple',
                bg: Colors.black,
                fg: Colors.white,
                onTap: onApple,
                leading: const Icon(Icons.apple, color: Colors.white, size: 23),
              ),
              const SizedBox(height: 12),
              _AuthButton(
                label: 'Tęsti su el. paštu',
                bg: VT.brand,
                fg: Colors.white,
                onTap: onEmail,
                leading: const Icon(Icons.mail_outline_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(height: 20),
              _trustLine(),
              const SizedBox(height: 14),
              _termsText(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trustLine() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_rounded, size: 12, color: VT.subtle),
        const SizedBox(width: 5),
        Text('Šifruota · Privatūs duomenys · GDPR',
            style: TextStyle(
                color: VT.subtle.withValues(alpha: 0.9),
                fontSize: 11.5,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _openLegal(BuildContext context, {required bool terms}) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            terms ? LegalScreen.terms(isLt) : LegalScreen.privacy(isLt),
      ),
    );
  }

  Widget _termsText(BuildContext context) {
    const base = TextStyle(
        color: VT.subtle, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w500);
    final link = base.copyWith(color: VT.brand, fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Tęsdamas sutinki su '),
        TextSpan(
            text: 'Sąlygomis',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openLegal(context, terms: true)),
        const TextSpan(text: ' ir '),
        TextSpan(
            text: 'Privatumo politika',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openLegal(context, terms: false)),
        const TextSpan(text: '.'),
      ]),
      textAlign: TextAlign.center,
      style: base,
    );
  }

  Widget _signInRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Jau turi paskyrą? ',
            style: TextStyle(
                color: VT.subtle, fontSize: 13.5, fontWeight: FontWeight.w500)),
        GestureDetector(
          onTap: onSignIn,
          child: const Text('Prisijunk',
              style: TextStyle(
                  color: VT.brand, fontSize: 13.5, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// Full-width sign-in button: leading logo pinned left, label centered.
class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.leading,
    required this.onTap,
    this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Widget leading;
  final VoidCallback onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(26),
            border: border != null ? Border.all(color: border!) : null,
          ),
          child: SizedBox(
            height: 53,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(left: 18, child: leading),
                Text(label,
                    style: TextStyle(
                        color: fg, fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
