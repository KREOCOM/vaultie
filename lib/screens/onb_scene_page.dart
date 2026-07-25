import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../i18n.dart';
import 'preview/dashboard_preview.dart';

/// Where the phone's screen sits inside a scene render, in the asset's own
/// pixels. Every value here is measured off the artwork rather than estimated —
/// eyeballing the first of these was out by 45px, which showed as the dashboard
/// spilling onto the black bezel.
class SceneGeometry {
  const SceneGeometry({
    required this.imgW,
    required this.imgH,
    required this.glassL,
    required this.glassT,
    required this.glassR,
    required this.glassB,
    required this.corner,
    required this.stampH,
    required this.statusH,
    required this.ringB,
  });

  final double imgW, imgH;

  /// Glass edges (inclusive pixel coordinates in the asset).
  final double glassL, glassT, glassR, glassB;

  /// Corner radius of the glass, fitted as a circle against the render.
  final double corner;

  /// How far down the ink stamp reaches. It must clear the status-bar glyphs
  /// AND the whole corner curve — then the render's own bezel is what shapes
  /// the corners, so a pixel of radius error cannot show — while stopping short
  /// of the header baked into the artwork.
  final double stampH;

  /// Status-bar inset, so the live header lands on the artwork's own header.
  final double statusH;

  /// Bottom of the phone's glow: where the scene starts fading into the page.
  final double ringB;

  double get glassW => glassR - glassL + 1;
  double get glassH => glassB - glassT + 1;

  /// The virtual screen the dashboard lays out at, sized to this glass's aspect
  /// so the FittedBox scales it uniformly — no crop, no stretch.
  double get vw => 390;
  double get vh => vw * glassH / glassW;
  double get vTop => vw * statusH / glassW;
}

/// An onboarding page built on a scene render: the artwork at full width, the
/// live [DashboardPreview] laid over the phone's glass, the render's own status
/// bar stamped back on top, and the copy on a fade at the bottom.
///
/// The overlay covers the whole glass, status bar included, because the
/// dashboard's backdrop gradient is darkest at its very top: stopping below the
/// render's status bar left a hard step that read as a pasted rectangle. The
/// glyphs come back from [stampAsset] — a black ink stamp cut out of the same
/// render (alpha = how much darker each pixel is than the band around it, i.e.
/// a multiply blend baked into a PNG) — so there is no boundary to see and the
/// time / 4G / battery still come from the artwork.
class OnbScenePage extends StatefulWidget {
  const OnbScenePage({
    super.key,
    required this.next,
    required this.sceneAsset,
    required this.stampAsset,
    required this.geometry,
    required this.badgeIcon,
    required this.badge,
    required this.headline,
    required this.sub,
    required this.dotIndex,
    this.dotCount = 4,
    this.script = DemoScript.home,
    this.instant = false,
    this.warmNext,
    this.blankUntilLive,
  });

  final Widget next;
  final String sceneAsset, stampAsset;
  final SceneGeometry geometry;
  final IconData badgeIcon;
  final String badge, headline, sub;
  final int dotIndex, dotCount;
  final DemoScript script;

  /// Mount the live screen on the first frame instead of waiting for the entry
  /// transition. Holding it back avoids a stutter, but it costs a visible swap
  /// from the artwork's rendered screen to the real one — which reads as the
  /// page showing you a picture first and only then the app. Set this where
  /// that swap would be more noticeable than the stutter.
  final bool instant;

  /// Scene asset of the page after this one, decoded ahead of time.
  final String? warmNext;

  /// Fill the glass with this colour until the live screen mounts, hiding the
  /// artwork's own rendered screen. Use it where the artwork shows a DIFFERENT
  /// screen than the demo does — swapping between two different screens is very
  /// visible, while a blank one for a few hundred ms just reads as waking up.
  final Color? blankUntilLive;

  @override
  State<OnbScenePage> createState() => _OnbScenePageState();
}

class _OnbScenePageState extends State<OnbScenePage> {
  /// The live dashboard is held back until the entry transition has finished.
  /// Building it costs more than a frame's budget, and doing that during the
  /// fade is what made one step of the chain stutter while the rest were fine.
  /// Until it mounts, the artwork's own rendered screen stands in — the phone is
  /// never empty — and the swap is cross-faded so it reads as the screen waking.
  late bool _live = widget.instant;

