import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'splash_screen.dart';

/// Onboarding page 4 — investing, inserted 2026-09-01 between OnbMonth
/// (page 3) and OnbOverview, which bumps OnbOverview/OnbAiChat/OnbFeatures'
/// own dotIndex by one each (dotCount 6 → 7 throughout).
///
/// 2026-09-02, second rework: a live DashboardPreview demo (first full-
/// screen, then framed) chased a string of real bugs — a stale demo
/// pointer, awkward "Toliau" placement, tap targets landing on blank space
/// — one fix at a time, and kept not landing right. Dropped in favour of
/// what every OTHER page in this chain not built on a live tab already
/// does successfully (OnbIntro, OnbBanks): a plain full-bleed still
/// (853×1844 — same asset size as the rest of the chain) with the copy on
/// a scrim-free scrim, sat on the photo's own already-dark lower half —
/// same technique as OnbOverview's copy block, just with a real photo
/// behind it instead of a live phone. Simple, and — unlike the live
/// version — it can't develop a new bug of its own.
class OnbInvest extends StatelessWidget {
  const OnbInvest({super.key, required this.next});

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
    final h = MediaQuery.of(context).size.height;
    // Shifted up 5% of the screen's own height (not the image's) — cropping
    // a sliver off the top (empty sky above the ticker cards, nothing load-
    // bearing) rather than relying on BoxFit.cover's own alignment, which
    // has almost nothing to crop here: this photo's aspect (853×1844) is
    // already nearly identical to the device's own, so shifting the
    // ALIGNMENT a normal amount barely moves anything. Rendered 5% taller
    // than the screen so the bottom edge still lands exactly at the
    // screen's own bottom instead of falling short and exposing the
    // Scaffold colour above the "Toliau" area — that colour is set to the
    // photo's own sampled bottom-row average (#000315) regardless, as a
    // safety net for whichever device aspect ratio actually falls short.
    const shift = 0.05;
    return wrapOnbStatusBar(Scaffold(
      backgroundColor: const Color(0xFF00021C),
      body: Stack(
        children: [
          Positioned(
            top: -h * shift,
            left: 0,
            right: 0,
            height: h * (1 + shift),
            child: const Image(
              image: AssetImage('assets/onboarding/page_invest_bg.png'),
              fit: BoxFit.cover,
            ),
          ),
          // Headline + subtitle pinned at a fixed fraction down the screen —
          // per explicit request, moved OFF the very bottom (where it sat
          // flush against "Toliau") and up into the photo's own big empty
          // lower half, so that space reads as filled rather than wasted.
          Positioned(
            top: h * 0.66,
            left: 30,
            right: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Investicijos šalia tavo finansų'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.4,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                          color: Color(0xB3000000),
                          blurRadius: 14,
                          offset: Offset(0, 3)),
                      Shadow(color: Color(0x66000000), blurRadius: 30),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('Akcijas ir kriptovaliutas stebėk kartu su kasdieniais pinigais.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    height: 1.4,
                    color: Colors.white,
                    shadows: [
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
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 16),
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
          for (var i = 0; i < 7; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 5 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 5 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
