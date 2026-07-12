import 'package:flutter/material.dart';

import '../../theme/vaultie_theme.dart';

/// Screen 3 — Empathy. Centered hero glyph + headline + subcopy + "Toliau".
/// Normalises the problem before the diagnostic questions. Reusable so we can
/// show one or two of these back to back.
class EmpathyScreen extends StatelessWidget {
  const EmpathyScreen({
    super.key,
    required this.icon,
    required this.headline,
    required this.body,
    required this.onNext,
    this.onBack,
    this.buttonLabel = 'Toliau',
  });

  final IconData icon;
  final String headline;
  final String body;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: onBack,
      bottom: VtPrimaryButton(label: buttonLabel, onPressed: onNext),
      child: Column(
        children: [
          const Spacer(flex: 3),
          _HeroGlyph(icon: icon),
          const Spacer(flex: 2),
          Text(headline, textAlign: TextAlign.center, style: VT.display),
          const SizedBox(height: 16),
          Text(body, textAlign: TextAlign.center, style: VT.body),
          const Spacer(flex: 4),
        ],
      ),
    );
  }
}

/// Soft green gradient circle with a glow and a white glyph.
class _HeroGlyph extends StatelessWidget {
  const _HeroGlyph({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 128,
      height: 128,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: VT.heroGradient,
        boxShadow: [
          BoxShadow(
            color: VT.brand.withValues(alpha: 0.30),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 58),
    );
  }
}