  static const Color _deep = Color(0xFF030E30);

  @override
  void initState() {
    super.initState();
    if (widget.instant) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anim = ModalRoute.of(context)?.animation;
      if (anim == null || anim.isCompleted) {
        _goLive();
        return;
      }
      void onStatus(AnimationStatus s) {
        if (s == AnimationStatus.completed) {
          anim.removeStatusListener(onStatus);
          _goLive();
        }
      }

      anim.addStatusListener(onStatus);
    });
  }

  void _goLive() {
    if (mounted) setState(() => _live = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the next scene while this page is just looping its demo, so the
    // next page's entry transition isn't what has to pay for it.
    final nextScene = widget.warmNext;
    if (nextScene != null) precacheImage(AssetImage(nextScene), context);
  }

  void _next() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.geometry;
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final imgH = w * g.imgH / g.imgW; // scene at full width, top-aligned

    // The scene is wider than the screen is tall, so it cannot fill the page
    // without cutting the icon columns off at the edges. Rather than crop it,
    // the artwork fades into the page colour before its bottom edge — the edge
    // itself is never visible, and the copy sits on the fade.
    final s0 = (imgH * g.ringB / g.imgH / size.height).clamp(0.0, 0.94);
    final s1 = ((imgH - 8) / size.height).clamp(s0 + 0.03, 1.0);

    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            width: w,
            height: imgH,
            child: Image.asset(widget.sceneAsset, fit: BoxFit.cover),
          ),
          Positioned(
            left: g.glassL / g.imgW * w,
            top: g.glassT / g.imgH * imgH,
            width: g.glassW / g.imgW * w,
            height: g.glassH / g.imgH * imgH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(g.corner / g.imgW * w),
              child: Stack(
                children: [
                  if (widget.blankUntilLive != null && !_live)
                    Positioned.fill(
                        child: ColoredBox(color: widget.blankUntilLive!)),
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _live ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: _live
                          ? _phoneScreen(g)
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: g.stampH / g.imgH * imgH,
                    child: Image.asset(
                      widget.stampAsset,
                      fit: BoxFit.fill,
                      // In dark mode the dashboard's top is nearly black, so the
                      // ink is flipped to white or the glyphs would vanish.
                      color: AppPrefs.darkMode.value ? Colors.white : null,
                      colorBlendMode:
                          AppPrefs.darkMode.value ? BlendMode.srcIn : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: const [
                      Color(0x00030E30),
                      Color(0x00030E30),
                      Color(0xCC030E30),
                      _deep,
                    ],
                    stops: [0, s0, s0 + (s1 - s0) * 0.62, s1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _badge(),
                    const SizedBox(height: 14),
                    Text(
                      tr(widget.headline),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -1.0,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Color(0xB300081F), blurRadius: 18)
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      tr(widget.sub),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.86),
                        shadows: const [
                          Shadow(color: Color(0x9900081F), blurRadius: 12)
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    GestureDetector(
                      onTap: _next,
                      child: Container(
                        height: 54,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: const Color(0xFF001450)
                                    .withValues(alpha: 0.45),
                                blurRadius: 22,
                                offset: const Offset(0, 10)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(tr('Toliau'),
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1846E6))),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dots(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The phone's screen: the live demo inside its own navigator, so any screen
  /// the walkthrough opens is confined to the handset in the artwork. Against
  /// the app's navigator it would push full-screen over the whole onboarding.
  Widget _phoneScreen(SceneGeometry g) => FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: g.vw,
          height: g.vh,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(g.vw, g.vh),
              devicePixelRatio: 3,
              padding: EdgeInsets.only(top: g.vTop),
              textScaler: const TextScaler.linear(1),
            ),
            child: IgnorePointer(
              child: Navigator(
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  transitionDuration: Duration.zero,
                  pageBuilder: (_, __, ___) =>
                      DashboardPreview(demo: true, script: widget.script),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _badge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF2F6BFF).withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.badgeIcon, size: 13, color: const Color(0xFFDBE6FF)),
            const SizedBox(width: 7),
            Text(
              tr(widget.badge),
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: Color(0xFFDBE6FF)),
            ),
          ],
        ),
      );

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.dotCount; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == widget.dotIndex ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white
                    .withValues(alpha: i == widget.dotIndex ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
