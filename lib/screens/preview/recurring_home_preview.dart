import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/design_system.dart';

/// Vaultie recurring Home — premium fintech quality (Bilance-level craft) in
/// Vaultie's green identity, on real recurring data. Circular category icons,
/// clean hero ring, flat payment list. Iteration 2.
class RecurringHomePreview extends StatefulWidget {
  const RecurringHomePreview({super.key});

  @override
  State<RecurringHomePreview> createState() => _RecurringHomePreviewState();
}

class _RecurringHomePreviewState extends State<RecurringHomePreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  // category palette (saturated, flat)
  static const _housing = Color(0xFF2E9C63);
  static const _connect = Color(0xFF2E9BE6);
  static const _insure = Color(0xFF5069C4);
  static const _utils = Color(0xFFE39A2A);
  static const _finance = Color(0xFF0E9C8A);
  static const _ent = Color(0xFFE0453E);
  static const _spotify = Color(0xFF1DB954);

  static const _items = <_Item>[
    _Item('Nuoma', 'Būstas · gruodžio 4', 804, true, Icons.home_rounded, _housing),
    _Item('Būsto paskola', 'Paskola · gruodžio 4', 339.71, true, Icons.account_balance_rounded, _finance),
    _Item('Komunaliniai', 'Laukiama gruodžio 18', 153.12, false, Icons.bolt_rounded, _utils),
    _Item('TV ir telefonas', 'Ryšys · gruodžio 3', 152.76, true, Icons.wifi_rounded, _connect),
    _Item('Studijų paskola', 'Paskola · gruodžio 5', 52.87, true, Icons.school_rounded, _finance),
    _Item('Draudimas', 'Laukiama gruodžio 17', 24.13, false, Icons.shield_rounded, _insure),
    _Item('Netflix', 'Prenumerata · gruodžio 2', 12.99, true, Icons.play_arrow_rounded, _ent),
    _Item('YouTube Premium', 'Laukiama šiandien', 11.99, false, Icons.smart_display_rounded, _ent),
    _Item('Spotify', 'Prenumerata · gruodžio 9', 10.99, true, Icons.graphic_eq_rounded, _spotify),
  ];

  double get _paid => _items.where((i) => i.paid).fold(0.0, (a, i) => a + i.amount);
  double get _total => _items.fold(0.0, (a, i) => a + i.amount);
  int get _count => _items.length;

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toPay = _total - _paid;
    final ratio = _total <= 0 ? 1.0 : _paid / _total;
    return Scaffold(
      backgroundColor: DS.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _filters()),
            SliverToBoxAdapter(child: _fade(0, _hero(paid: _paid, toPay: toPay, ratio: ratio))),
            SliverToBoxAdapter(child: _fade(1, _savingsRow())),
            SliverToBoxAdapter(child: _fade(2, _sectionLabel())),
            SliverToBoxAdapter(child: _fade(3, _listCard())),
            const SliverToBoxAdapter(child: SizedBox(height: DS.s28)),
          ],
        ),
      ),
    );
  }

  Widget _fade(int i, Widget child) {
    final start = (i * 0.1).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _in,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, (1 - anim.value) * 12), child: c),
      ),
      child: child,
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.gutter, DS.s12, DS.gutter, DS.s14),
      child: Row(
        children: [
          const Text('Gruodis', style: AppType.displayLg),
          const Spacer(),
          _iconBtn(Icons.visibility_outlined),
          const SizedBox(width: DS.s6),
          _iconBtn(Icons.search_rounded),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon) => SizedBox(
        width: 40,
        height: 40,
        child: Center(child: Icon(icon, size: 23, color: DS.ink)),
      );

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.gutter, 0, DS.gutter, DS.s16),
      child: Row(
        children: const [
          FilterPill(icon: Icons.calendar_today_rounded, label: 'Šį mėnesį'),
          SizedBox(width: DS.s10),
          FilterPill(icon: Icons.tune_rounded, label: 'Filtras'),
        ],
      ),
    );
  }

  // ── HERO ──
  Widget _hero({required double paid, required double toPay, required double ratio}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.gutter, 0, DS.gutter, DS.s12),
      child: AppCard(
        radius: DS.rHero,
        shadow: DS.e2,
        padding: const EdgeInsets.fromLTRB(DS.s20, DS.s20, DS.s20, DS.s20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sumokėta', style: AppType.moneySm.copyWith(color: DS.ink2)),
                  const SizedBox(height: DS.s4),
                  MoneyText(paid, style: AppType.moneyLg),
                  const SizedBox(height: DS.s16),
                  Text('Dar liks', style: AppType.moneySm.copyWith(color: DS.ink2)),
                  const SizedBox(height: DS.s4),
                  MoneyText(toPay, style: AppType.moneyLg.copyWith(color: DS.brand, fontSize: 18)),
                ],
              ),
            ),
            _ProgressRing(ratio: ratio),
          ],
        ),
      ),
    );
  }

  // ── SAVINGS ROW ──
  Widget _savingsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.gutter, 0, DS.gutter, DS.s16),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: DS.s14, vertical: DS.s12),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: Material(
                color: const Color(0xFFEAF3EC),
                shape: const CircleBorder(),
                child: const Center(
                    child: Icon(Icons.savings_rounded, size: 20, color: DS.brand)),
              ),
            ),
            const SizedBox(width: DS.s12),
            const Expanded(
              child: Text('Sutaupyta atšaukus', style: AppType.rowTitle),
            ),
            MoneyText(96, style: AppType.money.copyWith(color: DS.paid)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DS.gutter + DS.s2, 0, DS.gutter + DS.s2, DS.s10),
      child: Row(
        children: [
          const Text('GRUODŽIO MOKĖJIMAI', style: AppType.overline),
          const Spacer(),
          Text('$_count', style: AppType.overline.copyWith(letterSpacing: 0)),
        ],
      ),
    );
  }

  Widget _listCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.gutter),
      child: AppCard(
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              _ItemRow(item: _items[i]),
              if (i != _items.length - 1) const RowDivider(indent: 62),
            ],
          ],
        ),
      ),
    );
  }
}

