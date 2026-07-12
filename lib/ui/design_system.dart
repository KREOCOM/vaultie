import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Vaultie design system — centralized tokens + primitive components.
///
/// Nothing in the refined screens sets raw TextStyle / Color / EdgeInsets /
/// BoxShadow inline. Everything routes through these tokens and widgets so the
/// look is systematic and optically consistent (not ad-hoc "default Flutter").
class DS {
  DS._();

  // ── Colour: neutral ground with a whisper of green; pure-white cards ───────
  static const bg = Color(0xFFF1F3F0); // app background (slightly < card)
  static const card = Color(0xFFFFFFFF); // pure white surfaces
  static const cardAlt = Color(0xFFF5F7F4); // recessed / highlighted group
  static const hairline = Color(0xFFE8ECE7); // borders / dividers
  static const track = Color(0xFFE9ECE8); // chart/ring track

  // Ink ramp (green-black, softened from pure black)
  static const ink = Color(0xFF1A2620); // primary text
  static const ink2 = Color(0xFF6C7972); // secondary text
  static const ink3 = Color(0xFF9AA69E); // tertiary / captions

  // Brand + semantic
  static const brand = Color(0xFF174E35);
  static const accent = Color(0xFF1E8E4E);
  static const paid = Color(0xFF1E8E4E); // positive / settled
  static const pending = Color(0xFFB5831A); // awaiting / expected
  static const danger = Color(0xFFC0402B);

  // ── Spacing: 4-pt scale ────────────────────────────────────────────────────
  static const double s2 = 2, s4 = 4, s6 = 6, s8 = 8, s10 = 10, s12 = 12;
  static const double s14 = 14, s16 = 16, s20 = 20, s24 = 24, s28 = 28, s32 = 32;

  /// Screen horizontal margin — a single source of truth for optical alignment.
  static const double gutter = 20;

  // ── Radius scale (visual sizes; squircle multiplies internally) ────────────
  static const double rIcon = 12, rRow = 16, rCard = 20, rHero = 24, rPill = 100;

  // ── Elevation: neutral, two-layer, tuned soft ──────────────────────────────
  static const _sh = Color(0xFF13211A);
  static List<BoxShadow> get e1 => const [
        BoxShadow(color: Color(0x0A13211A), blurRadius: 3, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x0F13211A), blurRadius: 14, offset: Offset(0, 6)),
      ];
  static List<BoxShadow> get e2 => [
        BoxShadow(color: _sh.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
        BoxShadow(color: _sh.withValues(alpha: 0.07), blurRadius: 26, offset: const Offset(0, 12)),
      ];
}

/// iOS-style continuous (squircle) corner. Flutter's ContinuousRectangleBorder
/// runs "tighter" than BorderRadius.circular, so we scale the radius to match a
/// given visual corner size.
ShapeBorder squircle(double r, {BorderSide side = BorderSide.none}) =>
    ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(r * 1.6),
      side: side,
    );

/// Type scale. One place for size / weight / height / tracking. Money styles
/// carry tabular figures so digit columns line up.
class AppType {
  AppType._();

  static const _tab = [FontFeature.tabularFigures()];

  static const displayLg = TextStyle(
      color: DS.ink, fontSize: 27, fontWeight: FontWeight.w800, height: 1.05, letterSpacing: -0.5);
  static const display = TextStyle(
      color: DS.ink, fontSize: 22, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.4);

  static const moneyLg = TextStyle(
      color: DS.ink, fontSize: 22, fontWeight: FontWeight.w800, height: 1.0,
      letterSpacing: -0.4, fontFeatures: _tab);
  static const money = TextStyle(
      color: DS.ink, fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.0,
      letterSpacing: -0.1, fontFeatures: _tab);
  static const moneySm = TextStyle(
      color: DS.ink3, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.0,
      letterSpacing: 0, fontFeatures: _tab);

  static const rowTitle = TextStyle(
      color: DS.ink, fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.2);
  static const rowSub = TextStyle(
      color: DS.ink2, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.2);

  static const label = TextStyle(
      color: DS.ink2, fontSize: 13, fontWeight: FontWeight.w500, height: 1.2);
  static const overline = TextStyle(
      color: DS.ink3, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: 0.6);
}

/// Formats money the Lithuanian way — grouped integer, comma decimals, trailing
/// euro. Always 2 decimals, tabular-safe. Optional leading sign.
class Money {
  Money._();
  static String format(double v, {bool signed = false}) {
    final sign = signed ? (v < 0 ? '−' : '+') : (v < 0 ? '−' : '');
    final a = v.abs();
    final whole = a.truncate();
    final cents = ((a - whole) * 100).round().toString().padLeft(2, '0');
    final digits = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return '$sign$buf,$cents €';
  }
}

/// Money as text with tabular figures baked into the style.
class MoneyText extends StatelessWidget {
  const MoneyText(this.amount, {super.key, this.style = AppType.money, this.signed = false});
  final double amount;
  final TextStyle style;
  final bool signed;
  @override
  Widget build(BuildContext context) =>
      Text(Money.format(amount, signed: signed), style: style);
}

/// A flat category tile — solid colour, white glyph. Circle or squircle. No
/// gradient, no coloured shadow (those read as "toy / AI-generated").
class CategoryIcon extends StatelessWidget {
  const CategoryIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
    this.circle = true,
  });
  final IconData icon;
  final Color color;
  final double size;
  final bool circle;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: color,
        shape: circle ? const CircleBorder() : squircle(size * 0.32),
        clipBehavior: Clip.antiAlias,
        child: Center(child: Icon(icon, color: Colors.white, size: size * 0.52)),
      ),
    );
  }
}

/// A soft-tint filter/segment pill (calendar range, filter, etc.).
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF3EC),
      shape: squircle(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DS.s14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: DS.brand),
              const SizedBox(width: DS.s8),
              Text(label,
                  style: const TextStyle(
                      color: DS.brand, fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// White surface with squircle corners, a hairline edge, and a soft neutral
/// shadow. One card primitive for the whole app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = DS.rCard,
    this.color = DS.card,
    this.shadow,
    this.border = DS.hairline,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final List<BoxShadow>? shadow;
  final Color? border;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ?? DS.e1,
      ),
      child: Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: squircle(radius,
            side: border == null ? BorderSide.none : BorderSide(color: border!, width: 1)),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A hairline divider indented to clear the leading icon column.
class RowDivider extends StatelessWidget {
  const RowDivider({super.key, this.indent = 0});
  final double indent;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: const Divider(height: 1, thickness: 1, color: DS.hairline),
      );
}
