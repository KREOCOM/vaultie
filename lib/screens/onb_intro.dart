import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n.dart';

/// Onboarding page 1 — a full-bleed looping intro video (the animated Vaultie
/// tile mosaic) with a frosted-glass text block and a "Pradėti" action.
///
/// The video is a seamless boomerang loop (assets/onboarding/intro_loop.mp4) so
/// it always looks in motion, with no visible restart.
class OnbIntro extends StatefulWidget {
  const OnbIntro({super.key, required this.next});

  final Widget next;

  @override
  State<OnbIntro> createState() => _OnbIntroState();
}

class _OnbIntroState extends State<OnbIntro> {
  late final VideoPlayerController _c;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.asset('assets/onboarding/intro_loop.mp4')
      ..setLooping(true)
      ..setVolume(0);
    _c.initialize().then((_) {
      if (!mounted) return;
      _c.play();
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start() {
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
      // A deep blue behind the video so the first frame doesn't flash white
      // while the controller initialises.
      backgroundColor: const Color(0xFF0A2A7A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Full-bleed looping background video ──
          // The video's first frame, shown until the file is decoded. A 2–7 MB
          // asset does not open instantly, and without this the page arrived
          // empty and filled in a beat later — which reads as the tap not
          // having worked.
          Positioned.fill(
            child: Image.asset('assets/onboarding/page1_poster.jpg', fit: BoxFit.cover),
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

          // ── Bottom scrim: blends the video into a calm area with no hard line ──
          const Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.55,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00041446), Color(0x8C04113A), Color(0xF2030E32)],
                    stops: [0.0, 0.5, 1.0],
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
                  children: [
                    // Highlighted Vaultie mark — real app icon with a blue glow
                    // and a soft white rim so it pops off the video.
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1.4),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFF3A78FF)
                                  .withValues(alpha: 0.6),
                              blurRadius: 34,
                              spreadRadius: 2),
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 18,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(19),
                        child: Image.asset('assets/icon/app_icon.png',
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      tr('Visi tavo pinigai\nvienoje vietoje'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -1.0,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Color(0xB3001038), blurRadius: 18),
                        ],
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      tr('Vaultie automatiškai surenka tavo finansus ir padeda lengviau juos suprasti.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.86),
                        shadows: const [
                          Shadow(color: Color(0x99001038), blurRadius: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
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
          for (var i = 0; i < 5; i++)
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
