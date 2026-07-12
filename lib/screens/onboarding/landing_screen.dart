import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/vaultie_theme.dart';

/// Screen 1 — Landing (final). Light canvas with a soft green glow, an animated
/// green hero card (floats, breathing shadow, shimmer sweep) showing the monthly
/// total, then a benefit-led headline and the primary CTA.
class LandingScreen extends StatefulWidget {
  const LandingScreen({
    super.key,
    required this.onStart,
    required this.onHaveAccount,
  });

  final VoidCallback onStart;
  final VoidCallback onHaveAccount;

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat(reverse: true);

  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5500),
  )..repeat();

  static const _subInk = Color(0xFF586158);

  @override
  void dispose() {
    _float.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.15,
            colors: [Color(0xFFE7F2E8), Color(0xFFEDF0EA)],
            stops: [0.0, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset('assets/icon/app_icon.png',
                          width: 30, height: 30, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 9),
                    const Text('Vaultie',
                        style: TextStyle(
                            color: VT.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2)),
                  ],
                ),
                const Spacer(),
                _AnimatedHero(float: _float, shimmer: _shimmer),
                const Spacer(),
                const Text(
                  'Sužinok, kur dingsta\ntavo pinigai',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: VT.ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Nuoma, prenumeratos, draudimas — viskas vienoje vietoje.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _subInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                const Spacer(),
                VtPrimaryButton(label: 'Pradėti', onPressed: widget.onStart),
                const SizedBox(height: 4),
                VtTextButton(
                    label: 'Jau turiu paskyrą',
                    onPressed: widget.onHaveAccount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _AnimatedHero extends StatelessWidget {
  const _AnimatedHero({required this.float, required this.shimmer});

  final Animation<double> float;
  final Animation<double> shimmer;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([float, shimmer]),
      builder: (context, _) {
        final t = Curves.easeInOut.transform(float.value); // 0 low → 1 high
        final offsetY = _lerp(6, -6, t);
        // Quick shimmer sweep in the first ~28% of the cycle, then off-screen.
        final sp = Curves.easeIn.transform((shimmer.value / 0.28).clamp(0, 1));
        final sx = _lerp(-1.35, 1.35, sp);

        return Transform.translate(
          offset: Offset(0, offsetY),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF20704E),
                  Color(0xFF164A34),
                  Color(0xFF0F3826),
                ],
                stops: const [0.0, 0.55, 1.0],
                transform:
                    const GradientRotation(158 * math.pi / 180),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F3826)
                      .withValues(alpha: _lerp(0.24, 0.16, t)),
                  blurRadius: _lerp(22, 40, t),
                  offset: Offset(0, _lerp(12, 26, t)),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  const _HeroContent(),
                  // Inner top-left light glare.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.8, -0.95),
                            radius: 1.1,
                            colors: [
                              Colors.white.withValues(alpha: 0.16),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.62],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Shimmer streak.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment(sx, 0),
                        child: Transform.rotate(
                          angle: 0.32,
                          child: Container(
                            width: 66,
                            height: 320,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: 0.14),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent();

  static const _mint = Color(0xFFA9D3BA);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('KAS MĖNESĮ IŠEINA',
              style: TextStyle(
                  color: _mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('€',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 2),
              const Text('687',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 50,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      height: 1.0)),
              const SizedBox(width: 5),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('/mėn',
                    style: TextStyle(
                        color: _mint,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
          const SizedBox(height: 14),
          Row(
            children: [
              _tile(const Color(0xFF6D9E3F), Icons.home_rounded),
              const SizedBox(width: 11),
              const Text('Nuoma',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              const Text('€650',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              _tile(const Color(0xFFE85D5D), null, letter: 'N'),
              const SizedBox(width: 11),
              const Text('Netflix',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              const _WarnChip(text: 'nenaudota 3 mėn.'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(Color color, IconData? icon, {String? letter}) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: icon != null
          ? Icon(icon, color: Colors.white, size: 16)
          : Text(letter ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
    );
  }
}

class _WarnChip extends StatelessWidget {
  const _WarnChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E3BB),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 12.5, color: Color(0xFF8A6A16)),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  color: Color(0xFF8A6A16),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
