import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';

/// Onboarding page 4 — the Investavimas tab, inserted 2026-09-01 between
/// OnbMonth (page 3) and OnbOverview, which bumps OnbOverview/OnbAiChat/
/// OnbFeatures' own dotIndex by one each (dotCount 6 → 7 throughout).
///
/// 2026-09-02 rework, per explicit request: the phone-in-photo treatment
/// OnbMonth/OnbOverview use ("lievai atrodo" — it read as thin/cheap here)
/// is dropped for this page in favour of the REAL [DashboardPreview]
/// itself — but a first full-screen attempt ("Toliau" floating directly
/// over the live content) was corrected again just as quickly: shrunk back
/// into a framed card on a plain blue field, with "Toliau" given its own
/// space BELOW the frame instead of overlapping it — same rhythm as every
/// other page in the chain, just without a photo to align against. Home
/// shows first (with the real "Investicijos" quick action visible), then
/// `DemoScript.investing`'s own tour taps it, opens the empty state's
/// "Pridėti pirmą investiciją", picks Tesla, types 3 shares, confirms, sits
/// on the result, then loops back to Home and does it again.
///
/// The frame reuses OnbMonth's own virtual-canvas trick (lay the dashboard
/// out at a fixed size matched to the FRAME's own aspect, then
/// FittedBox.cover it in) but needs none of that page's pixel-sampled photo
/// geometry — the frame's shape is drawn here, not measured off an asset.
class OnbInvest extends StatelessWidget {
  const OnbInvest({super.key, required this.next});

  final Widget next;

  static const double _vw = 390, _vh = _vw * 19.5 / 9;

  void _nextPage(BuildContext context) {
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

  Widget _liveFrame() => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _vw,
          height: _vh,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(_vw, _vh),
              devicePixelRatio: 3,
              textScaler: TextScaler.linear(1),
            ),
            // IgnorePointer: this is a recording, not a screen the viewer
            // drives — same rule every other onboarding demo page follows.
            //
            // Still wrapped in its own private Navigator: the add-holding
            // sheet the tour opens is a REAL showModalBottomSheet call,
            // which pushes onto whatever Navigator it finds regardless of
            // IgnorePointer (that only blocks touch, not code) — without
            // this, it would push onto the app's real onboarding-chain
            // Navigator instead, and its own Navigator.pop(context, result)
            // could pop the wrong thing. Same isolation OnbOverview/OnbMonth
            // already use.
            child: IgnorePointer(
              child: Navigator(onGenerateRoute: _investingDemoRoute),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF020818),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // A soft blue glow behind the frame — atmosphere without needing
            // a photo asset, and it scales to any screen size for free.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 0.9,
                  colors: [Color(0xFF13297A), Color(0xFF020818)],
                  stops: [0, 1],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 22),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 9 / 19.5,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(34),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF1E4BFF)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 40,
                                    spreadRadius: 2),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: _liveFrame(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _nextPage(context),
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
                        _dots(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static Route<dynamic> _investingDemoRoute(RouteSettings settings) =>
      MaterialPageRoute(
        settings: settings,
        builder: (_) =>
            const DashboardPreview(demo: true, script: DemoScript.investing),
      );

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
