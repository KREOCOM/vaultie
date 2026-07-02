import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A recognisable subscription service with its real brand colour and a
/// hand-drawn logo (no image assets, no trademark files shipped).
enum Brand {
  netflix,
  spotify,
  youtube,
  primeVideo,
  appleMusic,
  appleTv,
  icloud,
  disneyPlus,
  other,
}

class BrandSpec {
  const BrandSpec({
    required this.brand,
    required this.label,
    required this.category,
    required this.background,
    required this.accent,
    this.circular = false,
  });

  final Brand brand;
  final String label;
  final String category;
  final Color background;
  final Color accent;
  final bool circular;
}

/// Catalogue used by the onboarding scene and the add-subscription picker.
const List<BrandSpec> kBrandCatalog = [
  BrandSpec(
    brand: Brand.netflix,
    label: 'Netflix',
    category: 'Streaming',
    background: Color(0xFF000000),
    accent: Color(0xFFE50914),
  ),
  BrandSpec(
    brand: Brand.spotify,
    label: 'Spotify',
    category: 'Music',
    background: Color(0xFF1DB954),
    accent: Colors.black,
    circular: true,
  ),
  BrandSpec(
    brand: Brand.youtube,
    label: 'YouTube',
    category: 'Streaming',
    background: Color(0xFFFF0000),
    accent: Colors.white,
  ),
  BrandSpec(
    brand: Brand.primeVideo,
    label: 'Prime Video',
    category: 'Streaming',
    background: Color(0xFF1399FF),
    accent: Colors.white,
  ),
  BrandSpec(
    brand: Brand.appleMusic,
    label: 'Apple Music',
    category: 'Music',
    background: Color(0xFFFA2D48),
    accent: Colors.white,
  ),
  BrandSpec(
    brand: Brand.appleTv,
    label: 'Apple TV',
    category: 'Streaming',
    background: Color(0xFF000000),
    accent: Colors.white,
  ),
  BrandSpec(
    brand: Brand.icloud,
    label: 'iCloud',
    category: 'Cloud',
    background: Color(0xFF3693F3),
    accent: Colors.white,
  ),
  BrandSpec(
    brand: Brand.disneyPlus,
    label: 'Disney+',
    category: 'Streaming',
    background: Color(0xFF13183C),
    accent: Color(0xFF3FC1F3),
  ),
  BrandSpec(
    brand: Brand.other,
    label: 'Other',
    category: 'Other',
    background: Color(0xFFE6F4EC),
    accent: Color(0xFF174E35),
  ),
];

BrandSpec brandSpec(Brand brand) =>
    kBrandCatalog.firstWhere((b) => b.brand == brand);

/// The eight services shown in the add-subscription picker grid (4×2 order).
const List<Brand> kPopularGrid = [
  Brand.netflix,
  Brand.spotify,
  Brand.youtube,
  Brand.primeVideo,
  Brand.appleTv,
  Brand.disneyPlus,
  Brand.icloud,
  Brand.other,
];

