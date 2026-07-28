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
          // The render arrives 2:3 and is re-laid to 853×1844 before it lands
          // here — cards in the top 47%, the deep field extended below them — so
          // `cover` is close to a 1:1 fit and crops almost nothing. Dropped in at
          // its native 2:3 it would have lost 15% off each side and pushed the
          // bottom card down under the copy.
          //
          // Anchored to the TOP, unlike the tile render before it: the cards are
          // the subject and they live up there, so a short screen should lose
          // empty floor from the bottom rather than clip a card off the top.
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/onboarding/page1.png'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),

          // ── Bottom wash ──
          // Fades to #030E30 — the exact navy the scene pages use — so the strip
          // the copy sits on is the same shade across the whole chain. Fading to
          // the artwork's own blue instead left page 1 visibly lighter than every
          // page after it.
          //
          // Fully OPAQUE from 62% down, which is where this differs from the
          // scene pages: their scrim only reaches ~80% at its darkest, and this
          // render's last tile rows go soft and out of focus around two thirds of
          // the way down. A translucent wash left that blur glowing through the
          // text. Below 62% there is flat colour and nothing else.
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
                    // Placed against this render, not by eye: the cards finish at
                    // 54% and the copy begins around 58%, so the fade starts just
                    // under the last card — grounding it rather than slicing it —
                    // and is fully opaque by 72%, which also buries the seam at
                    // 76% where the render's own frame ends and the extended
                    // canvas begins.
                    stops: [0.54, 0.64, 0.72, 1.0],
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
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
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
                    const SizedBox(height: 16),
                    for (final b in const [
                      'Veikia su 2 500+ bankų ES, JK ir EEE',
                      'Reguliuojama PSD2 atviroji bankininkystė',
                      'Duomenys lieka tavo telefone',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
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
                    const SizedBox(height: 22),
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
