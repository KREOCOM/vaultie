import 'package:flutter/material.dart';

/// A rounded-square avatar showing the first two letters of a subscription
/// name in white on a colour derived deterministically from the name — so the
/// same name always gets the same colour, and different names are easy to tell
/// apart at a glance.
class SubscriptionAvatar extends StatelessWidget {
  const SubscriptionAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  /// Stable pleasant colour from the name's hash (fixed saturation/lightness so
  /// white text stays readable on every result).
  static Color colorFor(String name) {
    final hue = (name.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.45, 0.42).toColor();
  }

  static String initialsFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFor(name),
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      alignment: Alignment.center,
      child: Text(
        initialsFor(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
