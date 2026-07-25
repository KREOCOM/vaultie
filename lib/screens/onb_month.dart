import 'package:flutter/material.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';

/// Onboarding page 3 — "here's the app". The full rendered scene (phone on the
/// tile platform, neon ring, floating logos) is shown as-is, never cropped. The
/// LIVE [DashboardPreview] is overlaid onto the phone's SCREEN (below the status
/// bar, clipped to the rounded bottom) so it's real Flutter — automatically in
/// the user's language — and a plain black Dynamic Island pill hides the scene's
/// green status indicator.
class OnbMonth extends StatelessWidget {
  const OnbMonth({super.key, required this.next});

  final Widget next;

  // Phone SCREEN content area inside page3_scene.png (940×1672), as fractions.
  // Tune these to align the dashboard with the scene's phone screen.
  static const double _scx = 0.272; // content left
  static const double _scy = 0.205; // content top (just below the status bar)
  static const double _scw = 0.456; // content width
  static const double _sch = 0.512; // content height (down to the nav bar)
  // Black island pill that hides the green indicator.
  static const double _ix = 0.405, _iy = 0.181, _iw = 0.19, _ih = 0.032;

  void _next(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final imgH = w * 1672 / 940; // scene drawn full width, top-aligned
    return Scaffold(
      backgroundColor: const Color(0xFF03081C),
      body: Stack(
        children: [
          // ── Full scene (never cropped) ──
          Positioned(
            top: 0,
            left: 0,
            width: w,
            height: imgH,
            child: Image.asset('assets/onboarding/page3_scene.png',
                fit: BoxFit.cover),
          ),

          // ── Live dashboard exactly on the phone screen ──
          Positioned(
            left: _scx * w,
            top: _scy * imgH,
            width: _scw * w,
            height: _sch * imgH,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(_scw * w * 0.14)),
              child: const FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: 390,
                  height: 844,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      size: Size(390, 844),
                      devicePixelRatio: 3,
                      padding: EdgeInsets.zero,
                      textScaler: TextScaler.linear(1),
                    ),
                    child: const IgnorePointer(child: DashboardPreview()),
                  ),
                ),
              ),
            ),
          ),

          // ── Black Dynamic Island pill hiding the green indicator ──
          Positioned(
            left: _ix * w,
            top: _iy * imgH,
            width: _iw * w,
            height: _ih * imgH,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(_ih * imgH),
              ),
            ),
          ),

          // ── Bottom action (text added later) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
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
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1846E6))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dots(),
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
          for (var i = 0; i < 4; i++)
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
