import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../i18n.dart';
import 'preview/dashboard_preview.dart';

/// The phone's screen: the live dashboard demo inside its own navigator, so any
/// screen it opens is confined to the handset in the artwork.
class _DemoStage extends StatelessWidget {
  const _DemoStage();

  @override
  Widget build(BuildContext context) => Navigator(
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => const DashboardPreview(demo: true),
        ),
      );
}

/// Onboarding page 3 — "here's the app". The rendered scene (phone on the tile
/// platform, neon ring, floating logos) is shown at full width, never cropped,
/// and the LIVE [DashboardPreview] is laid over the phone's whole glass so the
/// screen is real Flutter — automatically in the user's language.
///
/// The overlay covers the glass edge to edge, status bar included, because the
/// dashboard's own backdrop gradient is darkest at the very top: stopping the
/// overlay below the scene's status bar left that dark band butting against the
/// render's white one, and the step read as a pasted rectangle. Instead the
/// scene's status-bar glyphs are re-applied on top from [_statusbar] — a black
/// ink stamp cut out of the same render — so there is no boundary to see and
/// the time / 4G / battery / island still come from the artwork.
class OnbMonth extends StatefulWidget {
  const OnbMonth({super.key, required this.next});

  final Widget next;

  @override
  State<OnbMonth> createState() => _OnbMonthState();
}

class _OnbMonthState extends State<OnbMonth> {
  /// The live dashboard is held back until this page's entry transition has
  /// finished. Building it costs more than a frame's budget, and doing that
  /// during the fade is what made this one step stutter. Until it mounts the
  /// artwork's own rendered screen stands in — the phone is never empty — and
  /// the swap is cross-faded so it reads as the screen waking up.
  bool _live = false;

  @override
  void initState() {
    super.initState();
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

  // Phone glass inside page3_scene.png (941×1672), measured off its pixels:
  // x 298→648, y 359→1195, corners a clean circle of r≈45 (fitted, mse 0.11).
  // This render is rectilinear — the left edge lands on 298 in every row — so
  // the rect needs no inward fudge, unlike the one before it.
  static const double _gx = 298 / 941; // glass left
  static const double _gy = 359 / 1672; // glass top
  static const double _gw = 351 / 941; // glass width
  static const double _gh = 837 / 1672; // glass height
  // The ink stamp runs past the status bar (its glyphs end 42px down) to 58px,
  // so it also covers the whole corner curve: the render's own bezel is then
  // what shapes the corners, and a pixel of radius error can't show. The baked
  // "Pradžia" header starts at 68px, so the stamp stops clear of it.
  static const double _sbh = 58 / 1672;
  static const double _rad = 45 / 941; // glass corner radius
  static const double _ring = 1250 / 1672; // just below the phone body

  // Virtual screen the dashboard lays out at, sized to the glass's own aspect
  // (921 / 385) so the FittedBox scales it uniformly — no crop, no stretch. The
  // scene's phone is a little more elongated than a real handset, so it simply
  // shows slightly more of the feed.
  static const double _vw = 390;
  static const double _vh = _vw * 837 / 351;
  // Status-bar inset, virtual px: 54 image px puts the live "Pradžia" header on
  // the same line as the one baked into the artwork (which starts 68px down).
  static const double _vTop = _vw * 54 / 351;

  static const Color _deep = Color(0xFF030E30);

  void _next(BuildContext context) {
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
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final imgH = w * 1672 / 941; // scene drawn full width, top-aligned

    // The scene is wider than the screen is tall, so it cannot fill the page
    // without cutting the icon columns off at the edges. Rather than crop it,
    // the artwork fades into the page colour before its bottom edge — so the
    // edge itself is never visible and the copy sits on the fade, as on the
    // pages before it.
    final s0 = (imgH * _ring / size.height).clamp(0.0, 0.94);
    final s1 = ((imgH - 8) / size.height).clamp(s0 + 0.03, 1.0);

    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        children: [
          // ── Full scene (never cropped) ──
          Positioned(
            top: 0,
            left: 0,
            width: w,
            height: imgH,
            child: Image.asset('assets/onboarding/page3_scene.png',
                fit: BoxFit.cover),
          ),

          // ── Live dashboard on the phone's glass, status bar re-stamped ──
          Positioned(
            left: _gx * w,
            top: _gy * imgH,
            width: _gw * w,
            height: _gh * imgH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_rad * w),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _live ? 1 : 0,
                      duration: const Duration(milliseconds: 260),
                      child: !_live
                          ? const SizedBox.shrink()
                          : const FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _vw,
                        height: _vh,
                        child: MediaQuery(
                          data: MediaQueryData(
                            size: Size(_vw, _vh),
                            devicePixelRatio: 3,
                            padding: EdgeInsets.only(top: _vTop),
                            textScaler: TextScaler.linear(1),
                          ),
                          // Its own Navigator: when the demo opens the
                          // subscriptions manager, the route has to land inside
                          // the phone's screen. Against the app's navigator it
                          // would push full-screen over the whole onboarding.
                          child: IgnorePointer(child: _DemoStage()),
                        ),
                      ),
                    ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _sbh * imgH,
                    child: _statusbar(),
                  ),
                ],
              ),
            ),
          ),

          // ── Artwork fades into the page colour, then the copy ──
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
                      tr('Visas tavo mėnuo\nviename ekrane'),
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
                      tr('Pajamos, išlaidos, prenumeratos ir sąskaitos — viskas susirūšiuoja savaime.'),
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
                      onTap: () => _next(context),
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

  /// The scene's own status-bar glyphs, cut out as black ink on transparency so
  /// they sit on whatever the live dashboard paints underneath. In dark mode the
  /// dashboard's top is nearly black, so the ink is flipped to white.
  Widget _statusbar() => Image.asset(
        'assets/onboarding/page3_statusbar.png',
        fit: BoxFit.fill,
        color: AppPrefs.darkMode.value ? Colors.white : null,
        colorBlendMode: AppPrefs.darkMode.value ? BlendMode.srcIn : null,
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
            const Icon(Icons.auto_graph_rounded,
                size: 13, color: Color(0xFFDBE6FF)),
            const SizedBox(width: 7),
            Text(
              tr('Atsinaujina automatiškai'),
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
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 2 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 2 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
