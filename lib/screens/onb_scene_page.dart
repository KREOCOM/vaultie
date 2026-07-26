import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../i18n.dart';
import 'preview/showcase.dart';
import 'splash_screen.dart';

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
    this.glassCentreY = 0.36,
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

  /// Where the phone's screen should sit, as a fraction of the PAGE height —
  /// the centre of the glass lands here. Each render puts its phone at a
  /// different height, which showed as the handset jumping up and down as you
  /// tapped through; every page asking for the same value pins it. It is solved
  /// at layout time rather than baked in as a per-page crop, so it holds on any
  /// screen width instead of only the one it was tuned on.
  final double glassCentreY;

  double get glassW => glassR - glassL + 1;
  double get glassH => glassB - glassT + 1;

  /// The virtual screen the dashboard lays out at, sized to this glass's aspect
  /// so the FittedBox scales it uniformly — no crop, no stretch.
  ///
  /// 320, not a real handset's 390. The glass is only ~37% of the page width,
  /// so 390pt of UI was being squeezed into ~160pt — a scale of 0.41, which
  /// turns the app's 15pt body text into 6pt, and into 5pt on a narrow phone.
  /// Laying out narrower means the squeeze is gentler and everything inside the
  /// phone comes out ~22% larger; 320 is a real width (iPhone SE), so the app's
  /// own layouts already have to survive it.
  double get vw => 320;
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
    this.bullets = const [],
    required this.dotIndex,
    this.dotCount = 4,
    required this.kind,
    this.instant = false,
    this.warmNext,
    this.blankUntilLive,
  });

  final Widget next;
  final String sceneAsset, stampAsset;
  final SceneGeometry geometry;
  final IconData badgeIcon;
  final String badge, headline, sub;

  /// Short checkable lines under the copy. The reference onboarding this text
  /// came from could give each page two paragraphs and three bullets; here the
  /// phone takes two thirds of the page, so the paragraphs compress into [sub]
  /// and only the bullets — the concrete, checkable part — survive as a list.
  final List<String> bullets;
  final int dotIndex, dotCount;
  final ShowcaseKind kind;

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

  /// Measured height of the copy block. The phone is then centred in whatever
  /// is left above it, so a page with three bullets and a page with none both
  /// place it clear of the text. Picking a fraction by hand worked until the
  /// copy grew — then the badge sat on the handset.
  final GlobalKey _copyKey = GlobalKey();
  double? _copyH;

  void _measureCopy() {
    final box = _copyKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    if (_copyH != null && (_copyH! - h).abs() < 0.5) return;
    if (mounted) setState(() => _copyH = h);
  }

  static const Color _deep = Color(0xFF030E30);

  @override
  void initState() {
    super.initState();
    if (widget.instant) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureCopy();
      _armAutoAdvance();
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

  void _armAutoAdvance() {
    final d = kOnbAutoAdvance;
    if (d == null) return;
    Future<void>.delayed(d, () {
      if (mounted) _next();
    });
  }

  @override
  void didUpdateWidget(covariant OnbScenePage old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureCopy());
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
    final imgH = w * g.imgH / g.imgW; // scene at full width
    // Slide the artwork so every page's phone sits at the same height. A
    // positive shift crops sky off the top; a negative one lets the page colour
    // show above it, which these dark-skied renders hide anyway. Clamped so it
    // can never eat into the glass itself.
    final glassCentre = (g.glassT + g.glassB) / 2 / g.imgH * imgH;
    // Centre of the room left above the copy — falling back to the configured
    // fraction until the copy has been measured (one frame).
    final target = _copyH == null
        ? g.glassCentreY * size.height
        : (size.height - _copyH!) / 2;
    final shift = (glassCentre - target)
        .clamp(-0.12 * size.height, g.glassT / g.imgH * imgH - 8);

    // The scene is wider than the screen is tall, so it cannot fill the page
    // without cutting the icon columns off at the edges. Rather than crop the
    // sides, the artwork fades into the page colour before its bottom edge —
    // the edge itself is never visible, and the copy sits on the fade.
    // Where the artwork must be fully covered: just above the copy, or at the
    // scene's own fade point if the copy has not been measured yet. Tying it to
    // the copy is what keeps the text off the picture without a box around it.
    final copyTop = _copyH == null
        ? imgH - shift - 8
        : math.min(imgH - shift - 8, size.height - _copyH! - 18);
    final s0 = (math.min(imgH * g.ringB / g.imgH - shift, copyTop - 120) /
            size.height)
        .clamp(0.0, 0.94);
    final s1 = (copyTop / size.height).clamp(s0 + 0.03, 1.0);

    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        children: [
          Positioned(
            top: -shift,
            left: 0,
            width: w,
            height: imgH,
            child: Image.asset(widget.sceneAsset, fit: BoxFit.cover),
          ),
          Positioned(
            left: g.glassL / g.imgW * w,
            top: g.glassT / g.imgH * imgH - shift,
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
                key: _copyKey,
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left-aligned, with a short accent rule instead of a box.
                    // The translucent block guaranteed contrast but read as a
                    // patch stuck over the artwork; the scrim below is tied to
                    // this block's measured height instead, so the words are
                    // always on a settled background without a frame.
                    Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      tr(widget.headline),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.9,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(widget.sub),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: 0.86),
                        shadows: const [
                          Shadow(color: Color(0x9900081F), blurRadius: 12)
                        ],
                      ),
                    ),
                    if (widget.bullets.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      for (final b in widget.bullets)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(Icons.check_rounded,
                                    size: 14, color: Color(0xFF8FB4FF)),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  tr(b),
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.3,
                                    color:
                                        Colors.white.withValues(alpha: 0.80),
                                    shadows: const [
                                      Shadow(
                                          color: Color(0x9900081F),
                                          blurRadius: 10)
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
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
                    SizedBox(width: double.infinity, child: _dots()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The phone's screen. This shows [PhoneShowcase] rather than the app's real
  /// dashboard: at this size the real screens had to be squeezed to ~0.4, which
  /// left their text at 6pt, and scaling the UI up to compensate made the app
  /// look like it has huge type. The showcase presents the same features and
  /// the same figures, laid out to be read small.
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
              // No scaling here any more. It existed to rescue the real app's
              // 15pt text from being squeezed to 6pt; the showcase is drawn at
              // presentation sizes to begin with, so scaling on top would only
              // risk overflowing rows it was designed to fit.
              textScaler: const TextScaler.linear(1),
            ),
            child: IgnorePointer(child: PhoneShowcase(kind: widget.kind)),
          ),
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
