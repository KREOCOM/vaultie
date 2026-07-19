import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Onboarding page 3 — the Planavimas dashboard, and a budget being added.
///
/// Rebuilt from lib/screens/preview/dashboard_preview.dart rather than from a
/// screenshot, so the strings, colours, radii and the flow are the app's own:
/// tapping "Pridėti biudžetą" opens a modal sheet titled "Naujas biudžetas"
/// holding a Wrap of category chips; choosing one reveals the limit block with
/// the suggested figure; "Išsaugoti" closes the sheet and the row appears.
///
/// The numbers continue page 2. Būstas spent 742,50 € there; the app's real
/// suggestion rule (median x1.15, rounded up to a step of 50 above 500) puts
/// its limit at 900 €. Maistas spent 389,20 € → 450 €. Everything else on
/// screen is derived from those two facts, so nothing can disagree.
class OnbPlanning extends StatefulWidget {
  const OnbPlanning({super.key, required this.next});
  final Widget next;

  @override
  State<OnbPlanning> createState() => _OnbPlanningState();
}

// ── palette, from dashboard_preview.dart:44 ──────────────────────────────────
const _bg = Color(0xFFEEF1F7);
const _card = Color(0xFFFFFFFF);
const _soft = Color(0xFFEEF2F8);
const _hair = Color(0xFFE3E9F2);
const _psoft = Color(0xFFE4EDFD);
const _ink = Color(0xFF14203A);
const _muted = Color(0xFF5C6A85);
const _faint = Color(0xFF7C879E);
const _purple = Color(0xFF2F6BFF);
const _good = Color(0xFF2FA34E);
const _warn = Color(0xFFEE7A3A);

class _B {
  const _B(this.name, this.spent, this.limit, this.icon, this.color, this.shape);
  final String name;
  final double spent;
  final double limit;
  final IconData icon;
  final Color color;

  /// Cumulative fraction of this month's spend at seven points across the days
  /// so far. Each category spends differently, and the chart sums these — which
  /// is why adding one visibly bends the line instead of just rescaling it.
  final List<double> shape;

  double get left => limit - spent;
  double get frac => (spent / limit).clamp(0.0, 1.0);
  int get pct => (spent / limit * 100).round();
}

/// Rent and bills land in a couple of large hits early in the month.
const _bustas = _B('Būstas, sąskaitos', 742.50, 900, Icons.home_rounded, Color(0xFF98B00D),
    [0, 0.44, 0.52, 0.58, 0.72, 0.88, 1.0]);

/// Groceries trickle in almost evenly, so the combined line straightens out and
/// climbs later than Būstas alone does.
const _maistas = _B('Maistas, gėrimai', 389.20, 450, Icons.restaurant_rounded, Color(0xFF46AE4B),
    [0, 0.11, 0.26, 0.43, 0.61, 0.80, 1.0]);

/// Day of a 31-day month. The projection overshoots from here, which is what
/// turns the ring and the copy orange.
const _day = 22, _days = 31;

double _proj(double spent) => spent / _day * _days;

/// "1 234,50 €" — thin space, comma decimals, like Money.format.
String _eur(double v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  final p = s.split(',');
  final w = p[0];
  final g = w.length > 3 ? '${w.substring(0, w.length - 3)} ${w.substring(w.length - 3)}' : w;
  return '$g,${p[1]} €';
}

// ── the mock's vertical layout, named once and reused by the finger ──────────
const _padTop = 30.0, _ttlH = 54.0, _chipH = 34.0, _sectH = 46.0;
const _sumH = 274.0, _rowH = 112.0, _gap = 10.0, _addH = 54.0;
const _sumTop = _padTop + _ttlH + _chipH + _sectH;
const _row1Top = _sumTop + _sumH + 12;
const _addTop = _row1Top + _rowH + _gap;
const _addCentre = _addTop + _addH / 2;

const _sheetShort = 300.0, _sheetTall = 486.0;
/// grabber + header + body padding + label + chip gap, to the first chip's middle
const _toFirstChip = 109.0;

