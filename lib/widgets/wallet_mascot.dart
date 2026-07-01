import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

/// Expressions Vaultie can pull. Old values (happy/neutral/worried) are kept so
/// existing screens keep working; new scenes use [confused] and [scanning].
enum MascotMood { happy, neutral, worried, confused, scanning }

/// "Vaultie" — a rounded, Pixar-ish green wallet character.
///
/// Continuously floats up and down with a soft squash-and-stretch, blinks on a
/// timer, and changes its whole face per [mood]. Drawn entirely with a
/// [CustomPainter] so there are no image assets to ship.
class WalletMascot extends StatefulWidget {
  const WalletMascot({
    super.key,
    this.size = 160,
    this.mood = MascotMood.happy,
    this.animate = true,
  });

  final double size;
  final MascotMood mood;
  final bool animate;

  @override
  State<WalletMascot> createState() => _WalletMascotState();
}

class _WalletMascotState extends State<WalletMascot>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _float.repeat(reverse: true);
      _blink.repeat();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_float, _blink]),
      builder: (context, _) {
        final lift = Curves.easeInOut.transform(_float.value); // 0..1
        final bob = (lift - 0.5) * 2 * (widget.size * 0.05);

        // Volume-preserving squash & stretch, anchored at the feet.
        final sy = 1 + (lift - 0.5) * 0.06;
        final sx = 1 - (lift - 0.5) * 0.06;

        // Quick blink near the end of the cycle.
        final bv = _blink.value;
        final blinking = bv > 0.95 && bv < 0.99;
        var eyeOpen = blinking ? 0.12 : 1.0;
        if (widget.mood == MascotMood.scanning) eyeOpen *= 0.7;

        // Pupils sweep side to side while scanning.
        final scanPhase =
            widget.mood == MascotMood.scanning ? (lift * 2 - 1) : 0.0;

        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(sx, sy, 1),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _MascotPainter(
                mood: widget.mood,
                eyeOpen: eyeOpen,
                scanPhase: scanPhase,
                lift: lift,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.mood,
    required this.eyeOpen,
    required this.scanPhase,
    required this.lift,
  });

  final MascotMood mood;
  final double eyeOpen;
  final double scanPhase;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    RRect box(double l, double t, double w, double h, double r) =>
        RRect.fromRectAndRadius(
            Rect.fromLTWH(l * s, t * s, w * s, h * s), Radius.circular(r * s));

    // ---- Ground shadow (shrinks as the mascot lifts) ----
    final shadowW = 0.46 * (1 - 0.18 * lift);
    canvas.drawOval(
      Rect.fromCenter(
        center: p(0.5, 0.95),
        width: shadowW * s,
        height: 0.05 * s,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.10),
    );

    // ---- Stubby feet ----
    final feet = Paint()..color = VaultieColors.primaryDark;
    canvas.drawRRect(box(0.34, 0.82, 0.12, 0.07, 0.035), feet);
    canvas.drawRRect(box(0.54, 0.82, 0.12, 0.07, 0.035), feet);

    // ---- A card peeking out of the top ----
    canvas.drawRRect(box(0.32, 0.18, 0.36, 0.18, 0.04),
        Paint()..color = VaultieColors.accent);
    canvas.drawRRect(box(0.32, 0.18, 0.36, 0.05, 0.02),
        Paint()..color = Colors.white.withValues(alpha: 0.55));

    // ---- Stubby arms ----
    final arm = Paint()..color = VaultieColors.primaryLight;
    canvas.drawRRect(box(0.07, 0.50, 0.12, 0.07, 0.035), arm);
    canvas.drawRRect(box(0.81, 0.50, 0.12, 0.07, 0.035), arm);

    // ---- Wallet body ----
    final bodyRect = box(0.14, 0.26, 0.72, 0.60, 0.24);
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2E6B4D), VaultieColors.primary],
      ).createShader(bodyRect.outerRect);
    canvas.drawRRect(bodyRect, bodyPaint);

    // Glossy sheen on the upper body.
    canvas.drawRRect(box(0.22, 0.31, 0.56, 0.12, 0.10),
        Paint()..color = Colors.white.withValues(alpha: 0.10));

    // Front pocket (slightly darker, overlapping the lower half).
    canvas.drawRRect(
      box(0.14, 0.54, 0.72, 0.32, 0.24),
      Paint()..color = Color.lerp(VaultieColors.primary, VaultieColors.primaryDark, 0.35)!,
    );

    // Clasp button where the fold meets.
    canvas.drawCircle(p(0.5, 0.54), 0.055 * s, Paint()..color = VaultieColors.accent);
    canvas.drawCircle(
        p(0.5, 0.54), 0.026 * s, Paint()..color = VaultieColors.primaryDark);

    _drawFace(canvas, s, p, box);
  }

  void _drawFace(
    Canvas canvas,
    double s,
    Offset Function(double, double) p,
    RRect Function(double, double, double, double, double) box,
  ) {
    final leftEye = p(0.40, 0.46);
    final rightEye = p(0.60, 0.46);
    final eyeRx = 0.075 * s;
    final eyeRy = 0.10 * s * eyeOpen;

    // Cheeks (warm blush) for the friendlier moods.
    if (mood == MascotMood.happy || mood == MascotMood.neutral) {
      final cheek = Paint()..color = const Color(0xFFFF9E80).withValues(alpha: 0.35);
      canvas.drawCircle(p(0.31, 0.55), 0.035 * s, cheek);
      canvas.drawCircle(p(0.69, 0.55), 0.035 * s, cheek);
    }

    // Eye whites.
    final white = Paint()..color = Colors.white;
    for (final c in [leftEye, rightEye]) {
      canvas.drawOval(
        Rect.fromCenter(center: c, width: eyeRx * 2, height: eyeRy * 2),
        white,
      );
    }

    if (eyeOpen > 0.3) {
      // Pupils, nudged by the current expression.
      final dx = scanPhase * 0.32 * eyeRx;
      final dy = switch (mood) {
        MascotMood.confused => -0.25 * eyeRy,
        MascotMood.worried => 0.15 * eyeRy,
        _ => -0.05 * eyeRy,
      };
      final pupil = Paint()..color = const Color(0xFF0E2A1D);
      final spark = Paint()..color = Colors.white;
      for (final c in [leftEye, rightEye]) {
        final pc = c + Offset(dx, dy);
        canvas.drawCircle(pc, 0.036 * s, pupil);
        canvas.drawCircle(pc + Offset(-0.013 * s, -0.015 * s), 0.013 * s, spark);
      }
    } else {
      // Closed/blinking — happy lash arcs.
      final lash = Paint()
        ..color = const Color(0xFF0E2A1D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.018 * s
        ..strokeCap = StrokeCap.round;
      for (final c in [leftEye, rightEye]) {
        final path = Path()
          ..moveTo(c.dx - eyeRx, c.dy)
          ..quadraticBezierTo(c.dx, c.dy + 0.05 * s, c.dx + eyeRx, c.dy);
        canvas.drawPath(path, lash);
      }
    }

    _drawBrows(canvas, s, leftEye, rightEye, eyeRx);
    _drawMouth(canvas, s, p);
    if (mood == MascotMood.confused) _drawQuestionMark(canvas, s);
  }

  void _drawBrows(
      Canvas canvas, double s, Offset le, Offset re, double eyeRx) {
    if (mood == MascotMood.happy || mood == MascotMood.neutral) return;
    final brow = Paint()
      ..color = const Color(0xFF0E2A1D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.022 * s
      ..strokeCap = StrokeCap.round;
    final y = le.dy - 0.105 * s;

    void line(Offset c, double leftDy, double rightDy) {
      canvas.drawLine(
        Offset(c.dx - eyeRx, y + leftDy),
        Offset(c.dx + eyeRx, y + rightDy),
        brow,
      );
    }

    switch (mood) {
      case MascotMood.confused:
        line(le, -0.03 * s, 0.0); // raised, quizzical
        line(re, 0.01 * s, 0.02 * s); // lowered
      case MascotMood.worried:
        line(le, 0.02 * s, -0.02 * s); // angled up & in
        line(re, -0.02 * s, 0.02 * s);
      case MascotMood.scanning:
        line(le, 0.015 * s, 0.015 * s); // focused, flat-low
        line(re, 0.015 * s, 0.015 * s);
      default:
        break;
    }
  }

  void _drawMouth(Canvas canvas, double s, Offset Function(double, double) p) {
    final center = p(0.5, 0.66);
    final stroke = Paint()
      ..color = const Color(0xFF0E2A1D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.022 * s
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = const Color(0xFF0E2A1D);

    switch (mood) {
      case MascotMood.happy:
        // Big open grin with a little tongue.
        final w = 0.11 * s;
        final rect = Rect.fromCenter(center: center, width: w * 2, height: 0.16 * s);
        final path = Path()
          ..moveTo(center.dx - w, center.dy)
          ..arcTo(rect, 0, math.pi, false)
          ..close();
        canvas.drawPath(path, fill);
        canvas.drawArc(
          Rect.fromCenter(
              center: center + Offset(0, 0.045 * s), width: w, height: 0.07 * s),
          0,
          math.pi,
          false,
          Paint()..color = const Color(0xFFFF7E6B),
        );
      case MascotMood.neutral:
        final path = Path()
          ..moveTo(center.dx - 0.08 * s, center.dy)
          ..quadraticBezierTo(
              center.dx, center.dy + 0.05 * s, center.dx + 0.08 * s, center.dy);
        canvas.drawPath(path, stroke);
      case MascotMood.worried:
        final path = Path()
          ..moveTo(center.dx - 0.07 * s, center.dy + 0.03 * s)
          ..quadraticBezierTo(center.dx, center.dy - 0.03 * s,
              center.dx + 0.07 * s, center.dy + 0.03 * s);
        canvas.drawPath(path, stroke);
      case MascotMood.confused:
        // Small off-centre "hmm" oval.
        canvas.drawOval(
          Rect.fromCenter(
              center: center + Offset(-0.03 * s, 0),
              width: 0.07 * s,
              height: 0.05 * s),
          fill,
        );
      case MascotMood.scanning:
        // Focused little smirk.
        final path = Path()
          ..moveTo(center.dx - 0.06 * s, center.dy + 0.01 * s)
          ..quadraticBezierTo(center.dx + 0.02 * s, center.dy + 0.04 * s,
              center.dx + 0.08 * s, center.dy - 0.01 * s);
        canvas.drawPath(path, stroke);
    }
  }

  void _drawQuestionMark(Canvas canvas, double s) {
    final tp = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: VaultieColors.primary,
          fontSize: 0.22 * s,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(0.72 * s, 0.06 * s));
  }

  @override
  bool shouldRepaint(covariant _MascotPainter old) =>
      old.mood != mood ||
      old.eyeOpen != eyeOpen ||
      old.scanPhase != scanPhase ||
      old.lift != lift;
}
