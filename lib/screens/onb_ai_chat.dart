import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';
import 'splash_screen.dart';

/// Onboarding page 5 — the AI assistant, shown inside the empty phone drawn
/// into the background photo itself (page5_bg.png — a standing phone with a
/// glowing neon rim against a dark faceted-crystal wall).
///
/// Same technique as [OnbMonth]/[OnbOverview]: a REAL [DashboardPreview]
/// runs live inside the glass, its own `DemoScript.chat` tour driving it —
/// opens ON Home (so the "Tavo finansų agentas" banner is actually seen
/// being tapped, not skipped past), then answers a starter question and a
/// specific one — with a nested Navigator so both the chat screen itself
/// and anything it's part of stay confined to the phone.
///
/// Geometry measured off page5_bg.png (853×1844) via pixel sampling
/// (ImageMagick row/column scans at three different heights, not
/// eyeballed): screen glass left=211, top=343, right=630, bottom=1317.
class OnbAiChat extends StatefulWidget {
  const OnbAiChat({super.key, required this.next});

  final Widget next;

  static const double _imgW = 853, _imgH = 1844;
  // Shrunk 3px inward on every side past the measured edge, same reasoning
  // as the other live-embed pages: the photo's own bezel/glow isn't a
  // perfectly straight line, so sitting exactly on the measured edge risks
  // a sliver of content hiding under it.
  static const double _glassL = 214, _glassT = 346, _glassR = 627, _glassB = 1314;
  static const double _corner = 46;

  /// See OnbMonth's own doc comment on this constant — same reasoning here.
  static const double _vw = 390;
  static double get _vh => _vw * (_glassB - _glassT) / (_glassR - _glassL);

  @override
  State<OnbAiChat> createState() => _OnbAiChatState();
}

class _OnbAiChatState extends State<OnbAiChat> {
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
          width: OnbAiChat._vw,
          height: OnbAiChat._vh,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(OnbAiChat._vw, OnbAiChat._vh),
              devicePixelRatio: 3,
              textScaler: const TextScaler.linear(1),
            ),
            child: IgnorePointer(
              child: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(
                  builder: (_) =>
                      const DashboardPreview(demo: true, script: DemoScript.chat),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final imgH = w * OnbAiChat._imgH / OnbAiChat._imgW;
    final scale = w / OnbAiChat._imgW;

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
              image: AssetImage('assets/onboarding/page5_bg.png'),
              fit: BoxFit.fill,
            ),
          ),

          // ── The phone's glass: the REAL app, running its own hands-free
          // tour (tap the agent banner, ask a question, ask another),
          // scaled to the glass's own aspect so it fills it exactly. ──
          Positioned(
            left: OnbAiChat._glassL * scale,
            top: OnbAiChat._glassT * scale,
            width: (OnbAiChat._glassR - OnbAiChat._glassL) * scale,
            height: (OnbAiChat._glassB - OnbAiChat._glassT) * scale,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OnbAiChat._corner * scale),
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
                    // 2026-09-04: the per-page blue accent word was tried
                    // here and reverted — see OnbBanks' own doc, same reason.
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: tr('Klausk agento apie savo ')),
                        TextSpan(text: tr('finansus')),
                      ]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 25,
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
                      tr('Gauk atsakymus, paremtus tavo realiais finansiniais duomenimis.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
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
                    const SizedBox(height: 16),
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