// ── PREMIUM PROGRESS RING ──
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.ratio});
  final double ratio;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: CustomPaint(
        painter: _RingPainter(ratio),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(ratio * 100).round()}%',
                  style: const TextStyle(
                      color: DS.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      height: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 1),
              Text('sumokėta',
                  style: TextStyle(
                      color: DS.ink3, fontSize: 9.5, fontWeight: FontWeight.w600, height: 1.0)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.ratio);
  final double ratio;
  static const _stroke = 7.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(_stroke / 2, _stroke / 2) &
        Size(size.width - _stroke, size.height - _stroke);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _stroke) / 2;

    canvas.drawArc(rect, 0, 2 * math.pi, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = _stroke..color = DS.track);

    final r = ratio.clamp(0.0, 1.0);
    final sweep = 2 * math.pi * r;
    final shader = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: 3 * math.pi / 2,
      colors: const [DS.brand, DS.accent],
      stops: [0.0, r.clamp(0.05, 1.0)],
    ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..shader = shader);

    final a = -math.pi / 2 + sweep;
    final end = Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
    canvas.drawCircle(end, _stroke / 2 + 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(end, _stroke / 2 - 0.5, Paint()..color = DS.accent);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ratio != ratio;
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});
  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DS.s14, vertical: DS.s10),
      child: Row(
        children: [
          CategoryIcon(icon: item.icon, color: item.color, size: 38),
          const SizedBox(width: DS.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.rowTitle),
                const SizedBox(height: DS.s2),
                Text(item.due,
                    style: AppType.rowSub.copyWith(
                        color: item.paid ? DS.ink2 : DS.pending,
                        fontWeight: item.paid ? FontWeight.w500 : FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: DS.s10),
          MoneyText(item.amount, style: AppType.money),
          const SizedBox(width: DS.s10),
          _status(item.paid),
        ],
      ),
    );
  }

  Widget _status(bool paid) {
    if (paid) {
      return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: DS.paid, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
      );
    }
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFCED6CE), width: 1.6),
      ),
    );
  }
}

class _Item {
  const _Item(this.name, this.due, this.amount, this.paid, this.icon, this.color);
  final String name, due;
  final double amount;
  final bool paid;
  final IconData icon;
  final Color color;
}
