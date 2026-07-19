import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import 'package:flutter/rendering.dart';

/// Onboarding page 4 — the month overview, which is far longer than a screen.
///
/// The phone scrolls itself through the month with pauses at each section, so
/// the depth is visible without the content becoming a blur. The stops are read
/// from the real layout via [RenderAbstractViewport], not from copied numbers:
/// in the HTML prototype every hardcoded offset went stale the moment a card
/// grew, and the animation quietly stopped short of the last section.
///
/// Numbers continue page 2's July. The categories sum to the month's spending,
/// the daily figures are that spending over 31 days, and the savings rate falls
/// out of income minus spending — so no two lines here can disagree.
class OnbMonth extends StatefulWidget {
  const OnbMonth({super.key, required this.next});
  final Widget next;

  @override
  State<OnbMonth> createState() => _OnbMonthState();
}

const _bg = Color(0xFFEEF1F7);
const _card = Color(0xFFFFFFFF);
const _soft = Color(0xFFEEF2F8);
const _hair = Color(0xFFE3E9F2);
const _ink = Color(0xFF14203A);
const _muted = Color(0xFF5C6A85);
const _purple = Color(0xFF2F6BFF);
const _good = Color(0xFF2FA34E);
const _bad = Color(0xFFE0574F);

class _Cat {
  const _Cat(this.name, this.amount, this.icon, this.color);
  final String name;
  final double amount;
  final IconData icon;
  final Color color;
}

const _cats = <_Cat>[
  _Cat('Būstas, sąskaitos', 742.50, Icons.home_rounded, Color(0xFF98B00D)),
  _Cat('Maistas, gėrimai', 389.20, Icons.restaurant_rounded, Color(0xFF46AE4B)),
  _Cat('Transportas', 214.80, Icons.directions_car_rounded, Color(0xFF5866F0)),
  _Cat('Pramogos', 168.40, Icons.celebration_rounded, Color(0xFF2E9BE6)),
  _Cat('Sveikata, sportas', 131.60, Icons.fitness_center_rounded, Color(0xFFEE7A3A)),
  _Cat('Kita', 129.50, Icons.more_horiz_rounded, Color(0xFF6E7687)),
];

const _income = 2400.00;
const _daysInMonth = 31;
final double _spend = _cats.fold(0.0, (s, c) => s + c.amount);   // 1 776,00
final double _net = _income - _spend;                            // 624,00
final int _rate = (_net / _income * 100).round();                // 26
final double _perDay = _spend / _daysInMonth;                    // 57,29

String _eur(double v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  final p = s.split(',');
  final w = p[0];
  final g = w.length > 3 ? '${w.substring(0, w.length - 3)} ${w.substring(w.length - 3)}' : w;
  return '$g,${p[1]} €';
}

String _round(double v) {
  final w = v.round().toString();
  return '${w.length > 3 ? '${w.substring(0, w.length - 3)} ${w.substring(w.length - 3)}' : w} €';
}

