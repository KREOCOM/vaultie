import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../theme/vaultie_theme.dart';

class _Sub {
  const _Sub({
    required this.color,
    required this.name,
    required this.subtitle,
    this.letter,
    this.icon,
    this.warn = false,
    this.redChip,
  });
  final Color color;
  final String name;
  final String subtitle;
  final String? letter;
  final IconData? icon;
  final bool warn;
  final String? redChip;
}

/// Screen 3 — subscriptions stream. An endless vertical loop of payment cards
/// rising bottom→top, softly fading in/out at both ends (ShaderMask).
class SubscriptionStreamScreen extends StatefulWidget {
  const SubscriptionStreamScreen({super.key, required this.onNext, this.onBack});

  final VoidCallback onNext;
  final VoidCallback? onBack;

  @override
  State<SubscriptionStreamScreen> createState() =>
      _SubscriptionStreamScreenState();
}

class _SubscriptionStreamScreenState extends State<SubscriptionStreamScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFE85D5D);
  static const _green = Color(0xFF1DB954);
  static const _blue = Color(0xFF3B82F6);
  static const _purple = Color(0xFF8B5CF6);
  static const _subInk = Color(0xFF586158);

  static const _cards = [
    _Sub(
        color: _red,
        letter: 'N',
        name: 'Netflix',
        subtitle: 'nenaudota 3 mėn',
        warn: true,
        redChip: '−12€/mėn'),
    _Sub(color: _green, letter: 'S', name: 'Spotify', subtitle: '10,99 € / mėn'),
    _Sub(
        color: _blue,
        icon: Icons.account_balance_rounded,
        name: 'Būsto paskola',
        subtitle: '420,00 € / mėn'),
    _Sub(
        color: _purple,
        icon: Icons.verified_user_rounded,
        name: 'Draudimas',
        subtitle: '28,00 € / mėn'),
    _Sub(
        color: _blue,
        icon: Icons.fitness_center_rounded,
        name: 'Sporto salė',
        subtitle: 'nenaudota 4 mėn',
        warn: true,
        redChip: '−35€/mėn'),
    _Sub(
        color: _red,
        icon: Icons.play_arrow_rounded,
        name: 'YouTube Premium',
        subtitle: '11,99 € / mėn'),
  ];

  // Loop geometry: cards spaced [_slot] apart; a full loop is [_slot] × count.
  static const double _slot = 82;
  static const double _cardH = 62;
  double get _loop => _slot * _cards.length;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: widget.onBack,
      gradientBg: true,
      segments: 4,
      segmentsFilled: 2,
      bottom: VtPrimaryButton(label: tr('Toliau'), onPressed: widget.onNext),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Expanded(child: _stream()),
          const SizedBox(height: 8),
          Text(
            tr('Visos tavo prenumeratos.\nVienoje vietoje.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: VT.ink,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              height: 1.22,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Vaultie automatiškai suranda pasikartojančius mokėjimus banko išraše.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _subInk,
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _stream() {
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0x00000000),
        ],
        stops: [0.0, 0.16, 0.84, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: LayoutBuilder(
        builder: (context, c) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var i = 0; i < _cards.length; i++)
                    _positioned(i),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _positioned(int i) {
    var y = (i * _slot - _ctrl.value * _loop) % _loop;
    if (y < 0) y += _loop;
    return Positioned(
      left: 0,
      right: 0,
      top: y - _cardH,
      child: _card(_cards[i]),
    );
  }

  Widget _card(_Sub s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        height: _cardH,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: VT.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: VT.softShadow,
        ),
        child: Row(
          children: [
            _icon(s),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(s.name),
                      style: const TextStyle(
                          color: VT.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(tr(s.subtitle),
                      style: TextStyle(
                          color: s.warn
                              ? const Color(0xFFB4771A)
                              : VT.subtle,
                          fontSize: 13,
                          fontWeight:
                              s.warn ? FontWeight.w600 : FontWeight.w500)),
                ],
              ),
            ),
            if (s.redChip != null) _RedChip(text: tr(s.redChip!)),
          ],
        ),
      ),
    );
  }

  Widget _icon(_Sub s) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(s.color, Colors.white, 0.16)!, s.color],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: s.icon != null
          ? Icon(s.icon, color: Colors.white, size: 20)
          : Text(s.letter ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
    );
  }
}

class _RedChip extends StatelessWidget {
  const _RedChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE4E4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Color(0xFFD14545),
              fontSize: 12.5,
              fontWeight: FontWeight.w800)),
    );
  }
}