/// Rounded brand tile, e.g. a black square with a red italic Netflix "N".
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.brand, this.size = 56});

  final Brand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = brandSpec(brand);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: spec.background,
        gradient: brand == Brand.appleMusic
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFB5C74), Color(0xFFFA2D48)],
              )
            : null,
        shape: spec.circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: spec.circular ? null : BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: spec.background.withValues(alpha: 0.30),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: CustomPaint(painter: _BrandMarkPainter(spec)),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter(this.spec);
  final BrandSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final accent = Paint()..color = spec.accent;

    switch (spec.brand) {
      case Brand.netflix:
        _text(canvas, size, 'N',
            color: spec.accent,
            italic: true,
            weight: FontWeight.w900,
            scale: 0.62);
      case Brand.disneyPlus:
        _text(canvas, size, 'D+',
            color: spec.accent, weight: FontWeight.w800, scale: 0.42);
      case Brand.spotify:
        // Three nested sound waves.
        final p = Paint()
          ..color = spec.accent
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 3; i++) {
          final r = s * (0.16 + i * 0.10);
          p.strokeWidth = s * (0.075 - i * 0.012);
          canvas.drawArc(
            Rect.fromCenter(
                center: Offset(c.dx, c.dy - s * 0.04),
                width: r * 2,
                height: r * 2),
            math.pi * 0.18,
            math.pi * 0.64,
            false,
            p,
          );
        }
      case Brand.youtube:
        // White play triangle.
        final w = s * 0.22;
        final path = Path()
          ..moveTo(c.dx - w * 0.7, c.dy - w)
          ..lineTo(c.dx - w * 0.7, c.dy + w)
          ..lineTo(c.dx + w, c.dy)
          ..close();
        canvas.drawPath(path, accent);
      case Brand.primeVideo:
        // White "prime video" wordmark, wrapped to two lines.
        _text(canvas, size, 'prime\nvideo',
            color: spec.accent, weight: FontWeight.w700, scale: 0.2);
      case Brand.appleTv:
        _drawApple(canvas, size, spec.accent);
      case Brand.other:
        // Green "+" plus sign on the light tile.
        final plus = Paint()
          ..color = spec.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.09
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
            Offset(c.dx, c.dy - s * 0.18), Offset(c.dx, c.dy + s * 0.18), plus);
        canvas.drawLine(
            Offset(c.dx - s * 0.18, c.dy), Offset(c.dx + s * 0.18, c.dy), plus);
      case Brand.appleMusic:
        // Double music note.
        final stem = Paint()
          ..color = spec.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05;
        final x1 = c.dx - s * 0.10;
        final x2 = c.dx + s * 0.14;
        canvas.drawLine(
            Offset(x1, c.dy - s * 0.16), Offset(x1, c.dy + s * 0.12), stem);
        canvas.drawLine(
            Offset(x2, c.dy - s * 0.20), Offset(x2, c.dy + s * 0.08), stem);
        canvas.drawLine(Offset(x1, c.dy - s * 0.16),
            Offset(x2, c.dy - s * 0.20), stem..strokeWidth = s * 0.06);
        canvas.drawCircle(
            Offset(x1 - s * 0.03, c.dy + s * 0.12), s * 0.065, accent);
        canvas.drawCircle(
            Offset(x2 - s * 0.03, c.dy + s * 0.08), s * 0.065, accent);
      case Brand.icloud:
        // Fluffy cloud from overlapping circles + a base bar.
        canvas.drawCircle(
            Offset(c.dx - s * 0.13, c.dy + s * 0.02), s * 0.12, accent);
        canvas.drawCircle(
            Offset(c.dx + s * 0.04, c.dy - s * 0.06), s * 0.16, accent);
        canvas.drawCircle(
            Offset(c.dx + s * 0.18, c.dy + s * 0.03), s * 0.11, accent);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(c.dx - s * 0.22, c.dy + s * 0.02, s * 0.44, s * 0.14),
            Radius.circular(s * 0.07),
          ),
          accent,
        );
    }
  }

  void _text(
    Canvas canvas,
    Size size,
    String text, {
    required Color color,
    required double scale,
    FontWeight weight = FontWeight.bold,
    bool italic = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size.width * scale,
          fontWeight: weight,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          height: 1.05,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  /// A simple white Apple silhouette: a rounded body with a bite taken from the
  /// right and a small leaf on top.
  void _drawApple(Canvas canvas, Size size, Color color) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final body = Paint()..color = color;

    // Two overlapping lobes form the rounded body.
    final left = Path()
      ..addOval(Rect.fromCircle(
          center: c + Offset(-0.11 * s, 0.04 * s), radius: 0.19 * s));
    final right = Path()
      ..addOval(Rect.fromCircle(
          center: c + Offset(0.11 * s, 0.04 * s), radius: 0.19 * s));
    var apple = Path.combine(PathOperation.union, left, right);

    // Top dimple where the stem sits.
    final dimple = Path()
      ..addOval(
          Rect.fromCircle(center: c + Offset(0, -0.18 * s), radius: 0.08 * s));
    apple = Path.combine(PathOperation.difference, apple, dimple);

    // The signature bite on the right edge.
    final bite = Path()
      ..addOval(
          Rect.fromCircle(center: c + Offset(0.26 * s, 0.0), radius: 0.11 * s));
    apple = Path.combine(PathOperation.difference, apple, bite);

    canvas.drawPath(apple, body);

    // Leaf.
    canvas.save();
    canvas.translate(c.dx + 0.03 * s, c.dy - 0.24 * s);
    canvas.rotate(-math.pi / 5);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 0.16 * s, height: 0.09 * s),
      body,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) => old.spec != spec;
}
