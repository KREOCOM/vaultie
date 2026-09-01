import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';
import 'splash_screen.dart';

/// Onboarding page 4 — the Investavimas tab, shown inside the empty phone
/// drawn into the background photo itself (page_invest_bg.png — a phone
/// floating face-on against a black field with vertical blue neon streaks).
/// Inserted 2026-09-01 between OnbMonth (page 3) and OnbOverview, which
/// bumps OnbOverview/OnbAiChat/OnbFeatures' own dotIndex by one each
/// (dotCount 6 → 7 throughout — same mechanics as OnbBanks' own insertion).
///
/// Same technique as [OnbOverview]: a REAL [DashboardPreview] runs live
/// inside the glass, its own `DemoScript.investing` tour driving it (open
/// the empty tab's own "Pridėti pirmą investiciją", pick Tesla, enter 3
/// shares, confirm — the sheet's own scripted sequence, see
/// investing_tab.dart's `_AddHoldingSheetState.demo`), laid out at a
/// virtual size matched to the glass's own aspect ratio so FittedBox.cover
/// fits it exactly, with a nested Navigator so the sheet the tour opens
/// stays confined to the phone instead of taking over the real screen.
///
/// Geometry measured off page_invest_bg.png (1023×1537) via pixel sampling
/// (ImageMagick row/column scans at three different heights, not
/// eyeballed): screen glass left=322, top=204, right=713, bottom=1118.
class OnbInvest extends StatefulWidget {
  const OnbInvest({super.key, required this.next});

  final Widget next;

  static const double _imgW = 1023, _imgH = 1537;
  // Shrunk ~3px inward on every side past the measured edge, same reasoning
  // as OnbOverview's own doc: sitting exactly on the measured edge risks a
  // sliver of the phone's own rim glow hiding under it.
  //
  // _glassT nudged from 207 to 197 (2026-09-01): a 2x-zoom re-crop with
  // ruler lines drawn directly on the source photo (every 5px, well outside
  // both the notch and the corner curve) placed the rim's own inner edge —
  // where the screen's content actually starts — right at 195-200, not 207.
  // A first attempt at this same fix overshot to 162 (mistaking the rim's
  // OUTER glow bloom for the screen edge) and pushed the content up far
  // enough to draw over the rim itself instead of just closing the gap.
  static const double _glassL = 325, _glassT = 197, _glassR = 710, _glassB = 1115;
  static const double _corner = 42;

  /// See OnbOverview's own doc comment on this constant — same reasoning here.
  static const double _vw = 390;
  static double get _vh => _vw * (_glassB - _glassT) / (_glassR - _glassL);

  @override
  State<OnbInvest> createState() => _OnbInvestState();
}

class _OnbInvestState extends State<OnbInvest> {
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
          width: OnbInvest._vw,
          height: OnbInvest._vh,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(OnbInvest._vw, OnbInvest._vh),
              devicePixelRatio: 3,
              textScaler: const TextScaler.linear(1),
            ),
            child: IgnorePointer(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => const DashboardPreview(
                      demo: true, script: DemoScript.investing),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    // This photo's own aspect (1023×1537 ≈ 1.50) is noticeably SHORTER than
    // a phone screen's (≈2.16, what OnbMonth/OnbOverview's own artwork was
    // shot at) — scaling it to fit the device WIDTH the way those pages do
    // left a plain background gap between the artwork and the copy instead
    // of reaching the bottom edge. Scaling to fill the device HEIGHT instead
    // (and centring the now-wider-than-the-screen result, cropping the sides
    // symmetrically — the streaks either side of the phone are decorative
    // padding, nothing load-bearing gets cut) makes the phone read at the
    // same scale the other live-dashboard pages use, edge to edge.
    final scale = h / OnbInvest._imgH;
    final renderedW = OnbInvest._imgW * scale;
    final xOffset = (w - renderedW) / 2;
    // Filling the image all the way to the screen's own bottom edge (see
    // this method's own doc above) left the headline sitting right on top
    // of the photo's floor-reflection strip, with no breathing room between
    // them ("teksta liečia telefoną" — text touching the phone). Shifting
    // the whole image (and the glass inside it, by the same amount) up by a
    // fixed amount keeps the phone at the same size — nothing scales down —
    // while opening a plain-background gap at the bottom for the copy to
    // sit in; the little extra sky this crops off the top is inconsequential.
    const bottomGap = 76.0;

    return wrapOnbStatusBar(Scaffold(
      backgroundColor: const Color(0xFF020818),
      body: Stack(
        children: [
          Positioned(
            top: -bottomGap,
            left: xOffset,
            width: renderedW,
            height: h,
            child: const Image(
              image: AssetImage('assets/onboarding/page_invest_bg.png'),
              fit: BoxFit.fill,
            ),
          ),

          // ── The phone's glass: the REAL Investavimas tab, running its own
          // hands-free tour (open the empty state, add a first position),
          // scaled to the glass's own aspect so it fills it exactly. ──
          Positioned(
            left: xOffset + OnbInvest._glassL * scale,
            top: -bottomGap + OnbInvest._glassT * scale,
            width: (OnbInvest._glassR - OnbInvest._glassL) * scale,
            height: (OnbInvest._glassB - OnbInvest._glassT) * scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OnbInvest._corner * scale),
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

          // ── Copy block: bottom, plain text (no card) — same as OnbOverview. ──
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Sek ir investicijas'),
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
                      tr('Akcijos ir kriptovaliuta, konvertuotos į eurus, šalia visų tavo finansų.'),
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
              width: i == 3 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 3 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
