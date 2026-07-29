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
    return Scaffold(
      // The same near-black navy the scene pages settle on (`_deep` in
      // onb_scene_page.dart), so page 1's copy sits on the identical field as
      // every page after it.
      backgroundColor: const Color(0xFF030E30),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-bleed artwork ──
          // 862×1825, a hair wider than the screen's ratio, so `cover` matches
          // the height and trims a few points off each side — nothing near the
          // subject. Anchored to the TOP: the phone and the floating cards are
          // the subject and they live up there, so a short screen should lose
          // empty floor from the bottom rather than clip the phone.
          //
          // Then lifted. Detail per horizontal strip of the render goes flat from
          // 63% down, so that is where the phone and the cards end and the
          // reflection begins; the copy block is bottom-anchored and starts
          // around 58%, so unlifted the artwork ran under the first lines.
          //
          // Landed on the device, not calculated: 6% left the phone's base
          // touching the headline's rule with no gap at all, and 12% overshot to
          // a 94pt hole with the phone's top crowding the status bar. 9% was the
          // midpoint that looked right.
          //
          // Back to 9% with the animated line removed. 12.5% existed only to
          // compensate for the 42pt OnbPulseLine pushing the copy block upward;
          // with the plain rule restored that compensation clips the phone's top
          // against the status bar instead.
          //
          // Raising the art does this without washing the phone out under a
          // scrim that starts higher. The strip of Scaffold it exposes at the
          // bottom is #030E30 — the colour the wash is already fully opaque in
          // by then — so it cannot be seen.
          Positioned.fill(
            child: Transform.translate(
              offset: Offset(0, -MediaQuery.of(context).size.height * 0.09),
              child: const Image(
                image: AssetImage('assets/onboarding/page1.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),

          // ── Bottom wash ──
          // Fades to #030E30 — the exact navy the scene pages use — so the strip
          // the copy sits on is the same shade across the whole chain. Fading to
          // the artwork's own blue instead left page 1 visibly lighter than every
          // page after it.
          //
          // Fully OPAQUE well before the copy, which is where this differs from
          // the scene pages: their scrim only reaches ~80% at its darkest, and
          // this render's reflection stays faintly lit all the way down. A
          // translucent wash left that glow coming through the text.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00030E30),
                      Color(0x99030E30),
                      Color(0xFF030E30),
                      Color(0xFF030E30),
                    ],
                    // Measured against this render AFTER the lift above: its
                    // subject ends at 63% of the image, which the 9% lift puts
                    // around 55% of the screen. The wash starts just under that,
                    // so it grounds the reflection rather than slicing the phone,
                    // and is flat colour by 68% — clear of the copy block, which
                    // is bottom-anchored and starts around 58%.
                    //
                    // These three numbers belong to THIS artwork. Every previous
                    // set was measured against a different render and carried
                    // over wrongly. Re-measure when the image changes: crop 24px
                    // strips down the file and watch where the compressed size
                    // stops falling — that is where the subject ends.
                    stops: [0.55, 0.62, 0.68, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Variant A: text directly on the scrim, with the Vaultie mark
          // highlighted (glowing app icon) above the headline. ──
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      tr('Suprask savo\nfinansus geriau'),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.9,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      tr('Vaultie padeda aiškiau matyti, kur keliauja tavo pinigai, priimti geresnius sprendimus ir viską stebėti vienoje vietoje.'),
                      // No drop shadow any more. It existed to keep this legible
                      // over moving artwork; the copy now sits on flat colour, and
                      // a shadow there only softens the edges of the letters.
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final b in const [
                      'Veikia su 2 500+ bankų ES, JK ir EEE',
                      'Reguliuojama PSD2 atviroji bankininkystė',
                      'Duomenys lieka tavo telefone',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_rounded,
                                  size: 14, color: Color(0xFF9EC0FF)),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                tr(b),
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Colors.white.withValues(alpha: 0.86),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
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
    );
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
