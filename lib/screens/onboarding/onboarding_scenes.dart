import 'package:flutter/material.dart';

/// Per-question composed scenes for the diagnostic screens (each question gets
/// its own scene instead of the logo).

/// A central € coin with four scattered category dots and grey "motion" dashes —
/// "where does your money go?".
class MoneyScatterScene extends StatelessWidget {
  const MoneyScatterScene({super.key});

  static const _amber = Color(0xFFE9B44C);
  static const _red = Color(0xFFE07A5F);
  static const _blue = Color(0xFF3B82F6);
  static const _purple = Color(0xFF8B5CF6);
  static const _dashColor = Color(0xFFC4CFC7);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 184,
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Motion dashes — sit in the gap between the coin and each dot,
          // angled along the line toward it.
          _dash(left: 47, top: 37, angle: 0.56), // → amber (top-left)
          _dash(left: 116, top: 39, angle: -0.53), // → red (top-right)
          _dash(left: 50, top: 81, angle: -0.60), // → blue (bottom-left)
          _dash(left: 118, top: 81, angle: 0.57), // → purple (bottom-right)
          // Scattered category dots.
          Positioned(left: 6, top: 2, child: _dot(22, _amber)),
          Positioned(right: 10, top: 8, child: _dot(18, _red)),
          Positioned(left: 14, bottom: 4, child: _dot(16, _blue)),
          Positioned(right: 4, bottom: 0, child: _dot(20, _purple)),
          // Center € coin.
          _coin(),
        ],
      ),
    );
  }

  Widget _dash({required double left, required double top, required double angle}) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 16,
          height: 2.5,
          decoration: BoxDecoration(
            color: _dashColor,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ),
    );
  }

  Widget _dot(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.18)!, color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }

  Widget _coin() {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A9D6E), Color(0xFF174E35)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF174E35).withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Text('€',
          style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.0)),
    );
  }
}

/// A fanned-out hand of 5 service tiles (YouTube, Spotify, Netflix, rent,
/// insurance) — "how many services do you pay for?".
///
/// NOTE (real app): merchant tiles should use a brand-icon pack (simple-icons),
/// bill tiles use the category-icon set, with a fallback badge for unknowns.
/// Here they're lightweight approximations for the mock UI.
class ServiceFanScene extends StatelessWidget {
  const ServiceFanScene({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 186,
      height: 108,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Outer first (drawn under), center (Netflix) last (on top).
          _tile(
            left: 4,
            top: 44,
            angle: -0.279, // -16°
            color: const Color(0xFFFF0000),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 26),
          ),
          _tile(
            left: 132,
            top: 40,
            angle: 0.297, // +17°
            color: const Color(0xFF3B82F6),
            child: const Icon(Icons.verified_user_rounded,
                color: Colors.white, size: 23),
          ),
          _tile(
            left: 35,
            top: 26,
            angle: -0.140, // -8°
            color: const Color(0xFF1DB954),
            child: _spotifyWaves(),
          ),
          _tile(
            left: 103,
            top: 24,
            angle: 0.157, // +9°
            color: const Color(0xFF65A30D),
            child:
                const Icon(Icons.home_rounded, color: Colors.white, size: 23),
          ),
          _tile(
            left: 69,
            top: 16,
            angle: 0, // center
            color: const Color(0xFF000000),
            child: const Text('N',
                style: TextStyle(
                    color: Color(0xFFE50914),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.0)),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required double left,
    required double top,
    required double angle,
    required Color color,
    required Widget child,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _spotifyWaves() {
    Widget bar(double w) => Container(
          width: w,
          height: 2.6,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(2)),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [bar(20), const SizedBox(height: 3.5), bar(15), const SizedBox(height: 3.5), bar(10)],
    );
  }
}
