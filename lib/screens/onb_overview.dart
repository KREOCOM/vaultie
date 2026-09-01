import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';
import 'splash_screen.dart';

/// Onboarding page 4 — the Apžvalga tab, shown inside the empty phone drawn
/// into the background photo itself (page4_bg.png — a standing phone with a
/// glowing neon rim against a dark textured wall).
///
/// Same technique as [OnbMonth] (page 3): a REAL [DashboardPreview] runs
/// live inside the glass, its own `DemoScript.overview` tour driving it
/// (switch to Apžvalga, open the savings-rate breakdown), laid out at a
/// virtual size matched to the glass's own aspect ratio so FittedBox.cover
/// fits it exactly, with a nested Navigator so anything the tour pushes
/// (the savings breakdown) stays confined to the phone instead of taking
/// over the real screen.
///
/// Geometry measured off page4_bg.png (853×1844) via pixel sampling
/// (ImageMagick row/column scans at three different heights, not
/// eyeballed): screen glass left=222, top=353, right=628, bottom=1286.
class OnbOverview extends StatefulWidget {
  const OnbOverview({super.key, required this.next});

  final Widget next;

  static const double _imgW = 853, _imgH = 1844;
  // Shrunk 3px inward on every side past the measured edge, same reasoning
  // as OnbMonth's page3_bg2.png: the photo's own bezel/glow isn't a
  // perfectly straight line, so sitting exactly on the measured edge risks
  // a sliver of content hiding under it.
  // 2026-08-18: glassT nudged up from the measured 353 (minus the usual 3px
  // margin, so 356) to 349 — a sliver of the photo's own screen glow was
  // showing above the dashboard, meaning the margin ate too far into the
  // glass on this particular photo.
  static const double _glassL = 225, _glassT = 349, _glassR = 625, _glassB = 1283;
  static const double _corner = 46;

  /// See OnbMonth's own doc comment on this constant — same reasoning here.
  static const double _vw = 390;
  static double get _vh => _vw * (_glassB - _glassT) / (_glassR - _glassL);

  @override
  State<OnbOverview> createState() => _OnbOverviewState();
}

class _OnbOverviewState extends State<OnbOverview> {
  /// 2026-08-18: see OnbMonth's own doc comment on this field — same fix,
  /// same reason (the deferred-mount wait itself read as a bare black
  /// rectangle on a real device).
  bool _live = true;

  void _nextPage() {
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

  Widget _liveDashboard() => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: OnbOverview._vw,
          height: OnbOverview._vh,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(OnbOverview._vw, OnbOverview._vh),
              devicePixelRatio: 3,
              textScaler: const TextScaler.linear(1),
            ),
            child: IgnorePointer(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => const DashboardPreview(
                      demo: true, script: DemoScript.overview),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final imgH = w * OnbOverview._imgH / OnbOverview._imgW;
    final scale = w / OnbOverview._imgW;

    return wrapOnbStatusBar(Scaffold(
      backgroundColor: const Color(0xFF020818),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            width: w,
            height: imgH,
            child: const Image(
              image: AssetImage('assets/onboarding/page4_bg.png'),
              fit: BoxFit.fill,
            ),
          ),

          // ── The phone's glass: the REAL Apžvalga tab, running its own
          // hands-free tour (switch tabs, open the savings breakdown),
          // scaled to the glass's own aspect so it fills it exactly. ──
          Positioned(
            left: OnbOverview._glassL * scale,
            top: OnbOverview._glassT * scale,
            width: (OnbOverview._glassR - OnbOverview._glassL) * scale,
            height: (OnbOverview._glassB - OnbOverview._glassT) * scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OnbOverview._corner * scale),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF01021A)),
                  ),
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _live ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: _live ? _liveDashboard() : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Copy block: bottom, plain text (no card) — a card read as
          // not fitting this particular photo, so it's just the words
          // themselves, kept legible with a soft drop shadow, sized to sit
          // above the button without needing to touch the photo at all. ──
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Stebėk, kur gali sutaupyti'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
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
                    const SizedBox(height: 6),
                    Text(
                      tr('Atrask prenumeratas, sąskaitas ir sek savo santaupų normą.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.35,
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
                    const SizedBox(height: 34),
                    GestureDetector(
                      onTap: _nextPage,
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
              width: i == 4 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 4 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
