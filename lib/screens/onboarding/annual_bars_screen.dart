import 'package:flutter/material.dart';

import '../../theme/vaultie_theme.dart';

/// Screen 2 — "annual sum". A 12-bar chart grows bar-by-bar from the bottom,
/// then the big €344 total counts up. Slow, subtle, premium.
class AnnualBarsScreen extends StatefulWidget {
  const AnnualBarsScreen({super.key, required this.onNext, this.onBack});

  final VoidCallback onNext;
  final VoidCallback? onBack;

  @override
  State<AnnualBarsScreen> createState() => _AnnualBarsScreenState();
}

class _AnnualBarsScreenState extends State<AnnualBarsScreen>
    with SingleTickerProviderStateMixin {
  // Bar heights as fractions of the tallest (left lowest → right tallest).
  static const _pct = [
    0.09, 0.16, 0.24, 0.32, 0.41, 0.50, 0.59, 0.68, 0.77, 0.86, 0.94, 1.0,
  ];
  static const _staggerMs = 90;
  static const _barMs = 600;
  static const _target = 344;
  static const _subInk = Color(0xFF586158);

  late final AnimationController _bars = AnimationController(
    vsync: this,
    // Last bar starts at 11*90=990ms and runs 600ms → total ~1590ms.
    duration: Duration(milliseconds: (_pct.length - 1) * _staggerMs + _barMs),
  );

  @override
  void initState() {
    super.initState();
    // The bars grow and the € counter climbs from the same controller, so the
    // number rises in lock-step with the chart.
    _bars.forward();
  }

  @override
  void dispose() {
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: widget.onBack,
      gradientBg: true,
      segments: 4,
      segmentsFilled: 1,
      bottom: VtPrimaryButton(label: 'Toliau', onPressed: widget.onNext),
      child: Column(
        children: [
          const Spacer(flex: 2),
          _Chart(controller: _bars, pct: _pct, staggerMs: _staggerMs, barMs: _barMs),
          const SizedBox(height: 30),
          AnimatedBuilder(
            animation: _bars,
            builder: (context, _) {
              final value = (_target * _bars.value).round();
              // Quick fade-in over the first slice of the animation so the
              // number appears as the bars start rising, then climbs with them.
              final opacity = (_bars.value / 0.15).clamp(0.0, 1.0);
              return Opacity(
                opacity: opacity,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: Text('€',
                              style: TextStyle(
                                  color: VT.brand,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 2),
                        Text('$value',
                            style: const TextStyle(
                              color: VT.brand,
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.0,
                              height: 1.0,
                              fontFeatures: [FontFeature.tabularFigures()],
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('per metus — vienai prenumeratai',
                        style: TextStyle(
                            color: _subInk,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            },
          ),
          const Spacer(flex: 2),
          const Text(
            'Net mažos išlaidos per metus\nvirsta didele suma.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: VT.ink,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.22,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Vaultie automatiškai apskaičiuoja, kiek tavo prenumeratos ir kitos pasikartojančios išlaidos kainuoja per metus.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _subInk,
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.controller,
    required this.pct,
    required this.staggerMs,
    required this.barMs,
  });

  final AnimationController controller;
  final List<double> pct;
  final int staggerMs;
  final int barMs;

  static const _maxHeight = 168.0;

  @override
  Widget build(BuildContext context) {
    final totalMs = controller.duration!.inMilliseconds;
    return SizedBox(
      height: _maxHeight,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final raw = controller.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < pct.length; i++) ...[
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      height: _maxHeight * pct[i] * _grow(raw, i, totalMs),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: _bandColors(i),
                        ),
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
                if (i < pct.length - 1) const SizedBox(width: 6),
              ],
            ],
          );
        },
      ),
    );
  }

  double _grow(double raw, int i, int totalMs) {
    final start = (i * staggerMs) / totalMs;
    final end = (i * staggerMs + barMs) / totalMs;
    final local = ((raw - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(local);
  }

  /// Bars rise from "small = fine" to "large = a lot": the first four are
  /// green, the next five amber, the last three red. Each returns a
  /// [lighter-top, saturated-bottom] pair for a subtle vertical gradient.
  List<Color> _bandColors(int i) {
    if (i < 4) return const [Color(0xFF48D488), Color(0xFF16A34A)]; // green
    if (i < 9) return const [Color(0xFFFBCB4B), Color(0xFFF39A0B)]; // amber
    return const [Color(0xFFF87171), Color(0xFFE23B3B)]; // red
  }
}
