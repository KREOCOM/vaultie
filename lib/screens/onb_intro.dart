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
          // A night-city lifestyle photo (852×1846): the subject sits in the
          // lower-right two-thirds, and the top ~38% is clear dark-blue sky —
          // that empty band is deliberately where the copy block below sits,
          // no scrim needed there since the sky is already near-black-blue.
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/onboarding/page1_v2.png'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // ── Bottom wash ──
          // Grounds the button/dots strip to the same #030E30 every later page
          // opens on, same reasoning as before — just a shorter fade since this
          // render is already dark near its own bottom edge.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00030E30),
                      Color(0xCC030E30),
                      Color(0xFF030E30),
                    ],
                    stops: [0.78, 0.9, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Top scrim ──
          // The "sky is already dark" assumption above holds on the render
          // this was tuned against, but longer translated copy — or just
          // Android's taller line-height metrics — can push the text block
          // past that ~38% sky band onto the brighter subject below. This
          // guarantees contrast regardless of exactly how tall the copy
          // block ends up; it is invisible where the sky is already dark.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC030E30),
                      Color(0x00030E30),
                    ],
                    stops: [0.0, 0.5],
                  ),
                ),
              ),
            ),
          ),

          // ── Copy block: centred horizontally, near the top, on the clear
          // sky — no side elements, just the words (matches the approved
          // HTML mockup exactly: no floating cards, no numbers). ──
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(28, 40 * scale, 28, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(height: 13 * scale),
                    Text(
                      tr('Suprask savo\nfinansus geriau'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30 * scale,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.9,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 11 * scale),
                    Text(
                      tr('Vaultie padeda aiškiau matyti, kur keliauja tavo pinigai, priimti geresnius sprendimus ir viską stebėti vienoje vietoje.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5 * scale,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    SizedBox(height: 18 * scale),
                    // Outline-only, no fill — sits on the clear sky without
                    // reading as a UI card on top of the photo. Wraps to a
                    // second line on its own (no nowrap) instead of ever
                    // touching the screen edges on a narrower phone.
                    Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9 * scale),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 1.5),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                          children: [
                            TextSpan(text: tr('Jungiame prie ')),
                            TextSpan(
                              text: tr('2 500+ bankų'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(text: tr(' visoje Europoje')),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
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
