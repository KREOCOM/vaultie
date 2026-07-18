import 'package:flutter/material.dart';

/// Onboarding preview — swipeable full-bleed 3D hero images (from ChatGPT) with
/// the copy rendered in Flutter on top (dark text on the light lower area, so it
/// stays crisp + localizable). Each hero floats gently for a "living 3D" feel.
///
/// The heroes are ~853×1844 — near-identical to a phone's aspect ratio — which
/// is what lets BoxFit.cover fill the screen edge to edge with almost no crop.
/// Any replacement art must keep that shape, or it will letterbox.
///
/// TEMP launch screen for previewing the design on device; the last page's
/// button continues into the app's normal flow.
class OnbPreview extends StatefulWidget {
  const OnbPreview({super.key, required this.next});
  final Widget next;

  @override
  State<OnbPreview> createState() => _OnbPreviewState();
}

class _OnbData {
  const _OnbData({
    required this.image,
    required this.head,
    required this.accent,
    required this.sub,
    this.align = -0.16,
    this.features = false,
  });
  final String image, head, accent, sub;
  final double align;
  final bool features;
}

class _OnbPreviewState extends State<OnbPreview> with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF14203A);
  static const _muted = Color(0xFF5C6A85);
  static const _accent = Color(0xFF2F6BFF);
  static const _accentHi = Color(0xFF4F82FF);

  static const _pages = [
    _OnbData(
      image: 'assets/onboarding/vault.png',
      head: 'Welcome to ',
      accent: 'Vaultie',
      sub: 'All your money, in one place.\nSafe, smart, simple.',
      align: -0.18,
      features: true,
    ),
    _OnbData(
      image: 'assets/onboarding/p2.png',
      head: 'See the big ',
      accent: 'picture',
      sub: 'Your balance, income and spending —\nalways live, in one view.',
      align: -0.14,
    ),
    _OnbData(
      image: 'assets/onboarding/p3.png',
      head: 'Your smart ',
      accent: 'assistant',
      sub: 'Vaultie sorts your spending, finds subscriptions\nand answers your money questions.',
      align: -0.14,
    ),
    _OnbData(
      image: 'assets/onboarding/p4.png',
      head: 'Watch your money ',
      accent: 'grow',
      sub: "See every month side by side — what's working,\nand what quietly isn't.",
      align: -0.14,
    ),
    _OnbData(
      image: 'assets/onboarding/p5.png',
      head: 'Connect ',
      accent: 'any bank',
      sub: '2,500+ banks across Europe — including\nevery major Lithuanian one.',
      align: -0.14,
    ),
  ];

  final _pc = PageController();
  int _i = 0;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    _pc.dispose();
    super.dispose();
  }

  void _advance() {
    if (_i < _pages.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
    } else {
      _start();
    }
  }

  void _start() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _pages.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFFEAF2FF),
      body: Stack(
        children: [
          // swipeable heroes + copy
          PageView.builder(
            controller: _pc,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => _page(_pages[i]),
          ),

          // fixed bottom control: dots + button (over the page's scrim)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _advance,
                      child: Container(
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(colors: [_accent, _accentHi]),
                          boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 10))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(last ? "Let's Start" : 'Next',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var p = 0; p < _pages.length; p++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: p == _i ? 22 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: p == _i ? _accent : const Color(0xFFB9C6DE),
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(_OnbData d) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // floating hero
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = Curves.easeInOut.transform(_c.value);
            return Transform.translate(
              offset: Offset(0, -8 + t * 16),
              child: Transform.scale(scale: 1.02 + t * 0.02, child: child),
            );
          },
          child: Image.asset(d.image, fit: BoxFit.cover, alignment: Alignment(0, d.align)),
        ),

        // pulsing podium glow
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.of(context).size.height * 0.44,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = Curves.easeInOut.transform(_c.value);
                return Center(
                  child: Container(
                    width: 230,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [_accent.withValues(alpha: 0.28 + t * 0.2), _accent.withValues(alpha: 0.0)]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // bottom copy (dark on the light lower area)
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00EAF2FF), Color(0xD6EFF5FF), Color(0xFFF1F6FF)],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: _ink),
                      children: [
                        TextSpan(text: d.head),
                        TextSpan(text: d.accent, style: const TextStyle(color: _accent)),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(d.sub, textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w500, color: _muted)),
                  if (d.features) ...[
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                      child: Row(children: [
                        _feature(Icons.verified_user_rounded, 'Bank-level\nsecurity'),
                        _divider(),
                        _feature(Icons.pie_chart_rounded, 'Smart\ninsights'),
                        _divider(),
                        _feature(Icons.bolt_rounded, 'Everything\nsimple'),
                      ]),
                    ),
                  ],
                  // leave room for the fixed control (button + dots)
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _feature(IconData ic, String label) => Expanded(
        child: Column(children: [
          Icon(ic, color: _accent, size: 26),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink, height: 1.25)),
        ]),
      );

  Widget _divider() => Container(width: 1, height: 40, color: const Color(0xFFD6E0F0));
}
