import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../theme/vaultie_theme.dart';

class _Notif {
  const _Notif(this.service, this.body);
  final String service; // netflix | spotify | youtube | disney | icloud
  final String body;
}

/// Screen — reminders. Push notifications drop in one-by-one at the top (spring),
/// pushing the earlier ones down — showing Vaultie warns before every charge.
/// No question / answer buttons.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, required this.onNext, this.onBack});

  final VoidCallback onNext;
  final VoidCallback? onBack;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  static const _all = [
    _Notif('netflix', 'Rytoj nurašys Netflix — 12,99 €'),
    _Notif('spotify', 'Po 2 d. atsinaujins Spotify — 10,99 €'),
    _Notif('youtube', 'YouTube Premium po 4 d. — 11,99 €'),
    _Notif('disney', 'Disney+ nenaudotas 2 mėn — gal atšaukti?'),
    _Notif('icloud', 'iCloud+ nurašys rytoj — 2,99 €'),
  ];
  static const _subInk = Color(0xFF586158);

  final _listKey = GlobalKey<AnimatedListState>();
  final List<_Notif> _visible = [];
  int _added = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 750), (t) {
      if (_added >= _all.length) {
        t.cancel();
        return;
      }
      _visible.insert(0, _all[_added]); // newest on top
      _listKey.currentState
          ?.insertItem(0, duration: const Duration(milliseconds: 560));
      _added++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VtScaffold(
      onBack: widget.onBack,
      gradientBg: true,
      segments: 4,
      segmentsFilled: 3,
      bottom: VtPrimaryButton(label: 'Toliau', onPressed: widget.onNext),
      child: Column(
        children: [
          const SizedBox(height: 10),
          SizedBox(
            height: 392,
            child: AnimatedList(
              key: _listKey,
              physics: const NeverScrollableScrollPhysics(),
              initialItemCount: 0,
              itemBuilder: (context, index, animation) =>
                  _item(_visible[index], animation),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr('Įspėsim prieš kiekvieną\nmokėjimą.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: VT.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.22,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Jokių netikėtų nurašymų — spėsi atšaukti, kol pinigai dar nenuskaityti.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
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

  Widget _item(_Notif n, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.28), end: Offset.zero)
              .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
          child: _card(n),
        ),
      ),
    );
  }

  Widget _card(_Notif n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VT.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: VT.softShadow,
      ),
      child: Row(
        children: [
          _ServiceIcon(service: n.service),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('VAULTIE',
                        style: TextStyle(
                            color: VT.subtle,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const Spacer(),
                    Text(tr('dabar'),
                        style: TextStyle(
                            color: VT.subtle.withValues(alpha: 0.8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(tr(n.body),
                    style: const TextStyle(
                        color: VT.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand-coloured service tile (mock). Real logos can later load from
/// assets/services/<key>.png; these are recognisable placeholders.
class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({required this.service});
  final String service;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    Widget glyph;
    switch (service) {
      case 'netflix':
        color = const Color(0xFFE50914);
        glyph = const Text('N',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800));
        break;
      case 'spotify':
        color = const Color(0xFF1DB954);
        glyph = const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 18);
        break;
      case 'youtube':
        color = const Color(0xFFFF0000);
        glyph = const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20);
        break;
      case 'disney':
        color = const Color(0xFF1140C9);
        glyph = const Text('D+',
            style: TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800));
        break;
      case 'icloud':
      default:
        color = const Color(0xFF3B9BE8);
        glyph = const Icon(Icons.cloud_rounded, color: Colors.white, size: 18);
    }
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.16)!, color],
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: glyph,
    );
  }
}
