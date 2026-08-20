import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'splash_screen.dart';

/// Onboarding page 2 — bank coverage. Inserted 2026-08-17 right after
/// OnbIntro, ahead of the existing OnbMonth/OnbOverview/OnbAiChat/
/// OnbFeatures chain — this page only bumps every later page's own
/// dotIndex by one (dotCount is 6 throughout; OnbBudget, once between
/// OnbAiChat and OnbFeatures, was removed 2026-08-18).
///
/// A full-bleed still (bank logos over a lit-up Europe globe, 853×1844 — same
/// aspect as page 1's own artwork), shown exactly as supplied: no scrim, no
/// recolouring, same rule as page 1's own photo.
class OnbBanks extends StatelessWidget {
  const OnbBanks({super.key, required this.next});

  final Widget next;

  void _next(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same Android-only downscale rule as OnbIntro, same reference width —
    // see that file's own comment for why this never touches iOS.
    final scale = Platform.isAndroid
        ? (MediaQuery.of(context).size.width / 393).clamp(0.86, 1.0)
        : 1.0;
    return wrapOnbStatusBar(Scaffold(
      backgroundColor: const Color(0xFF030E30),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/onboarding/page2_banks.png'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // ── Copy block: top, same placement as page 1 — plain text with a
          // soft drop shadow, same as every other page's copy block. ──
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(30, 40 * scale, 30, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Jungiame 2 700+ bankų\nvisoje Europoje'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30 * scale,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.7,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                              color: Color(0xB3000000),
                              blurRadius: 14,
                              offset: Offset(0, 3)),
                          Shadow(color: Color(0x66000000), blurRadius: 30),
                        ],
                      ),
                    ),
                    SizedBox(height: 8 * scale),
                    Text(
                      tr('Visi tavo bankai, visos tavo sąskaitos vienoje vietoje.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15.5 * scale,
                        height: 1.4,
                        color: Colors.white,
                        shadows: const [
                          Shadow(
                              color: Color(0xB3000000),
                              blurRadius: 10,
                              offset: Offset(0, 2)),
                          Shadow(color: Color(0x66000000), blurRadius: 22),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Button + dots: bottom, same as every page. ──
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _next(context),
                      child: Container(
                        height: 54,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF001450)
                                    .withValues(alpha: 0.45),
                                blurRadius: 22,
                                offset: const Offset(0, 10)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(tr('Toliau'),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1846E6))),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(width: double.infinity, child: _dots()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 1 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 1 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
