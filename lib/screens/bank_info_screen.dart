import 'package:flutter/material.dart';

import 'bank_connect_screen.dart';

const Color _brightGreen = Color(0xFF4CAF72);

/// Explains how the bank connection works before showing the bank list, so the
/// user understands the security/privacy model up front. "Continue" replaces
/// this screen with the bank list, so backing out returns to wherever the flow
/// started (dashboard or settings), not here.
class BankInfoScreen extends StatelessWidget {
  const BankInfoScreen({super.key});

  static const route = '/bank-info';

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final points = isLt
        ? const [
            (Icons.lock_rounded, 'Prisijungsite per saugų „Enable Banking" tiltą'),
            (
              Icons.visibility_off_rounded,
              'Matysime tik transakcijų istoriją — jokių slaptažodžių'
            ),
            (Icons.smartphone_rounded, 'Duomenys saugomi tik jūsų telefone'),
            (Icons.event_available_rounded, 'Sutikimas galioja 90 dienų'),
          ]
        : const [
            (Icons.lock_rounded, 'You\'ll sign in through the secure Enable Banking bridge'),
            (
              Icons.visibility_off_rounded,
              'We only see your transaction history — never your passwords'
            ),
            (Icons.smartphone_rounded, 'Your data is stored only on your phone'),
            (Icons.event_available_rounded, 'Your consent lasts 90 days'),
          ];

    return Scaffold(
      backgroundColor: const Color(0xFF050F08),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.6),
                    radius: 1.1,
                    colors: [Color(0x662E6B4D), Color(0x00050F08)],
                    stops: [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _brightGreen.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(color: _brightGreen, width: 1.5),
                      ),
                      child: const Icon(Icons.account_balance_rounded,
                          color: _brightGreen, size: 38),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isLt
                        ? 'Kaip veikia banko prijungimas?'
                        : 'How does connecting your bank work?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 32),
                  for (final p in points) ...[
                    _point(p.$1, p.$2),
                    const SizedBox(height: 18),
                  ],
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brightGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                      elevation: 8,
                      shadowColor: _brightGreen,
                    ),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const BankConnectScreen()),
                    ),
                    child: Text(isLt ? 'Tęsti' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _point(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _brightGreen, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
