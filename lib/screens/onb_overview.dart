import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Onboarding page 2 — the Apžvalga dashboard opening into Santaupų norma.
///
/// The device holds two screens side by side. A finger reaches the "Santaupų
/// norma" row, presses it, and the pair slides across to the detail screen with
/// its statistics. One controller drives the whole thing so the press and the
/// slide can never drift apart.
///
/// Layout is the "F" option from docs/onboarding-overview-preview.html: the
/// phone is deliberately larger than the space above the copy, and its lower
/// edge runs behind the card. The card carries an upward shadow so that reads
/// as one thing lying over another rather than as a collision.
///
/// Every figure is derived from its parts — the categories sum to the month's
/// spending, and the rate is computed from income and spending — so no two
/// screens here can contradict each other.
class OnbOverview extends StatefulWidget {
  const OnbOverview({super.key, required this.next});
  final Widget next;

  @override
  State<OnbOverview> createState() => _OnbOverviewState();
}

// ── the month, invented but self-consistent ──────────────────────────────────

class _Cat {
  const _Cat(this.name, this.amount, this.icon, this.color);
  final String name;
  final double amount;
  final IconData icon;
  final Color color;
}

const _cats = <_Cat>[
  _Cat('Būstas, sąskaitos', 742.50, Icons.home_rounded, Color(0xFFA9BE3F)),
  _Cat('Maistas, gėrimai', 389.20, Icons.restaurant_rounded, Color(0xFF4E9A51)),
  _Cat('Transportas', 214.80, Icons.directions_car_rounded, Color(0xFFC8544A)),
  _Cat('Pramogos', 168.40, Icons.movie_rounded, Color(0xFF3D6BE5)),
  _Cat('Sveikata', 131.60, Icons.favorite_rounded, Color(0xFF5BA9DE)),
  _Cat('Kita', 129.50, Icons.more_horiz_rounded, Color(0xFF6E7687)),
];

const _income = 2400.00;
final double _spend = _cats.fold(0.0, (s, c) => s + c.amount);   // 1 776,00
final double _saved = _income - _spend;                          // 624,00
final int _rate = ((_saved / _income) * 100).round();            // 26

/// Six months of rates; the last one must equal the month shown above.
const _months = <(String, int)>[
  ('Vas', 18), ('Kov', 22), ('Bal', 12), ('Geg', 29), ('Bir', 21), ('Lie', 26),
];
final int _peak = _months.map((m) => m.$2).reduce(math.max);
final double _avg = _months.map((m) => m.$2).reduce((a, b) => a + b) / _months.length;

/// The Apžvalga mock is laid out with named gaps, and the finger is placed from
/// the same arithmetic — so the two cannot drift apart when something above the
/// row changes.
const _ringH = 168.0;
const _normRowTop = 54 + 38 + 14 + 34 + 16 + _ringH + 14 + 46 + 10;
const _normRowCentre = _normRowTop + 23;

const _brand = Color(0xFF2F6BFF);
const _ink = Color(0xFF14203A);
const _dim = Color(0xFF5C6A85);

/// "1 776 €" — no cents, grouped, for the ring labels.
String _round(double v) {
  final w = v.round().toString();
  return '${w.length > 3 ? '${w.substring(0, w.length - 3)} ${w.substring(w.length - 3)}' : w} €';
}

String _eur(double v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  final parts = s.split(',');
  final whole = parts[0];
  final grouped = whole.length > 3
      ? '${whole.substring(0, whole.length - 3)} ${whole.substring(whole.length - 3)}'
      : whole;
  return '$grouped,${parts[1]} €';
}

class _OnbOverviewState extends State<OnbOverview> with TickerProviderStateMixin {
  /// Plays once when the screen opens — the device rises into place.
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();

