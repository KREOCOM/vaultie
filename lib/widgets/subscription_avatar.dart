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

  /// The logo URL to show, or null to fall back to the category icon / initials.
  String? get _logoUrl {
    final domain = logoDomain?.trim();
    if (domain != null && domain.isNotEmpty) return logoUrlForDomain(domain);
    // No explicit domain: only guess a brand logo from the name when this is a
    // brand-style expense (or a category-less avatar, preserving old behaviour).
    if (category == null ||
        normalizeCategoryKey(category!) == 'entertainment') {
      return logoUrlForName(name);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.29);
    final url = _logoUrl;
    if (url == null) {
      return category != null ? _categoryIcon(radius) : _initials(radius);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        // Loaded → logo on a white rounded tile; still loading → fallback.
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
            : _fallback(radius),
        errorBuilder: (context, error, stack) => _fallback(radius),
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
