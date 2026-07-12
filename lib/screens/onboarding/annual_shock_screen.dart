import 'package:flutter/material.dart';

import '../../theme/vaultie_theme.dart';

/// Screen 3 — Empathy ("annual shock"). A small monthly amount → down arrow →
/// the red annual total, driving home how tiny charges add up over a year.
class AnnualShockScreen extends StatelessWidget {
  const AnnualShockScreen({super.key, required this.onNext, this.onBack});

  final VoidCallback onNext;
  final VoidCallback? onBack;

  static const _subInk = Color(0xFF586158);
  static const _arrow = Color(0xFFB7C4BC);

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: onBack,
      segments: 4,
      segmentsFilled: 1,
      showLogo: true,
      bottom: VtPrimaryButton(label: 'Toliau', onPressed: onNext),
      child: Column(
        children: [
          const Spacer(flex: 2),
          const _MonthlyCard(),
          const SizedBox(height: 14),
          const Icon(Icons.arrow_downward_rounded, size: 26, color: _arrow),
          const SizedBox(height: 14),
          const _AnnualCard(),
          const Spacer(flex: 3),
          const Text(
            'Maži nurašymai virsta\ndidele suma',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: VT.ink,
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1.18,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '„Tik €13 per mėnesį" per metus tampa €156. Vaultie parodo tikrą skaičių.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _subInk,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
      decoration: BoxDecoration(
        color: VT.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: VT.softShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('NĖ NEPAJUNTI',
              style: TextStyle(
                  color: VT.subtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('€12.99',
                  style: TextStyle(
                      color: VT.ink,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('/mėn',
                    style: TextStyle(
                        color: VT.subtle,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnnualCard extends StatelessWidget {
  const _AnnualCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7D2B25), Color(0xFFC0483F)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC0483F).withValues(alpha: 0.34),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PER METUS',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6)),
          const SizedBox(height: 6),
          const Text('€156',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  height: 1.0)),
        ],
      ),
    );
  }
}