class _OnbPlanningState extends State<OnbPlanning> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();

  /// The whole demonstration: tap add → sheet → chip → save → the row appears.
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  /// The curve redraws on its own beat, so the screen is never quite still.
  late final AnimationController _curve =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat();

  /// A slow drift up and down; the phone floats rather than sits.
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    _curve.dispose();
    _float.dispose();
    super.dispose();
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
                  animation: Listenable.merge([_enter, _loop, _curve, _float]),
                  builder: (context, _) {
                    final e = Curves.easeOutCubic.transform(_enter.value);
                    // ±5pt on a sine, so there is no corner at the turn
                    final drift = math.sin(_float.value * math.pi) * 5 - 2.5;

                    return Opacity(
                      opacity: e,
                      child: Transform.translate(
                        offset: Offset(0, ((1 - e) * 40 + drift) * s),
                        child: Center(
                          child: _Device(width: 268 * s, height: 580 * s, t: _loop.value, curve: _curve.value),
                        ),
                      ),
                    );
                  },
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
                    width: i == 3 ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 3 ? Colors.white : Colors.white.withValues(alpha: 0.38),
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Toliau',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1440B4))),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 19, color: Color(0xFF1440B4)),
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
        const Text('Susikurk biudžetą',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Colors.white, shadows: glow)),
        const Text('ir laikykis jo',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Color(0xFFBFD6FF), shadows: glow)),
        const SizedBox(height: 10),
        Text(
          'Limitą pasiūlysime pagal tavo\nrealų mėnesių vidurkį.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92), shadows: glow),
        ),
      ],
    );
  }
}

// ── device ───────────────────────────────────────────────────────────────────

class _Device extends StatelessWidget {
  const _Device({required this.width, required this.height, required this.t, required this.curve});
  final double width, height, t, curve;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(width * 0.024),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.135),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF161619), Color(0xFF0B0B0D), Color(0xFF000000), Color(0xFF0E0E11), Color(0xFF1A1A1E)],
          stops: [0.0, 0.30, 0.55, 0.85, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xFF060C1E).withValues(alpha: 0.42),
              blurRadius: width * 0.16, offset: Offset(0, width * 0.06)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.116),
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(width: 390, height: 844, child: _Planning(t: t, curve: curve)),
        ),
      ),
    );
  }
}

class _Planning extends StatelessWidget {
  const _Planning({required this.t, required this.curve});
  final double t, curve;

