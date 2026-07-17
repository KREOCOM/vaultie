import 'package:flutter/material.dart';

/// Onboarding preview — a full-bleed 3D hero image (from ChatGPT) with the text,
/// features and button rendered on top in Flutter, so the copy stays crisp and
/// localizable. The image floats gently for a "living 3D" feel. Temporary launch
/// screen for previewing the design on device.
class OnbPreview extends StatefulWidget {
  const OnbPreview({super.key, required this.next});

  /// Where "Let's Start" goes (the app's normal launch flow).
  final Widget next;

  @override
  State<OnbPreview> createState() => _OnbPreviewState();
}

class _OnbPreviewState extends State<OnbPreview> with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF14203A);
  static const _muted = Color(0xFF5C6A85);
  static const _accent = Color(0xFF2F6BFF);
  static const _accentHi = Color(0xFF4F82FF);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
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
    return Scaffold(
      backgroundColor: const Color(0xFFEAF2FF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── floating 3D hero ──
          AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              final t = Curves.easeInOut.transform(_c.value); // 0..1
              return Transform.translate(
                offset: Offset(0, -8 + t * 16),
                child: Transform.scale(scale: 1.03 + t * 0.02, child: child),
              );
            },
            child: Image.asset(
              'assets/onboarding/welcome.png',
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.12),
            ),
          ),

          // ── bottom copy (dark text on the light water) ──
          Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, (1 - v) * 26), child: child),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00EAF2FF), Color(0xCCEFF5FF), Color(0xFFF1F6FF)],
                    stops: [0.0, 0.42, 1.0],
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
                          children: const [
                            TextSpan(text: 'Welcome to '),
                            TextSpan(text: 'Vaultie', style: TextStyle(color: _accent)),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'All your money, in one place.\nFinally in control.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15.5, height: 1.4, fontWeight: FontWeight.w500, color: _muted),
                      ),
                      const SizedBox(height: 22),
                      // feature row in a frosted card
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                        ),
                        child: Row(
                          children: [
                            _feature(Icons.verified_user_rounded, 'Bank-level\nsecurity'),
                            _divider(),
                            _feature(Icons.pie_chart_rounded, 'Smart insights\n& analytics'),
                            _divider(),
                            _feature(Icons.bolt_rounded, 'Everything\nyou need'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // button
                      GestureDetector(
                        onTap: _start,
                        child: Container(
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: const LinearGradient(colors: [_accent, _accentHi]),
                            boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 10))],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Let's Start", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                              SizedBox(width: 10),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 5; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == 0 ? 22 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: i == 0 ? _accent : const Color(0xFFB9C6DE),
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(IconData ic, String label) => Expanded(
        child: Column(
          children: [
            Icon(ic, color: _accent, size: 26),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink, height: 1.25)),
          ],
        ),
      );

  Widget _divider() => Container(width: 1, height: 40, color: const Color(0xFFD6E0F0));
}
