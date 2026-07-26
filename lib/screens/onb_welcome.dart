import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n.dart';
import 'splash_screen.dart';
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
    final auto = kOnbAutoAdvance;
    if (auto != null) {
      Future<void>.delayed(auto, () {
        if (mounted) _next();
      });
    }
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

          // ── Centred copy over the video ──
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
                      tr('Prijunk savo\nbanką saugiai'),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.9,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr('Prisijungimą patvirtini savo banke. Vaultie gauna tik skaitymo prieigą — negali pervesti pinigų ar atlikti mokėjimų. Prieigą bet kada gali atšaukti.'),
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

  // Page 2 of 4 active.
  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
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