  static double _ramp(double x, double a, double b, [Curve c = Curves.easeInOutCubic]) =>
      c.transform(((x - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    // ── the timeline ──
    final added = t >= 0.50;                                  // the row is in the list
    final chosen = t >= 0.34;                                  // the chip is selected
    final showLimit = t >= 0.37;

    final up = t < 0.17 ? 0.0 : t < 0.23 ? _ramp(t, 0.17, 0.23) : t < 0.54 ? 1.0 : 1 - _ramp(t, 0.54, 0.60);
    final tall = t < 0.38 ? 0.0 : t < 0.48 ? _ramp(t, 0.38, 0.48) : 1.0;
    final sheetH = _sheetShort + (_sheetTall - _sheetShort) * tall;
    final born = t < 0.54 ? 0.0 : _ramp(t, 0.54, 0.62, Curves.easeOutBack);

    final active = added ? const [_bustas, _maistas] : const [_bustas];
    final spent = active.fold(0.0, (a, b) => a + b.spent);
    final limit = active.fold(0.0, (a, b) => a + b.limit);
    final over = (_proj(spent) - limit).round();

    return Container(
      width: 390,
      height: 844,
      color: _bg,
      child: Stack(
        children: [
          // ── the list ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, _padTop, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(
                  height: _ttlH,
                  child: Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 12),
                    child: Text('Planavimas',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.5)),
                  ),
                ),
                SizedBox(
                  height: _chipH,
                  child: Row(children: [_monthChip()]),
                ),
                const SizedBox(
                  height: _sectH,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 10),
                    child: Text('Biudžetai',
                        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.3)),
                  ),
                ),
                _summary(active, spent, limit, over),
                const SizedBox(height: 12),
                _row(_bustas),
                if (born > 0) ...[
                  const SizedBox(height: _gap),
                  Opacity(
                    opacity: born.clamp(0.0, 1.0),
                    child: Transform.translate(offset: Offset(0, (1 - born) * 14), child: _row(_maistas)),
                  ),
                ],
                const SizedBox(height: _gap),
                _addButton(),
              ],
            ),
          ),

          // ── nav ──
          Positioned(left: 0, right: 0, bottom: 0, child: _nav()),

          // ── the sheet and its scrim ──
          if (up > 0) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: const Color(0xFF091022).withValues(alpha: 0.42 * up)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -(1 - up) * sheetH,
              height: sheetH,
              child: _sheet(chosen, showLimit),
            ),
          ],

          _finger(sheetH),
        ],
      ),
    );
  }

  Widget _monthChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hair),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: _purple),
            SizedBox(width: 7),
            Text('Šis mėnuo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _ink)),
            SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _purple),
          ],
        ),
      );

  Widget _summary(List<_B> active, double spent, double limit, int over) => Container(
        height: _sumH,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x1A0A1321), blurRadius: 3, offset: Offset(0, 1)),
            BoxShadow(color: Color(0x1A0F1321), blurRadius: 14, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                _figure(_eur(spent), 'išleista', CrossAxisAlignment.start),
                const Spacer(),
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(painter: _RingPainter(spent / limit)),
                      Center(
                        child: Text('${(spent / limit * 100).round()}%',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                _figure(_eur(limit), 'visas biudžetas', CrossAxisAlignment.end),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 118, child: CustomPaint(painter: _ProjPainter(active, limit, curve), size: Size.infinite)),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1', style: TextStyle(fontSize: 12, color: _muted)),
                Text('8', style: TextStyle(fontSize: 12, color: _muted)),
                Text('16', style: TextStyle(fontSize: 12, color: _muted)),
                Text('24', style: TextStyle(fontSize: 12, color: _muted)),
              ],
            ),
            const SizedBox(height: 8),
            // 12.5 rather than the app's 13.5, and pinned to one line: at 13.5
            // this string measures ~329pt against 326pt of card, so it wrapped
            // and pushed itself out of the bottom of a card sized for one line.
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Tokiu tempu peršoksi biudžetą ~$over € — sulėtink.',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _warn)),
            ),
          ],
        ),
      );

  Widget _figure(String big, String k, CrossAxisAlignment a) => Column(
        crossAxisAlignment: a,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(big, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.4)),
          const SizedBox(height: 1),
          Text(k, style: const TextStyle(fontSize: 13, color: _muted)),
        ],
      );

  Widget _row(_B b) => Container(
        height: _rowH,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hair),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: b.color, shape: BoxShape.circle),
                  child: Icon(b.icon, size: 21, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(b.name, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 2),
                    const Text('Pasiūlyta pagal tavo išlaidas · keisk',
                        style: TextStyle(fontSize: 11.5, color: _muted)),
                  ],
                ),
                const Spacer(),
                Text(_eur(b.limit),
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: _ink)),
                const SizedBox(width: 3),
                const Icon(Icons.edit_rounded, size: 15, color: _faint),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('${_eur(b.spent)} išleista', style: const TextStyle(fontSize: 13.5, color: _muted)),
                const Spacer(),
                Text('${_eur(b.left)} liko',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _warn)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(height: 9, color: _warn.withValues(alpha: 0.14)),
                  FractionallySizedBox(
                    widthFactor: b.frac,
                    child: Container(height: 9, color: _warn),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _addButton() => Container(
        height: _addH,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hair),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 22, color: _purple),
            SizedBox(width: 10),
            Text('Pridėti biudžetą',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _purple)),
          ],
        ),
      );

  Widget _nav() => Container(
        height: 78,
        padding: const EdgeInsets.only(top: 9),
        decoration: const BoxDecoration(
          color: Color(0xF0FFFFFF),
          border: Border(top: BorderSide(color: _hair)),
        ),
        child: Row(
          children: [
            for (final n in const [
              ('Pradžia', Icons.dashboard_rounded, false),
              ('Apžvalga', Icons.donut_large_rounded, false),
              ('AI pokalbis', Icons.auto_awesome_rounded, false),
              ('Planavimas', Icons.event_note_rounded, true),
              ('Paskyra', Icons.person_rounded, false),
            ])
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(n.$2, size: 21, color: n.$3 ? _purple : const Color(0xFF97A2B5)),
                    const SizedBox(height: 4),
                    Text(n.$1,
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600,
                            color: n.$3 ? _purple : const Color(0xFF97A2B5))),
                  ],
                ),
              ),
          ],
        ),
      );

  // ── the modal sheet ──
  Widget _sheet(bool chosen, bool showLimit) => Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.hardEdge,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: _faint, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Row(
                  children: [
                    Text('Naujas biudžetas',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
                    Spacer(),
                    Icon(Icons.close_rounded, size: 20, color: _faint),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Kategorija',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _muted)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        _chip(_maistas.name, _maistas.icon, _maistas.color, chosen),
                        _chip('Transportas', Icons.directions_car_rounded, const Color(0xFF5866F0), false),
                        _chip('Apsipirkimas', Icons.shopping_bag_rounded, const Color(0xFF00897B), false),
                        _chip('Sveikata, sportas', Icons.fitness_center_rounded, _warn, false),
                        _chip('Pramogos', Icons.celebration_rounded, const Color(0xFF2E9BE6), false),
                      ],
                    ),
                    if (showLimit) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text('Mėnesio limitas',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _muted)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: _psoft, borderRadius: BorderRadius.circular(8)),
                            child: Text('siūlome ${_maistas.limit.round()} €',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _purple)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: _soft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _hair),
                        ),
                        child: Row(
                          children: [
                            Text('${_maistas.limit.round()}',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
                            const Spacer(),
                            const Text('€',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _muted)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: _purple, borderRadius: BorderRadius.circular(14)),
                        child: const Text('Išsaugoti',
                            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _chip(String label, IconData icon, Color color, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? _psoft : _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? _purple : _hair, width: on ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? _purple : _ink)),
          ],
        ),
      );

  /// Reaches the add button, then the chip, then Išsaugoti.
  ///
  /// The chip is pressed while the sheet is still short, so its y comes from
  /// [_sheetShort] — measuring it against the grown sheet would put the finger
  /// roughly 180pt above the thing it is meant to be touching.
  Widget _finger(double sheetH) {
    const chipY = (844 - _sheetShort) + _toFirstChip;
    const saveY = 844.0 - 18 - 26;

    late final double x, y;
    double o;
    var press = 1.0;

    if (t < 0.24) {
      x = 198.0; y = _addCentre;
      o = t < 0.08 ? t / 0.08 : t < 0.20 ? 1.0 : 1 - (t - 0.20) / 0.04;
      if (t > 0.17 && t < 0.20) press = 0.82;
    } else if (t < 0.40) {
      x = 109.0; y = chipY;
      o = t < 0.29 ? 0.0 : t < 0.31 ? (t - 0.29) / 0.02 : t < 0.37 ? 1.0 : 1 - (t - 0.37) / 0.03;
      if (t > 0.335 && t < 0.36) press = 0.82;
    } else {
      x = 202.0; y = saveY;
      o = t < 0.44 ? 0.0 : t < 0.46 ? (t - 0.44) / 0.02 : t < 0.51 ? 1.0 : 1 - (t - 0.51) / 0.03;
      if (t > 0.48 && t < 0.505) press = 0.82;
    }
    o = o.clamp(0.0, 1.0);
    if (o <= 0) return const SizedBox.shrink();

    return Positioned(
      left: x - 15,
      top: y - 15,
      child: Opacity(
        opacity: o,
        child: Transform.scale(
          scale: press,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
              gradient: const RadialGradient(
                center: Alignment(-0.32, -0.4),
                colors: [Color(0xF0FFFFFF), Color(0x52FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.46, 0.7],
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF0A1432).withValues(alpha: 0.34),
                    blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── painters ─────────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  const _RingPainter(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 4;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, p..color = const Color(0xFFE7F0E8));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        frac.clamp(0.0, 1.0) * math.pi * 2, false, p..color = _warn);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.frac != frac;
}

/// Cumulative spend to today, then a dashed projection to month end, against a
/// dashed limit line. The solid part is revealed by [reveal] so it redraws.
class _ProjPainter extends CustomPainter {
  const _ProjPainter(this.active, this.limit, this.reveal);
  final List<_B> active;
  final double limit, reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final spent = active.fold(0.0, (a, b) => a + b.spent);
    final projected = _proj(spent);
    final top = math.max(limit, projected) * 1.12;
    double y(double v) => h - (v / top) * h;

    // limit gridline
    final dash = Paint()
      ..color = _good.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    for (var x = 0.0; x < w; x += 11) {
      canvas.drawLine(Offset(x, y(limit)), Offset(math.min(x + 6, w), y(limit)), dash);
    }

    // The cumulative line is the sum of each active budget's own shape, so the
    // trajectory changes when one is added rather than merely rescaling.
    const steps = 7;
    final xEnd = w * (_day / _days);
    final pts = <Offset>[
      for (var i = 0; i < steps; i++)
        Offset(xEnd * i / (steps - 1),
            y(active.fold(0.0, (sum, b) => sum + b.spent * b.shape[i]))),
    ];

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, xEnd * reveal.clamp(0.0, 1.0), h));

    final area = Path.from(line)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_warn.withValues(alpha: 0.22), _warn.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = _warn,
    );
    canvas.restore();

    // projection
    final projPaint = Paint()
      ..color = _faint
      ..strokeWidth = 1.8;
    final a = pts.last, b = Offset(w, y(projected));
    final len = (b - a).distance;
    for (var d = 0.0; d < len; d += 9) {
      final t0 = d / len, t1 = math.min(d + 5, len) / len;
      canvas.drawLine(Offset.lerp(a, b, t0)!, Offset.lerp(a, b, t1)!, projPaint);
    }

    canvas.drawCircle(a, 4, Paint()..color = _warn);
    canvas.drawCircle(a, 4, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ProjPainter old) =>
      old.active.length != active.length || old.limit != limit || old.reveal != reveal;
}

class _ArcGround extends CustomPainter {
  const _ArcGround();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBFDFF));

    final edge = size.height * 0.40;
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
