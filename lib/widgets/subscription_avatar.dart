import 'package:flutter/material.dart';

import '../expense_categories.dart';
import '../services/logo_service.dart';

/// A rounded-square avatar for an expense.
///
/// Resolution order:
///   1. A brand logo (Google favicon) — when [logoDomain] is set, or the name
///      maps to a known brand and the expense is in a brand category.
///   2. The category icon on a tinted tile — for generic bills (rent, insurance).
///   3. The first letters of the name — when no [category] is provided (e.g. a
///      person's avatar) and no logo resolves.
class SubscriptionAvatar extends StatelessWidget {
  const SubscriptionAvatar({
    super.key,
    required this.name,
    this.category,
    this.logoDomain,
    this.size = 48,
  });

  final String name;

  /// Stored category key of the expense (new taxonomy or legacy). Null for
  /// non-expense avatars (e.g. the Settings profile), which keep the old
  /// initials behaviour.
  final String? category;

  /// Explicit brand domain to fetch a logo for, if any.
  final String? logoDomain;

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

  /// Whether this avatar may resolve a logo from the NAME (vs. only an explicit
  /// domain). Generic bills (rent, insurance) shouldn't guess a brand.
  bool get _mayGuessFromName =>
      category == null || normalizeCategoryKey(category!) == 'entertainment';

  /// A bundled logo asset for this avatar, or null.
  String? get _logoAsset {
    if (!_mayGuessFromName) return null;
    return logoAssetForName(name);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.29);
    // Bundled asset only — resolves on-device, so an avatar never discloses the
    // merchant to any third party. No bundled logo → category icon / initials,
    // never a network fetch.
    final asset = _logoAsset;
    if (asset == null) {
      return category != null ? _categoryIcon(radius) : _initials(radius);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => _fallback(radius),
        frameBuilder: (context, child, frame, sync) => ClipRRect(
          borderRadius: radius,
          child: ColoredBox(
            color: Colors.white,
            child: Padding(padding: EdgeInsets.all(size * 0.16), child: child),
          ),
        ),
      ),
    );
  }

  Widget _fallback(BorderRadius radius) =>
      category != null ? _categoryIcon(radius) : _initials(radius);

  /// A tinted tile with the category's icon — the default for generic expenses.
  Widget _categoryIcon(BorderRadius radius) {
    final cat = categoryFor(category!);
    return DecoratedBox(
      decoration: BoxDecoration(color: cat.color, borderRadius: radius),
      child: Center(
        child: Icon(cat.icon, color: Colors.white, size: size * 0.52),
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
