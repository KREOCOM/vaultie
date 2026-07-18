import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Onboarding, built one section at a time. This is the top illustration only —
/// the copy, feature rows and button come next.
///
/// The illustration is drawn in Flutter rather than shipped as an image, for
/// three reasons: a PNG has one aspect ratio and phones span 0.428 to 0.562, so
/// any fixed image loses 15–36% of itself to BoxFit.cover; the logos here are
/// already bundled in assets/logos/; and vector-drawn tiles stay sharp on every
/// density.
///
/// What it shows is deliberately literal: these are the subscriptions the
/// recurring classifier finds, orbiting the Vaultie mark.
class OnbTop extends StatefulWidget {
  const OnbTop({super.key, required this.next});
  final Widget next;

  @override
  State<OnbTop> createState() => _OnbTopState();
}

/// A logo tile placed on the canvas. [x] and [y] are fractions of the
/// illustration box, so the composition scales with the screen instead of
/// depending on fixed pixel positions.
class _Tile {
  const _Tile(this.asset, this.x, this.y, this.size, {this.tilt = 0, this.found = false});
  final String asset;
  final double x, y, size, tilt;
  final bool found;
}

class _OnbTopState extends State<OnbTop> with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF101828);
  static const _brand = Color(0xFF1B4DF5);
  static const _tileBg = Colors.white;

  // Placed by hand: nothing sits under the Vaultie mark in the middle, and the
  // outermost tile keeps a margin from the edges on the narrowest phone.
  static const _tiles = [
    _Tile('assets/logos/netflix.png', 0.13, 0.16, 52, tilt: -0.08, found: true),
    _Tile('assets/logos/spotify.png', 0.80, 0.10, 46, tilt: 0.10, found: true),
    _Tile('assets/logos/youtube.png', 0.86, 0.44, 50, tilt: -0.05),
    _Tile('assets/logos/icloud.png', 0.08, 0.52, 44, tilt: 0.07),
    _Tile('assets/logos/disney.png', 0.22, 0.82, 48, tilt: -0.06),
    _Tile('assets/logos/hbo.png', 0.72, 0.80, 44, tilt: 0.09, found: true),
    _Tile('assets/logos/telia.png', 0.50, 0.05, 40, tilt: 0.04),
    _Tile('assets/logos/dropbox.png', 0.47, 0.90, 40, tilt: -0.07),
  ];

  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 5200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 8),
            Expanded(flex: 5, child: _illustration()),
            // The rest of the screen is built in the next pass.
            const Expanded(flex: 4, child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Text('V',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 9),
            const Text('Vaultie',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: _ink)),
          ],
        ),
      );

  Widget _illustration() {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Keep the composition inside a square-ish area so it reads the same on
        // a short iPhone SE and a tall 21:9 Android.
        final side = math.min(w, h * 1.05);
        final left = (w - side) / 2;

        return Stack(
          alignment: Alignment.center,
          children: [
            // soft brand glow behind everything
            Center(
              child: Container(
                width: side * 0.86,
                height: side * 0.86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_brand.withValues(alpha: 0.10), _brand.withValues(alpha: 0.0)],
                  ),
                ),
              ),
            ),

            // two faint orbit rings
            for (final r in [0.62, 0.86])
              Center(
                child: Container(
                  width: side * r,
                  height: side * r,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE8EDF9), width: 1),
                  ),
                ),
              ),

            // the logo tiles
            for (var i = 0; i < _tiles.length; i++) _tile(_tiles[i], i, left, side, h),

            // the Vaultie mark, centred
            Center(child: _mark(side)),
          ],
        );
      },
    );
  }

  Widget _tile(_Tile t, int i, double left, double side, double boxH) {
    final size = t.size * (side / 360); // scale with the canvas
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // each tile drifts on its own phase so the group never pulses in unison
        final phase = (_c.value + i * 0.17) % 1.0;
        final dy = math.sin(phase * 2 * math.pi) * 5.0;
        return Positioned(
          left: left + t.x * side - size / 2,
          top: t.y * boxH - size / 2 + dy,
          child: Transform.rotate(angle: t.tilt, child: child),
        );
      },
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              padding: EdgeInsets.all(size * 0.2),
              decoration: BoxDecoration(
                color: _tileBg,
                borderRadius: BorderRadius.circular(size * 0.29),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0B1F4D).withValues(alpha: 0.13),
                    blurRadius: size * 0.34,
                    offset: Offset(0, size * 0.12),
                  ),
                ],
              ),
              child: Image.asset(t.asset, fit: BoxFit.contain),
            ),
            if (t.found)
              Positioned(
                right: -size * 0.08,
                top: -size * 0.08,
                child: Container(
                  width: size * 0.36,
                  height: size * 0.36,
                  decoration: const BoxDecoration(color: Color(0xFF12B76A), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(Icons.check_rounded, size: size * 0.24, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mark(double side) {
    final s = side * 0.24;
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s * 0.29),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A97FF), Color(0xFF1B4DF5)],
        ),
        boxShadow: [
          BoxShadow(color: _brand.withValues(alpha: 0.36), blurRadius: s * 0.5, offset: Offset(0, s * 0.18)),
        ],
      ),
      alignment: Alignment.center,
      child: Text('V',
          style: TextStyle(color: Colors.white, fontSize: s * 0.52, fontWeight: FontWeight.w800, height: 1)),
    );
  }
}
