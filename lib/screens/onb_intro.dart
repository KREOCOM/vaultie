import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';
import 'splash_screen.dart';

/// Onboarding page 1 — a full-bleed still (the Vaultie tile mosaic) with the
/// copy on a scrim and a "Pradėti" action.
///
/// A video used to run here and was dropped deliberately. It was a brand reveal
/// whose wordmark landed at eight seconds, and people leave this page in three —
/// so almost nobody saw the payoff, and the splash one second earlier had just
/// shown them the same wordmark anyway. What it did cost was real: a 9 MB decode
/// on the slowest screen in the app, plus a poster to keep in sync, a
/// hold-the-last-frame rule and a loop seam that could all drift. The still is
/// 1.4 MB, draws on the first frame, and is the same composition people were
/// seeing in practice.
class OnbIntro extends StatefulWidget {
  const OnbIntro({super.key, required this.next});

  final Widget next;

  @override
  State<OnbIntro> createState() => _OnbIntroState();
}

class _OnbIntroState extends State<OnbIntro> {
  @override
  void initState() {
    super.initState();
    final auto = kOnbAutoAdvance;
    if (auto != null) {
      Future<void>.delayed(auto, () {
        if (mounted) _start();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Used to hang off the video controller finishing its initialisation. With
    // the video gone there is nothing to wait for, so it runs as soon as there
    // is a context to precache against.
    _warmNextPage();
  }

  /// The next page is by far the heaviest in the chain — a 2.4 MB scene image
  /// plus a full dashboard built from ~900 transactions. Doing that work inside
  /// its entry transition is what made "Toliau" stutter there and nowhere else,
  /// so it happens now, while this page is just playing its clip.
  ///
  /// This used to live on the bank-tiles page that sat between the two. Taking
  /// that page out of the chain took the warm-up with it, which would have put
  /// the stutter straight back — so it moved here.
  void _warmNextPage() {
    if (!mounted) return;
    DashboardPreview.warmDemo();
    precacheImage(
        const AssetImage('assets/onboarding/page3_scene.png'), context);
  }

  void _start() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This copy block was measured against a ~393dp-wide reference (a
    // current iPhone). Below that, the fixed font sizes and spacing take up
    // a growing fraction of a screen that isn't just narrower but usually
    // shorter too, which is what pushed the "2 500+ bankų" badge down onto
    // the photo's subject on a 360dp phone. Scaling text and spacing down
    // together keeps the block proportionally where it was designed to sit,
    // on any width; never scales UP, so the reference size is untouched.
    // Android-only: this page was already correct on iOS (the build already
    // submitted to App Review), tuned against a ~393dp-wide iPhone reference.
    // Scaling it on iOS too would touch phones smaller than that reference
    // (SE, mini) that were never reported as a problem — only Android's
    // shorter/narrower screens were.
    final scale = Platform.isAndroid
        ? (MediaQuery.of(context).size.width / 393).clamp(0.86, 1.0)
        : 1.0;
    return wrapOnbStatusBar(Scaffold(
      // The same near-black navy the scene pages settle on (`_deep` in
      // onb_scene_page.dart), so page 1's copy sits on the identical field as
      // every page after it.
      backgroundColor: const Color(0xFF030E30),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-bleed artwork ──
          // 2026-08-17 v4: a woman on a balcony at night, reading her phone,
          // a lit bank-tower skyline (HSBC, Citi) behind her — same 853×1844
          // aspect as v2/v3, same composition logic: clear dark sky top-left
          // is where the copy block below sits, no scrim needed there.
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/onboarding/page1_v4.png'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // ── Bottom wash / Top scrim, removed for v3 ──
          // 2026-08-17: per request, the photo shows exactly as supplied —
          // no darkening layered on top of it. v2's still needed both (the
          // "sky is already dark" assumption didn't always hold once
          // translated copy or Android's taller line-height pushed the text
          // block onto the brighter subject below, and the button/dots
          // strip needed grounding to the next page's #030E30). If v3 ever
          // shows a real contrast problem, that's worth solving directly —
          // just not by quietly recolouring the photo again.

          // ── Copy block: centred horizontally, near the top, on the clear
          // sky. 2026-08-19 v2: the solid gradient card didn't fit every
          // photo in the chain — plain text with a soft drop shadow reads
          // clean against all of them instead. ──
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(30, 40 * scale, 30, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Suprask savo\nfinansus aiškiau'),
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
                      tr('Vaultie padeda aiškiau matyti, kur keliauja tavo pinigai, priimti geresnius sprendimus ir viską stebėti vienoje vietoje.'),
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
                    // 2026-08-17: the "Jungiame prie 2 500+ bankų visoje
                    // Europoje" badge that sat here was removed — the bank-
                    // connect coverage gets its own page next in the chain,
                    // this one shouldn't say it first and then say it again.
                  ],
                ),
              ),
            ),
          ),

          // ── Button + dots: bottom, same as every page after this one. ──
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _start,
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
                        child: Text(tr('Pradėti'),
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
              width: i == 0 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 0 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
