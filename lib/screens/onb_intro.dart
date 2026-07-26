import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n.dart';
import 'splash_screen.dart';

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
    final auto = kOnbAutoAdvance;
    if (auto != null) {
      Future<void>.delayed(auto, () {
        if (mounted) _start();
      });
    }
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
              heightFactor: 0.62,
              widthFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00041446), Color(0xB304113A), Color(0xFF030E32)],
                    stops: [0.0, 0.55, 0.86],
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
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Colors.white.withValues(alpha: 0.86),
                        shadows: const [
                          Shadow(color: Color(0x99001038), blurRadius: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final b in const [
                      'Veikia su 2 500+ bankų ES, JK ir EEE',
                      'Reguliuojama PSD2 atviroji bankininkystė',
                      'Duomenys lieka tavo telefone',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.check_rounded,
                                  size: 14, color: Color(0xFF8FB4FF)),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                tr(b),
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: Colors.white.withValues(alpha: 0.80),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
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
