import 'package:flutter/material.dart';

import '../services/logo_service.dart';

/// A rounded-square avatar for a subscription.
///
/// When the name maps to a known brand it shows the auto-fetched logo (Clearbit)
/// on a white tile; otherwise — or while loading / on network error — it falls
/// back to the first two letters of the name in white on a colour derived
/// deterministically from the name (same name → same colour).
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
    final radius = BorderRadius.circular(size * 0.29);
    final url = logoUrlForName(name);
    if (url == null) return _initials(radius);

    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        // Loaded → logo on a white rounded tile; still loading → initials.
        loadingBuilder: (context, child, progress) => progress == null
            ? ClipRRect(
                borderRadius: radius,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.16),
                    child: child,
                  ),
                ),
              )
            : _initials(radius),
        errorBuilder: (context, error, stack) => _initials(radius),
      ),
    );
  }

  Widget _initials(BorderRadius radius) {
    return DecoratedBox(
      decoration: BoxDecoration(color: colorFor(name), borderRadius: radius),
      child: Center(
        child: Text(
          initialsFor(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.34,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
