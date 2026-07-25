import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n.dart';
import 'preview/dashboard_preview.dart';

/// Onboarding page 2 — full-bleed looping video (bank tiles across Europe) with
/// an OPAQUE bottom card holding the security message. The card lets the video
/// run full-frame (no need to leave empty space) and keeps the text perfectly
/// legible over any part of the video.
class OnbWelcome extends StatefulWidget {
  const OnbWelcome({super.key, required this.next});

  final Widget next;

  @override
  State<OnbWelcome> createState() => _OnbWelcomeState();
}

class _OnbWelcomeState extends State<OnbWelcome> {
  late final VideoPlayerController _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.asset('assets/onboarding/page2_loop.mp4')
      ..setLooping(true)
      ..setVolume(0);
    _c.initialize().then((_) {
      if (!mounted) return;
      _c.play();
      setState(() => _ready = true);
      _warmNextPage();
    });
  }

  /// Page 3 is by far the heaviest in the chain — a 2.4 MB scene image plus a
  /// full dashboard built from ~900 transactions. Doing that work inside its
  /// entry transition is what made "Toliau" stutter here and nowhere else, so
  /// it happens now instead, while this page just sits and loops.
  void _warmNextPage() {
    if (!mounted) return;
    DashboardPreview.warmDemo();
    precacheImage(
        const AssetImage('assets/onboarding/page3_scene.png'), context);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _next() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF071A54),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-bleed looping background video ──
          // The video's first frame, shown until the file is decoded. A 2–7 MB
          // asset does not open instantly, and without this the page arrived
          // empty and filled in a beat later — which reads as the tap not
          // having worked.
          Positioned.fill(
            child: Image.asset('assets/onboarding/page2_poster.jpg', fit: BoxFit.cover),
          ),
          if (_ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _c.value.size.width,
                height: _c.value.size.height,
                child: VideoPlayer(_c),
              ),
            ),

          // ── Strong bottom scrim so the centred text stays legible on video ──
          const Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.62,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00041446), Color(0xB304103A), Color(0xF2030E30)],
                    stops: [0.0, 0.42, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Variant 2: centred text with a trust badge, text on the video ──
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // trust badge (pill)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F6BFF).withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_rounded,
                              size: 13, color: Color(0xFFDBE6FF)),
                          const SizedBox(width: 7),
                          Text(
                            tr('Saugumas · Privatumas · Patikimumas'),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                                color: Color(0xFFDBE6FF)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tr('2500+ bankų\nvisoje Europoje'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -1.0,
                        color: Colors.white,
                        shadows: [Shadow(color: Color(0xB300081F), blurRadius: 18)],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr('Saugiai jungiamės per Enable Banking — banko lygio šifravimas ir PSD2 licencija. Tavo saugumas mums svarbiausias.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.86),
                        shadows: const [Shadow(color: Color(0x9900081F), blurRadius: 12)],
                      ),
                    ),
                    const SizedBox(height: 22),
                    GestureDetector(
                      onTap: _next,
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
                    const SizedBox(height: 18),
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

  // Page 2 of 4 active.
  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 1 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 1 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