class _OnbMonthState extends State<OnbMonth> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))
        ..repeat(reverse: true);

  final _sc = ScrollController();
  final _kAi = GlobalKey(), _kInsights = GlobalKey(), _kDaily = GlobalKey();
  bool _touring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTour());
  }

  @override
  void dispose() {
    _enter.dispose();
    _float.dispose();
    _sc.dispose();
    super.dispose();
  }

  /// The scroll offset that brings [key]'s section to the top of the viewport.
  double? _offsetOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.0).offset;
  }

  Future<void> _startTour() async {
    if (_touring) return;
    _touring = true;

    while (mounted && _sc.hasClients) {
      final max = _sc.position.maxScrollExtent;
      // Read the stops fresh each lap: they come from the laid-out widgets, so
      // editing a card above them can never leave the tour pointing at nothing.
      final stops = <double>[
        0,
        ...[_kAi, _kInsights, _kDaily]
            .map(_offsetOf)
            .whereType<double>()
            .map((o) => o.clamp(0.0, max)),
        max,
      ];

      for (final target in stops) {
        if (!mounted || !_sc.hasClients) return;
        await _sc.animateTo(target,
            duration: const Duration(milliseconds: 560), curve: Curves.easeInOutCubic);
        await Future<void>.delayed(const Duration(milliseconds: 1050));
      }
      if (!mounted || !_sc.hasClients) return;
      await _sc.animateTo(0, duration: const Duration(milliseconds: 480), curve: Curves.easeInOutCubic);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
  }

  void _start(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxHeight / 844;

          return Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: _ArcGround())),
              Positioned(
                top: 26 * s,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_enter, _float]),
                  builder: (context, child) {
                    final e = Curves.easeOutCubic.transform(_enter.value);
                    final drift = (_float.value - 0.5) * 10;
                    return Opacity(
                      opacity: e,
                      child: Transform.translate(
                        offset: Offset(0, ((1 - e) * 40 + drift) * s),
                        child: child,
                      ),
                    );
                  },
                  child: Center(child: _device(268 * s, 580 * s)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 26 * s,
                child: AnimatedBuilder(
                  animation: _enter,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(((_enter.value - 0.35) / 0.65).clamp(0.0, 1.0));
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
                    );
                  },
                  child: _foot(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _device(double w, double h) => Container(
        width: w,
        height: h,
        padding: EdgeInsets.all(w * 0.024),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.135),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF161619), Color(0xFF0B0B0D), Color(0xFF000000), Color(0xFF0E0E11), Color(0xFF1A1A1E)],
            stops: [0.0, 0.30, 0.55, 0.85, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF060C1E).withValues(alpha: 0.42),
                blurRadius: w * 0.16, offset: Offset(0, w * 0.06)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * 0.116),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: 390, height: 844, child: _screen()),
          ),
        ),
      );

  Widget _screen() => Container(
        color: _bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _sc,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _chips(),
                      const SizedBox(height: 16),
                      _rings(),
                      _plain('Liepos suma', '−${_eur(_spend)}'),
                      _stats(),
                      _ai(key: _kAi),
                      _categoryHeader(),
                      _categoryList(),
                      _h2(tr('Įžvalgos'), key: _kInsights),
                      _insight(_cats[1], 451.20, _cats[1].amount),
                      _insight(_cats[0], 624.50, _cats[0].amount),
                      _h2(tr('Vidutinės dienos išlaidos'), key: _kDaily),
                      _daily(),
                      _h2(tr('Prekybininkai')),
                      _plainCard(tr('34 prekybininkai')),
                      _h2(tr('Didžiausios išlaidos')),
                      _biggest(),
                    ],
                  ),
                ),
              ),
            ),
            // the bar sits above the feed, as it does in the app
            Positioned(
              left: 0, right: 0, top: 0,
              child: Container(
                height: 120,
                color: const Color(0xFF2149C8),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                alignment: Alignment.bottomLeft,
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Colors.white),
                    const SizedBox(width: 12),
                    Text(tr('Liepos apžvalga'),
                        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _chips() => Row(
        children: [
          _chip(Icons.calendar_today_rounded, tr('Liepa')),
          const SizedBox(width: 10),
          _chip(Icons.tune_rounded, tr('Filtras')),
        ],
      );

  Widget _chip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i, size: 15, color: _purple),
            const SizedBox(width: 7),
            Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
          ],
        ),
      );

  Widget _rings() => SizedBox(
        height: 170,
        child: Row(
          children: [
            Expanded(child: _ring(true)),
            const SizedBox(width: 14),
            Expanded(child: _ring(false)),
          ],
        ),
      );

  Widget _ring(bool out) => Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _DonutPainter(out)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(out ? '−' : '+',
                    style: const TextStyle(fontSize: 15, color: _muted, fontWeight: FontWeight.w600, height: 1)),
                Text(out ? _round(_spend) : _round(_income),
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: _ink, height: 1.3)),
                Text(out ? tr('Išleista') : tr('Gauta'),
                    style: const TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );

  Widget _plain(String k, String v) => Container(
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Text(k, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      );

  Widget _plainCard(String t) => Container(
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _muted),
          ],
        ),
      );

  Widget _stats() => Container(
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            _stat(_round(_spend), tr('išleista')),
            _divider(),
            _stat(_round(_income), tr('uždirbta')),
            _divider(),
            _stat('+${_net.round()} €', tr('grynasis')),
            _divider(),
            _stat('$_rate %', tr('santaupų')),
          ],
        ),
      );

  Widget _stat(String v, String k) => Expanded(
        child: Column(
          children: [
            Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 2),
            Text(k, style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      );

  Widget _divider() => Container(width: 1, height: 34, color: _hair);

  Widget _ai({Key? key}) => Container(
        key: key,
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr('SANTRAUKA'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _purple, letterSpacing: 0.7)),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFE4EDFD), borderRadius: BorderRadius.circular(5)),
                  child: const Text('AI',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: _purple)),
                ),
                const Spacer(),
                const Icon(Icons.auto_awesome_rounded, size: 18, color: _purple),
              ],
            ),
            const SizedBox(height: 9),
            Text(tr('Liepos finansų momentas 📸'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 8),
            Text(
              tr('Liepa buvo tvarkinga. Gavai {a} €, išleidai {b} €, tad atsidėjai {c} € — santaupų norma {d} %, virš 20 % tikslo. Daugiausia nusinešė būstas ir sąskaitos ({e} €) bei maistas ({f} €).')
                  .replaceFirst('{a}', '${_income.round()}')
                  .replaceFirst('{b}', '${_spend.round()}')
                  .replaceFirst('{c}', '${_net.round()}')
                  .replaceFirst('{d}', '$_rate')
                  .replaceFirst('{e}', '${_cats[0].amount.round()}')
                  .replaceFirst('{f}', '${_cats[1].amount.round()}'),
              style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF2A3854)),
            ),
          ],
        ),
      );

  Widget _categoryHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(3, 16, 3, 7),
        child: Row(
          children: [
            Text(tr('Kategorija'), style: const TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(tr('Suma'), style: const TextStyle(fontSize: 12.5, color: _purple, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _categoryList() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            for (var i = 0; i < _cats.length; i++) ...[
              if (i > 0) Container(height: 1, color: const Color(0xFFEDEFF4)),
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    _icon(_cats[i], 32, 16),
                    const SizedBox(width: 12),
                    Text(tr(_cats[i].name),
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                    const Spacer(),
                    Text('−${_eur(_cats[i].amount)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _icon(_Cat c, double size, double glyph) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
        child: Icon(c.icon, size: glyph, color: Colors.white),
      );

  Widget _h2(String t, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(t, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _ink)),
      );

  /// The insight card, matching dashboard_preview.dart:4655 — including the
  /// outlined "Nusistatyti biudžetą" button, which the prototype had dropped.
  Widget _insight(_Cat c, double prev, double now) {
    final diff = now - prev;
    final more = diff >= 0;
    return Container(
      margin: const EdgeInsets.only(top: 11),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _hair),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0A1321), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x1A0F1321), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(c.icon, size: 22, color: c.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: _ink, height: 1.35),
                    children: [
                      TextSpan(text: '${tr('Kategorijai')} „${tr(c.name).split(',').first}" ${tr('išleidai')} '),
                      TextSpan(
                        text: '${diff.abs().round()} €',
                        style: TextStyle(fontWeight: FontWeight.w800, color: more ? _bad : _good),
                      ),
                      TextSpan(text: ' ${more ? tr('daugiau') : tr('mažiau')} ${tr('nei praėjusį mėnesį.')}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _insightBox(c.color, prev, tr('Birželis'))),
              const SizedBox(width: 10),
              Expanded(child: _insightBox(c.color, now, tr('Liepa'))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _purple),
            ),
            child: Text(tr('Nusistatyti biudžetą'),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _purple)),
          ),
        ],
      ),
    );
  }

  Widget _insightBox(Color color, double v, String label) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _soft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hair),
        ),
        child: Row(
          children: [
            Container(width: 26, height: 26, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('−${_eur(v)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
                Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
          ],
        ),
      );

  Widget _daily() => Container(
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Row(
              children: [
                Text(tr('Liepa'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
                const Spacer(),
                Text('−${_eur(_perDay)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
              ],
            ),
            const SizedBox(height: 9),
            // each category's share of a day; all six sum to the header figure
            for (final c in _cats)
              SizedBox(
                height: 38,
                child: Row(
                  children: [
                    _icon(c, 26, 13),
                    const SizedBox(width: 11),
                    Text(tr(c.name), style: const TextStyle(fontSize: 13.5, color: _ink)),
                    const Spacer(),
                    Text('−${_eur(c.amount / _daysInMonth)}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _ink)),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _biggest() => Container(
        margin: const EdgeInsets.only(top: 11),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            for (final e in [
              (tr('Nuoma'), tr('Liepos {d}').replaceFirst('{d}', '1'), 520.00, 0),
              ('Maxima', tr('Liepos {d}').replaceFirst('{d}', '12'), 86.40, 1),
            ]) ...[
              if (e.$4 > 0) Container(height: 1, color: const Color(0xFFEDEFF4)),
              SizedBox(
                height: 58,
                child: Row(
                  children: [
                    _icon(_cats[e.$4], 32, 16),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(e.$1, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                        Text(e.$2, style: const TextStyle(fontSize: 11, color: _muted)),
                      ],
                    ),
                    const Spacer(),
                    Text('−${_eur(e.$3)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _foot(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == 2 ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 2 ? Colors.white : Colors.white.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _copy(),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _start(context),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF0A2260).withValues(alpha: 0.28),
                        blurRadius: 18, offset: const Offset(0, 8)),
                  ],
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tr('Toliau'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1440B4))),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 19, color: Color(0xFF1440B4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _copy() {
    const glow = [Shadow(color: Color(0x730A1E4B), blurRadius: 14, offset: Offset(0, 2))];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('Visas mėnuo'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Colors.white, shadows: glow)),
        Text(tr('vienoje vietoje'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Color(0xFFBFD6FF), shadows: glow)),
        const SizedBox(height: 10),
        Text(
          tr('Kur nuėjo pinigai, kas pasikeitė\nir kiek tai kainuoja per dieną.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92), shadows: glow),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.out);
  final bool out;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    const stroke = 15.0;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: d - stroke, height: d - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    if (!out) {
      canvas.drawArc(rect, 0, 6.2831853, false, p..color = const Color(0xFF6E7687));
      return;
    }
    var start = -1.5707963;
    for (final c in _cats) {
      final sweep = c.amount / _spend * 6.2831853;
      canvas.drawArc(rect, start, sweep, false, p..color = c.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.out != out;
}

class _ArcGround extends CustomPainter {
  const _ArcGround();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBFDFF));
    final edge = size.height * 0.46;
    final path = Path()
      ..moveTo(0, edge)
      ..quadraticBezierTo(size.width / 2, edge - size.height * 0.09, size.width, edge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF3E74FF), Color(0xFF2F6BFF), Color(0xFF1E4FD8)],
          stops: [0, 0.42, 1],
        ).createShader(Rect.fromLTWH(0, edge, size.width, size.height - edge)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