  /// Runs forever: reach → press → slide → hold → slide back.
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 7000))..repeat();

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
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

  /// Maps t onto a 0→1 ramp across [from, to], flat outside it.
  static double _ramp(double t, double from, double to, {Curve curve = Curves.easeOutCubic}) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          // Everything below is authored against an 844pt page and scaled, so
          // the proportions from the preview survive on any phone.
          final s = box.maxHeight / 844;

          return Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: _ArcGround())),

              // the device, running behind the copy card on purpose
              Positioned(
                top: 30 * s,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_enter, _loop]),
                  builder: (context, _) {
                    final e = Curves.easeOutCubic.transform(_enter.value);
                    final t = _loop.value;

                    // slide across after the press, and back at the very end
                    final slide = t < 0.40
                        ? 0.0
                        : t < 0.52
                            ? _ramp(t, 0.40, 0.52, curve: Curves.easeInOutCubic)
                            : t < 0.92
                                ? 1.0
                                : 1 - _ramp(t, 0.92, 1.0, curve: Curves.easeInOutCubic);

                    return Opacity(
                      opacity: e,
                      child: Transform.translate(
                        offset: Offset(0, (1 - e) * 40 * s),
                        child: Center(
                          child: _Device(width: 268 * s, height: 580 * s, slide: slide, t: t),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // the copy, pinned to the bottom
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
                for (var i = 0; i < 5; i++)
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

  /// The copy sits straight on the blue, with no card behind it.
  ///
  /// A black slab here read as an extension of the black phone directly above
  /// it — two dark rectangles touching, which merged into one shape. The blue
  /// is already a field of its own, so the text does not need a second one.
  /// Soft shadows carry it where the blue is lightest.
  Widget _copy() {
    const glow = [Shadow(color: Color(0x730A1E4B), blurRadius: 14, offset: Offset(0, 2))];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Kiek iš tikrųjų',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Colors.white, shadows: glow)),
        const Text('atsidedi',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Color(0xFFBFD6FF), shadows: glow)),
        const SizedBox(height: 10),
        Text(
          'Iš pajamų ir išlaidų — tavo\nsantaupų norma kas mėnesį.',
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
  const _Device({required this.width, required this.height, required this.slide, required this.t});
  final double width;
  final double height;

  /// 0 = Apžvalga on screen, 1 = Santaupų norma on screen.
  final double slide;

  /// The loop's own position, for the finger.
  final double t;

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
          BoxShadow(color: const Color(0xFF060C1E).withValues(alpha: 0.4),
              blurRadius: width * 0.16, offset: Offset(0, width * 0.06)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.116),
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: 390,
            height: 844,
            child: ClipRect(
              child: Stack(
                children: [
                  Transform.translate(
                    offset: Offset(-390 * slide, 0),
                    child: _OverviewMock(lit: t > 0.42 && t < 0.52),
                  ),
                  Transform.translate(
                    offset: Offset(390 * (1 - slide), 0),
                    child: const _NormMock(),
                  ),
                  _finger(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reaches in, presses the Santaupų norma row, and withdraws once the detail
  /// screen is up. Its y comes from [_normRowCentre], not a copied number.
  Widget _finger() {
    final opacity = t < 0.10
        ? 0.0
        : t < 0.22
            ? (t - 0.10) / 0.12
            : t < 0.55
                ? 1.0
                : t < 0.62
                    ? 1 - (t - 0.55) / 0.07
                    : 0.0;
    if (opacity <= 0) return const SizedBox.shrink();

    final approach = 1 - Curves.easeOutCubic.transform(((t - 0.10) / 0.12).clamp(0.0, 1.0));
    final press = t > 0.42 && t < 0.50 ? 0.82 : 1.0;

    return Positioned(
      left: 190,
      top: _normRowCentre - 15,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(approach * 20, approach * 30),
          child: Transform.scale(
            scale: press,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 1.5),
                gradient: const RadialGradient(
                  center: Alignment(-0.32, -0.4),
                  colors: [Color(0xE6FFFFFF), Color(0x47FFFFFF), Color(0x00FFFFFF)],
                  stops: [0, 0.46, 0.7],
                ),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF0A1432).withValues(alpha: 0.3),
                      blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── screen 1: Apžvalga ───────────────────────────────────────────────────────

class _OverviewMock extends StatelessWidget {
  const _OverviewMock({required this.lit});

  /// Whether the Santaupų norma row is showing its pressed state.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 390,
      height: 844,
      color: const Color(0xFFEFF1F5),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 54),
          const SizedBox(
            height: 38,
            child: Row(
              children: [
                Text('Apžvalga',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.7)),
                Spacer(),
                Icon(Icons.remove_red_eye_outlined, size: 20, color: _ink),
                SizedBox(width: 13),
                Icon(Icons.search_rounded, size: 20, color: _ink),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: Row(
              children: [
                _chip(Icons.calendar_today_rounded, 'Šis mėnuo'),
                const SizedBox(width: 9),
                _chip(Icons.tune_rounded, 'Filtras'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: _ringH,
            child: Row(
              children: [
                Expanded(child: _ring(spend: true)),
                const SizedBox(width: 12),
                Expanded(child: _ring(spend: false)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _plainRow('Liepos suma', '−${_eur(_spend)}'),
          const SizedBox(height: 10),
          _normRow(),
          const SizedBox(height: 13),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              children: [
                Text('Kategorija', style: TextStyle(fontSize: 12, color: _dim, fontWeight: FontWeight.w600)),
                Spacer(),
                Text('Suma', style: TextStyle(fontSize: 12, color: _brand, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Column(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) Container(height: 1, color: const Color(0xFFEDEFF4)),
                  _catRow(_cats[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11)),
        child: Row(
          children: [
            Icon(icon, size: 13, color: _brand),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink)),
          ],
        ),
      );

  // StackFit.expand is the whole point: without it the Stack sizes to the label
  // column and the ring gets painted into an 85pt box instead of the full cell.
  Widget _ring({required bool spend}) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          CustomPaint(painter: _DonutPainter(spend: spend)),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(spend ? '−' : '+',
                  style: const TextStyle(fontSize: 14, color: _dim, fontWeight: FontWeight.w600, height: 1)),
              Text(spend ? _round(_spend) : _round(_income),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink, height: 1.25)),
              Text(spend ? 'Išleista' : 'Gauta',
                  style: const TextStyle(fontSize: 11.5, color: _dim, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      );

  Widget _plainRow(String k, String v) => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
        child: Row(
          children: [
            Text(k, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      );

  /// The tap target. Its height and the paddings above it put its centre at
  /// y=399, which is where the finger is placed.
  Widget _normRow() => Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: lit ? const Color(0xFFE6EEFF) : Colors.white,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFE6EEFF), borderRadius: BorderRadius.circular(9)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium_rounded, size: 11, color: _brand),
                  const SizedBox(width: 4),
                  Text('$_rate %',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _brand)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text('Santaupų norma',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            Text(_eur(_saved), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF9AA6BC)),
          ],
        ),
      );

  /// Icons rather than plain colour discs — the disc alone said nothing about
  /// which category it was.
  Widget _catRow(_Cat c) => SizedBox(
        height: 50,
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: c.color, shape: BoxShape.circle),
              child: Icon(c.icon, size: 15, color: Colors.white),
            ),
            const SizedBox(width: 11),
            Text(c.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
            const Spacer(),
            Text('−${_eur(c.amount)}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      );
}

/// The spend ring is the category split; the income ring is a single sweep.
class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.spend});
  final bool spend;

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    const stroke = 14.0;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: d - stroke, height: d - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    if (!spend) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = const Color(0xFF6E7687));
      return;
    }

    var start = -math.pi / 2;
    for (final c in _cats) {
      final sweep = (c.amount / _spend) * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, paint..color = c.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.spend != spend;
}

// ── screen 2: Santaupų norma ─────────────────────────────────────────────────

class _NormMock extends StatelessWidget {
  const _NormMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 390,
      height: 844,
      color: const Color(0xFFEFF1F5),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 54),
          const Row(
            children: [
              Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: _ink),
              SizedBox(width: 11),
              Text('Santaupų norma',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.5)),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: const Color(0xFFE3ECFF), borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.savings_rounded, size: 16, color: _brand),
                    SizedBox(width: 8),
                    Text('Kas tai?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
                  ],
                ),
                const SizedBox(height: 9),
                const Text('Santaupų norma rodo, kokią dalį gautų pajamų per mėnesį NEišleidai.',
                    style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF2A3854))),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: const Text('(pajamos − išlaidos) ÷ pajamos',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _brand)),
                ),
                const SizedBox(height: 9),
                Text(
                  'Liepą gavai ${_income.round()} €, išleidai ${_spend.round()} € → norma $_rate %. '
                  'Kuo didesnė, tuo daugiau atsidedi. Neblogas tikslas — 20 % ar daugiau.',
                  style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF2A3854)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Liepos pajamos', style: TextStyle(fontSize: 12, color: _dim, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    _figure(Icons.add_rounded, _eur(_income)),
                    const SizedBox(height: 11),
                    const Text('Liepos santaupos', style: TextStyle(fontSize: 12, color: _dim, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    _figure(Icons.savings_rounded, _eur(_saved)),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Santaupų norma',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
                    const SizedBox(height: 3),
                    Text('$_rate %',
                        style: const TextStyle(fontSize: 33, fontWeight: FontWeight.w800, color: _brand, height: 1.1)),
                    const Text('santaupos / pajamos',
                        style: TextStyle(fontSize: 11, color: _dim, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 13),
          const Padding(
            padding: EdgeInsets.only(left: 3, bottom: 7),
            child: Text('Praėjusio mėn. statusas',
                style: TextStyle(fontSize: 12, color: _dim, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Birželio santaupų klubas',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
                    SizedBox(height: 4),
                    Text('21 % — virš 20 % tikslo',
                        style: TextStyle(fontSize: 11.5, color: _dim, fontWeight: FontWeight.w600)),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(color: _brand, shape: BoxShape.circle),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('21', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                      Text('% klubas', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFDCE7FF))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 13),
          Padding(
            padding: const EdgeInsets.only(left: 3, bottom: 7),
            child: Text('Paskutinių 6 mėn. normos · vidurkis ${_avg.toStringAsFixed(1).replaceAll('.', ',')} %',
                style: const TextStyle(fontSize: 12, color: _dim, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in _months)
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${m.$2} %',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: m == _months.last ? _brand : _ink)),
                        const SizedBox(height: 5),
                        // heights are computed off the peak, not measured at
                        // layout time, so they land the same everywhere
                        Container(
                          width: 15,
                          height: m.$2 / _peak * 92,
                          decoration: BoxDecoration(
                            color: m == _months.last ? const Color(0xFF1E4FD8) : _brand,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(m.$1, style: const TextStyle(fontSize: 10, color: _dim, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _figure(IconData icon, String text) => Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: _brand, shape: BoxShape.circle),
            child: Icon(icon, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        ],
      );
}

// ── ground ───────────────────────────────────────────────────────────────────

/// White above, blue below, parted by a shallow arc. The seam sits lower than
/// on page 1 because the phone here is taller.
class _ArcGround extends CustomPainter {
  const _ArcGround();

  static const _seam = 0.37;   // where the arc's edge crosses, as a fraction
  static const _peakLift = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBFDFF));

    final edge = size.height * _seam;
    final lift = size.height * _peakLift;
    final path = Path()
      ..moveTo(0, edge)
      ..quadraticBezierTo(size.width / 2, edge - lift * 2, size.width, edge)
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
