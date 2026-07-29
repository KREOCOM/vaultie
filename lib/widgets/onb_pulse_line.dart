import 'package:flutter/material.dart';

/// The accent rule above the onboarding headline, drawn as a live chart line.
///
/// It replaces a static 3pt bar. The line swings hard up and down the way the
/// dashboard's own chart does, draws itself from the left, and stops at three
/// peaks where a euro figure appears. Then it clears and starts again.
///
/// NOTHING is drawn ahead of the pen. A faint "route" under the live line was
/// the first version and it gave the trick away — the whole shape was visible
/// from frame one, so the drawing read as a reveal of something already there
/// rather than as a line being made. What has not been drawn yet does not exist.
///
/// Used on page 1 ONLY. Seven pages each running a six-second loop would be
/// noise, and a reader who moves faster than the loop never sees it finish.
class OnbPulseLine extends StatefulWidget {
  const OnbPulseLine({
    super.key,
    this.height = 42,
    this.color = const Color(0xFF7FA9FF),
    this.labels = const ['86 €', '214 €', '137 €'],
    this.period = const Duration(seconds: 6),
  });

  final double height;
  final Color color;

  /// One per marked peak, in order along the line.
  final List<String> labels;
  final Duration period;

  @override
  State<OnbPulseLine> createState() => _OnbPulseLineState();
}

class _OnbPulseLineState extends State<OnbPulseLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _PulsePainter(
                t: _c.value,
                color: widget.color,
                labels: widget.labels,
                dir: Directionality.of(context),
              ),
            ),
          ),
        ),
      );
}

/// Normalised chart shape: x left→right, y 0 = top of the line band.
///
/// Deliberately uneven and deliberately steep — it swings nearly the full height
/// of the band. A shallow, regular wave reads as decoration; this reads as days
/// of real spending.
const _pts = <Offset>[
  Offset(0.00, 0.70),
  Offset(0.05, 0.44),
  Offset(0.10, 0.86),
  Offset(0.16, 0.30),
  Offset(0.22, 0.08), // peak · label 0
  Offset(0.28, 0.62),
  Offset(0.33, 0.90),
  Offset(0.39, 0.36),
  Offset(0.45, 0.74),
  Offset(0.51, 0.20),
  Offset(0.57, 0.52),
  Offset(0.62, 0.06), // peak · label 1
  Offset(0.68, 0.58),
  Offset(0.74, 0.92),
  Offset(0.80, 0.34),
  Offset(0.86, 0.12), // peak · label 2
  Offset(0.92, 0.64),
  Offset(1.00, 0.40),
];

/// Indices in [_pts] that get a dot and a figure.
const _marks = <int>[4, 11, 15];

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.t,
    required this.color,
    required this.labels,
    required this.dir,
  });

  final double t;
  final Color color;
  final List<String> labels;
  final TextDirection dir;

  // The loop: draw, hold, clear. Holding matters — a line that restarts the
  // instant it finishes never lets the last figure be read.
  static const _drawTo = 0.66;
  static const _holdTo = 0.90;

  @override
  void paint(Canvas canvas, Size size) {
    // Figures sit above their peak, so the line lives in the lower band.
    const labelBand = 16.0;
    final bandH = size.height - labelBand;
    if (bandH <= 0 || size.width <= 0) return;

    Offset at(Offset p) => Offset(p.dx * size.width, labelBand + p.dy * bandH);

    final path = Path()..moveTo(at(_pts.first).dx, at(_pts.first).dy);
    for (final p in _pts.skip(1)) {
      final o = at(p);
      path.lineTo(o.dx, o.dy);
    }

    // How far the pen has travelled, with a hold at full length and a fade out.
    final double drawnFrac;
    if (t <= _drawTo) {
      drawnFrac = Curves.easeInOut.transform(t / _drawTo);
    } else {
      drawnFrac = 1;
    }
    final fade = t <= _holdTo ? 1.0 : 1 - (t - _holdTo) / (1 - _holdTo);
    if (fade <= 0) return;

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final total = metrics.fold<double>(0, (s, m) => s + m.length);

    final drawn = Path();
    var remaining = drawnFrac * total;
    for (final m in metrics) {
      if (remaining <= 0) break;
      final take = remaining.clamp(0.0, m.length);
      drawn.addPath(m.extractPath(0, take), Offset.zero);
      remaining -= take;
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: fade),
    );

    // Cumulative distance to each point, so a figure appears exactly when the
    // pen reaches its peak rather than on a guessed timer.
    final reached = <int, double>{};
    var acc = 0.0;
    for (var i = 1; i < _pts.length; i++) {
      acc += (at(_pts[i]) - at(_pts[i - 1])).distance;
      reached[i] = acc / total;
    }

    for (var k = 0; k < _marks.length && k < labels.length; k++) {
      final idx = _marks[k];
      final need = reached[idx] ?? 1.0;
      if (drawnFrac < need) continue;
      final a = fade * ((drawnFrac - need) / 0.05).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final o = at(_pts[idx]);

      canvas.drawCircle(o, 4, Paint()..color = color.withValues(alpha: a * 0.30));
      canvas.drawCircle(
          o, 2.2, Paint()..color = const Color(0xFFEAF1FF).withValues(alpha: a));

      final tp = TextPainter(
        text: TextSpan(
          text: labels[k],
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            height: 1,
            letterSpacing: -0.2,
            color: const Color(0xFFDCE8FF).withValues(alpha: a),
          ),
        ),
        textDirection: dir,
      )..layout();
      // Kept inside the band: a figure on the last peak would otherwise run off
      // the right edge.
      final dx = (o.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, o.dy - tp.height - 7));
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}
