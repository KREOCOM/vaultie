import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../theme/vaultie_theme.dart';

class _Bank {
  const _Bank(this.name, this.slug);
  final String name;
  final String slug; // assets/banks/<slug>.png
}

/// Screen — bank scale. Three marquee rows of bank logos scroll at different
/// speeds/directions behind faded edges, over a "2 500+ banks" badge.
///
/// Logos load from assets/banks/<slug>.png; a neutral placeholder shows until
/// the real logo assets are dropped in (see the report — NOT colored letters).
class BankScaleScreen extends StatefulWidget {
  const BankScaleScreen({super.key, required this.onNext, this.onBack});

  final VoidCallback onNext;
  final VoidCallback? onBack;

  @override
  State<BankScaleScreen> createState() => _BankScaleScreenState();
}

class _BankScaleScreenState extends State<BankScaleScreen>
    with TickerProviderStateMixin {
  static const _row1 = [
    _Bank('Swedbank', 'swedbank'),
    _Bank('SEB', 'seb'),
    _Bank('Luminor', 'luminor'),
    _Bank('Revolut', 'revolut'),
    _Bank('Citadele', 'citadele'),
    _Bank('Šiaulių bankas', 'siauliu'),
  ];
  static const _row2 = [
    _Bank('LHV', 'lhv'),
    _Bank('Coop Pank', 'coop'),
    _Bank('Deutsche Bank', 'deutsche'),
    _Bank('Commerzbank', 'commerzbank'),
    _Bank('Sparkasse', 'sparkasse'),
    _Bank('ING', 'ing'),
  ];
  static const _row3 = [
    _Bank('N26', 'n26'),
    _Bank('Wise', 'wise'),
    _Bank('bunq', 'bunq'),
    _Bank('ABN AMRO', 'abnamro'),
    _Bank('Rabobank', 'rabobank'),
    _Bank('Nordea', 'nordea'),
  ];
  static const _row4 = [
    _Bank('Monzo', 'monzo'),
    _Bank('Starling', 'starling'),
    _Bank('Klarna', 'klarna'),
    _Bank('Santander', 'santander'),
    _Bank('BNP Paribas', 'bnp'),
    _Bank('KBC', 'kbc'),
  ];
  static const _row5 = [
    _Bank('Erste Bank', 'erste'),
    _Bank('Raiffeisen', 'raiffeisen'),
    _Bank('UniCredit', 'unicredit'),
    _Bank('OP', 'op'),
    _Bank('Danske Bank', 'danske'),
    _Bank('Handelsbanken', 'handelsbanken'),
  ];

  late final AnimationController _c1 =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))
        ..repeat();
  late final AnimationController _c2 =
      AnimationController(vsync: this, duration: const Duration(seconds: 46))
        ..repeat();
  late final AnimationController _c3 =
      AnimationController(vsync: this, duration: const Duration(seconds: 54))
        ..repeat();
  late final AnimationController _c4 =
      AnimationController(vsync: this, duration: const Duration(seconds: 44))
        ..repeat();
  late final AnimationController _c5 =
      AnimationController(vsync: this, duration: const Duration(seconds: 50))
        ..repeat();

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    _c4.dispose();
    _c5.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: widget.onBack,
      gradientBg: true,
      segments: 4,
      segmentsFilled: 4,
      bottom: VtPrimaryButton(label: 'Toliau', onPressed: widget.onNext),
      child: Column(
        children: [
          const SizedBox(height: 6),
          const _Badge(),
          const Spacer(),
          _marquee(_row1, _c1, leftward: true),
          const SizedBox(height: 12),
          _marquee(_row2, _c2, leftward: false),
          const SizedBox(height: 12),
          _marquee(_row3, _c3, leftward: true),
          const SizedBox(height: 12),
          _marquee(_row4, _c4, leftward: false),
          const SizedBox(height: 12),
          _marquee(_row5, _c5, leftward: true),
          const Spacer(),
          Text(
            tr('Jungiamės prie 2 500+ bankų\nvisoje Europoje.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: VT.ink,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.22,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _marquee(List<_Bank> banks, AnimationController ctrl,
      {required bool leftward}) {
    return SizedBox(
      height: 46,
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0.0, 0.08, 0.92, 1.0],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.centerLeft,
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (context, _) {
                final t = ctrl.value;
                final dx = leftward ? -0.5 * t : -0.5 * (1 - t);
                return FractionalTranslation(
                  translation: Offset(dx, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [_set(banks), _set(banks)],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _set(List<_Bank> banks) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final b in banks) _bankCard(b)],
      );

  Widget _bankCard(_Bank b) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: VT.card,
        borderRadius: BorderRadius.circular(13),
        boxShadow: VT.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BankLogo(slug: b.slug),
          const SizedBox(width: 9),
          Text(b.name,
              style: const TextStyle(
                  color: VT.ink, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Real logo from assets/banks/<slug>.png; neutral placeholder until added.
class _BankLogo extends StatelessWidget {
  const _BankLogo({required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.asset(
        'assets/banks/$slug.png',
        width: 26,
        height: 26,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF1EC),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.account_balance_rounded,
              size: 15, color: Color(0xFF9AA6A0)),
        ),
      ),
    );
  }
}

/// White pill "🟢 2 500+ bankų · saugus ryšys" that fades + slides in from top.
class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * -14), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: VT.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: VT.line),
          boxShadow: VT.softShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: VT.accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(tr('2 500+ bankų · saugus ryšys'),
                style: const TextStyle(
                    color: VT.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
