import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';
import 'splash_screen.dart';

/// Onboarding page 3 — the home feed, shown inside the empty phone drawn
/// into the background photo itself (page3_bg2.png — a hand holding a
/// phone against a dark blue field with light streaks).
///
/// 2026-08-18 v9: was a static screenshot clipped into the glass — now the
/// REAL [DashboardPreview] runs its own built-in `DemoScript.home` tour
/// (hide the balance, scroll the payments, open the recurring manager)
/// live inside the glass. Same trick [OnbScenePage] already uses for the
/// other onboarding pages: lay the widget out at a fixed virtual size via
/// a MediaQuery override, sized to the GLASS's own aspect ratio (not a real
/// handset's), then FittedBox.cover it in — since the virtual canvas's
/// aspect already matches the glass, cover neither crops nor stretches
/// anything, it's an exact fit by construction.
///
/// Geometry measured off page3_bg2.png (853×1844) via pixel sampling
/// (ImageMagick column/row scans, not eyeballed): screen glass
/// left=232, top=290, right=638, bottom=1230.
class OnbMonth extends StatefulWidget {
  const OnbMonth({super.key, required this.next});

  final Widget next;

  static const double _imgW = 853, _imgH = 1844;
  // 2026-08-18: shrunk 3px inward on every side past the measured edge —
  // the photo's own bezel edge isn't perfectly straight (a slight
  // perspective/curve to it), so sitting exactly ON the measured edge let
  // "Šią savaitę" hide a sliver under the bezel on the left.
  // 2026-08-18: glassB was flatly wrong — 1188, from a strip crop
  // misjudged by eye. Re-measured with an actual pixel column scan
  // (x=550, avoiding the thumb): content runs to y=1233, bezel starts
  // 1234. The phone was genuinely taller than the content, leaving a real
  // gap of the photo's own dark screen below the dashboard.
  static const double _glassL = 232, _glassT = 290, _glassR = 638, _glassB = 1230;
  static const double _corner = 46;

  /// Virtual layout width the live dashboard is measured at.
  ///
  /// [OnbScenePage] uses 320 (iPhone SE) for its lightweight PhoneShowcase,
  /// but the REAL Prenumeratos/Sąskaitos cards this page now embeds were
  /// never designed to fit two side-by-side that narrow — labels and euro
  /// figures both ellipsised at 320, and a 4-figure "Sąskaitos" total still
  /// did at 375. 390 (a standard modern iPhone's own logical width) is
  /// where both stop truncating — legible beats smaller-and-truncated.
  static const double _vw = 390;
  static double get _vh => _vw * (_glassB - _glassT) / (_glassR - _glassL);

  @override
  State<OnbMonth> createState() => _OnbMonthState();
}

class _OnbMonthState extends State<OnbMonth> {
  /// 2026-08-18: used to hold the live dashboard back until the entry
  /// transition finished, so building it wouldn't stutter the fade — but on
  /// a real device that wait was itself visible as a bare black rectangle
  /// inside the phone for a beat, which read far worse than the stutter it
  /// was avoiding. Starts live immediately now; still fades in over 260ms
  /// (see the AnimatedOpacity below) so the first frame isn't a hard cut.
  final bool _live = true;

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
          width: OnbMonth._vw,
          height: OnbMonth._vh,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(OnbMonth._vw, OnbMonth._vh),
              devicePixelRatio: 3,
              textScaler: const TextScaler.linear(1),
            ),
            // A NESTED Navigator: without one, Navigator.of(context) calls
            // made from inside DashboardPreview (opening a month's
            // "apžvalga", the recurring manager, anything) walk straight
            // past this whole subtree and find the app's OWN root
            // Navigator instead — so whatever they push takes over the
            // real, full device screen instead of staying inside this tiny
            // phone-in-photo. This gives DashboardPreview its own root
            // route to push onto, sized and clipped exactly like the rest
            // of it, so anything it opens is scaled and confined right
            // along with it.
            child: IgnorePointer(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) => const DashboardPreview(
                      demo: true, script: DemoScript.home),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final imgH = w * OnbMonth._imgH / OnbMonth._imgW;
    final scale = w / OnbMonth._imgW;

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
              image: AssetImage('assets/onboarding/page3_bg2.png'),
              fit: BoxFit.fill,
            ),
          ),

          // ── The phone's glass: the REAL dashboard, running its own
          // hands-free demo tour (hide balance, scroll, open recurring),
          // scaled to the glass's own aspect so it fills it exactly. ──
          Positioned(
            left: OnbMonth._glassL * scale,
            top: OnbMonth._glassT * scale,
            width: (OnbMonth._glassR - OnbMonth._glassL) * scale,
            height: (OnbMonth._glassB - OnbMonth._glassT) * scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OnbMonth._corner * scale),
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
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Matyk visą finansų vaizdą'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
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
                      tr('Balansai, išlaidos, pajamos, biudžetas vienoje aiškioje vietoje.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
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
                    const SizedBox(height: 32),
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
          for (var i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 2 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 2 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
