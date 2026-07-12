import 'package:flutter/material.dart';

/// Vaultie design system (Phase 1 onboarding + paywall).
///
/// Light canvas, green as ACCENT (not background). Cards are white with a soft
/// shadow; the hero/buttons use the brand green gradient. Everything on the
/// onboarding/paywall surface reads these tokens — no ad-hoc colours.
class VT {
  VT._();

  // ── Canvas & surfaces ─────────────────────────────────────────────────────
  static const canvas = Color(0xFFF4F6F3); // light app background
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFEAEEE9);
  static const progressTrack = Color(0xFFD9E1D8); // unfilled progress segments

  /// Soft green radial glow used across onboarding surfaces.
  static const canvasGradient = RadialGradient(
    center: Alignment(0, -0.25),
    radius: 1.15,
    colors: [Color(0xFFE7F2E8), Color(0xFFEDF0EA)],
    stops: [0.0, 1.0],
  );

  // ── Brand green ───────────────────────────────────────────────────────────
  static const brand = Color(0xFF174E35); // deep brand green
  static const brandGrad = Color(0xFF1E6A47); // gradient partner (hero/buttons)
  static const accent = Color(0xFF16A34A); // bright accent (checks, highlights)

  // ── Text ──────────────────────────────────────────────────────────────────
  static const ink = Color(0xFF14231C); // primary text
  static const subtle = Color(0xFF6E7B74); // secondary text
  static const onBrand = Color(0xFFFFFFFF);

  // ── Radii & shadow ────────────────────────────────────────────────────────
  static const rCard = 22.0;
  static const rPill = 26.0;

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandGrad, brand],
  );

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: brand.withValues(alpha: 0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: brand.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  // ── Text styles ───────────────────────────────────────────────────────────
  static const display = TextStyle(
    color: ink,
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.4,
  );
  static const title = TextStyle(
    color: ink,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
  );
  static const body = TextStyle(
    color: subtle,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );
}

/// Standard onboarding scaffold: light canvas, safe area, generous padding.
class VtScaffold extends StatelessWidget {
  const VtScaffold({
    super.key,
    required this.child,
    this.onBack,
    this.progress,
    this.segments,
    this.segmentsFilled = 0,
    this.showLogo = false,
    this.gradientBg = false,
    this.bottom,
  });

  final Widget child;
  final VoidCallback? onBack;

  /// Use the soft green radial glow (matches the landing screen) instead of the
  /// flat canvas colour.
  final bool gradientBg;

  /// Show the centered Vaultie logo below the progress row (survey screens).
  final bool showLogo;

  /// 0..1 continuous green progress bar under the top bar (null = none).
  final double? progress;

  /// Segmented progress bar (e.g. 4 segments, N filled). Takes priority over
  /// [progress] when set.
  final int? segments;
  final int segmentsFilled;

  /// Optional pinned bottom action area (e.g. the primary button).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final hasBar = progress != null || segments != null;
    return Scaffold(
      backgroundColor: gradientBg ? Colors.transparent : VT.canvas,
      body: Container(
        decoration: gradientBg
            ? const BoxDecoration(gradient: VT.canvasGradient)
            : null,
        child: SafeArea(
        child: Column(
          children: [
            if (onBack != null || hasBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                child: Row(
                  children: [
                    if (onBack != null)
                      _CircleBack(onTap: onBack!)
                    else
                      const SizedBox(width: 40),
                    if (segments != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: VtSegmentedProgress(
                            total: segments!, filled: segmentsFilled),
                      ),
                    ] else if (progress != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: VtProgressBar(value: progress!)),
                    ] else
                      const Spacer(),
                  ],
                ),
              ),
            if (showLogo)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset('assets/icon/app_icon.png',
                      width: 38, height: 38, fit: BoxFit.cover),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: child,
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: bottom!,
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _CircleBack extends StatelessWidget {
  const _CircleBack({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VT.card,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 16, color: VT.ink),
        ),
      ),
    );
  }
}

/// Segmented green progress bar.
class VtProgressBar extends StatelessWidget {
  const VtProgressBar({super.key, required this.value});
  final double value; // 0..1

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: VT.line,
          valueColor: const AlwaysStoppedAnimation(VT.accent),
        ),
      ),
    );
  }
}

/// Segmented progress bar — [total] pills, first [filled] painted brand green.
class VtSegmentedProgress extends StatelessWidget {
  const VtSegmentedProgress({super.key, required this.total, required this.filled});
  final int total;
  final int filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < filled ? VT.brand : VT.progressTrack,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Primary green pill button (full width by default).
class VtPrimaryButton extends StatelessWidget {
  const VtPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VT.rPill),
        gradient: onPressed == null ? null : VT.heroGradient,
        color: onPressed == null ? VT.line : null,
        boxShadow: onPressed == null ? null : VT.buttonShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(VT.rPill),
          onTap: onPressed,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 20,
                      color: onPressed == null ? VT.subtle : VT.onBrand),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: onPressed == null ? VT.subtle : VT.onBrand,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text-style secondary action ("Jau turiu paskyrą").
class VtTextButton extends StatelessWidget {
  const VtTextButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: VT.brand,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
