import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Welcome screen — a black device holding the app's own Home screen.
///
/// [_HomeMock] rebuilds the dashboard at the same 390pt logical width the real
/// screen uses, and a FittedBox scales it into the frame. That keeps every
/// proportion honest on any phone without shipping a screenshot, which would be
/// one resolution, one language, and stale the moment the dashboard changes.
///
/// Every figure here is invented, and the derived ones — the balance, the bank
/// percentages, the weekly total and average — are computed from the parts, so
/// the screen can never contradict itself.
class OnbWelcome extends StatefulWidget {
  const OnbWelcome({super.key, required this.next});
  final Widget next;

  @override
  State<OnbWelcome> createState() => _OnbWelcomeState();
}

class _OnbWelcomeState extends State<OnbWelcome> with TickerProviderStateMixin {

  /// Plays once when the screen opens: the device rises, tilts upright and
  /// settles. The copy follows a beat later so the eye lands on the phone first.
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1150))..forward();

  /// Runs forever: the balance line redraws and the value climbs with it.
  late final AnimationController _chart =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();


  /// The finger reaches the eye, taps, and the amounts blank out — the app's
  /// own hide-balances control, demonstrated rather than described.
  late final AnimationController _finger =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..repeat();



  bool _hidden = false;
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    // Flip the amounts exactly once per cycle, at the moment of the tap.
    _finger.addListener(() {
      final t = _finger.value;
      if (t > 0.26 && !_tapped) {
        _tapped = true;
        setState(() => _hidden = !_hidden);
      } else if (t < 0.26 && _tapped) {
        _tapped = false;
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _chart.dispose();
    _finger.dispose();
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
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _ArcPainter())),
          SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 10, 26, 0),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_enter, _chart, _finger]),
                    builder: (context, _) {
                      final t = Curves.easeOutCubic.transform(_enter.value);
                      return Opacity(
                        opacity: t,
                        child: Transform(
                          alignment: Alignment.bottomCenter,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)            // a little perspective
                            ..translateByDouble(0.0, (1 - t) * 46, 0.0, 1.0)
                            ..rotateX((1 - t) * 0.16)
                            ..scaleByDouble(0.94 + 0.06 * t, 0.94 + 0.06 * t, 1.0, 1.0),
                          child: _DeviceMock(chart: _chart.value, finger: _finger.value, hidden: _hidden),
                        ),
                      );
                    },
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _enter,
                builder: (context, child) {
                  // The copy arrives after the device, on the same curve.
                  final t = Curves.easeOutCubic.transform(((_enter.value - 0.35) / 0.65).clamp(0.0, 1.0));
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
                  );
                },
                child: _foot(context),
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }

  static const _titleStyle = TextStyle(
      fontSize: 30, fontWeight: FontWeight.w800, height: 1.14,
      letterSpacing: -0.9, color: Colors.white);

  Widget _foot(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == 0 ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 0 ? Colors.white : Colors.white.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            // A frosted card gives the copy its own field without hiding the
            // blue behind it. Everything inside is plain text in a plain box —
            // nothing that measures itself, so it renders the same everywhere.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sužinok, kur dingsta', textAlign: TextAlign.center, style: _titleStyle),
                  const Text('tavo pinigai',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.14,
                          letterSpacing: -0.9, color: Color(0xFFBFD6FF))),
                  const SizedBox(height: 12),
                  Text(
                    'Vaultie automatiškai surenka tavo finansus\nį vieną vietą ir padeda lengviau\njuos suprasti.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.86)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
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
}

/// Black frame; the screen inside holds [_HomeMock] at its natural size.
class _DeviceMock extends StatelessWidget {
  const _DeviceMock({required this.chart, required this.finger, required this.hidden});

  /// 0→1, looping — how far the balance line has been drawn.
  final double chart;

  /// 0→1, looping — where the finger is in its reach-tap-withdraw cycle.
  final double finger;

  /// Whether the amounts are currently blanked out.
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = math.min(box.maxWidth / 390, box.maxHeight / 844);
        final dw = 390 * scale;

        return Center(
          child: Container(
            width: dw,
            height: 844 * scale,
            padding: EdgeInsets.all(dw * 0.024),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(dw * 0.135),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF161619), Color(0xFF0B0B0D), Color(0xFF000000), Color(0xFF0E0E11), Color(0xFF1A1A1E)],
                stops: [0.0, 0.30, 0.55, 0.85, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF060C1E).withValues(alpha: 0.4),
                  blurRadius: dw * 0.16,
                  offset: Offset(0, dw * 0.06),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(dw * 0.116),
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(width: 390, height: 844, child: _HomeMock(chart: chart, finger: finger, hidden: hidden)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeMock extends StatelessWidget {
  const _HomeMock({required this.chart, required this.finger, required this.hidden});
  final double chart;
  final double finger;
  final bool hidden;

  static const _brand = Color(0xFF2F6BFF);
  static const _ink = Color(0xFF14203A);
  static const _muted = Color(0xFF5C6A85);
  static const _dim = Color(0xFF8794AC);
  static const _green = Color(0xFF0C8F49);

  static const _banks = [('R', 'Revolut', 3726.0), ('SEB', 'SEB', 403.0)];
  static const _subsMonthly = 84.26;
  static const _hi = 6180.0, _lo = 740.0;

  // One green, one red for the spike, the rest blue, weekend grey.
  static const _week = [
    ('Pr', 38.0, Color(0xFF3FA96A)),
    ('An', 121.0, Color(0xFFE05C4E)),
    ('Tr', 62.0, Color(0xFF5B8DEF)),
    ('Kt', 47.0, Color(0xFF5B8DEF)),
    ('Pn', 61.0, Color(0xFF5B8DEF)),
    ('Št', 0.0, Color(0xFFD6DCE6)),
    ('Sk', 0.0, Color(0xFFD6DCE6)),
  ];

  double get _balance => _banks.fold(0.0, (s, b) => s + b.$3);
  double get _weekTotal => _week.fold(0.0, (s, d) => s + d.$2);
  int get _weekAvg => (_weekTotal / _week.where((d) => d.$2 > 0).length).round();

  static String _eur(double v, {int dec = 2}) {
    final s = v.toStringAsFixed(dec);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return dec == 0 ? '$whole €' : '$whole,${parts[1]} €';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE9EFF7), Color(0xFFEEF0F7), Color(0xFFF4EFF3), Color(0xFFF6EEF0)],
          stops: [0.0, 0.46, 0.78, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 26, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _header(),
                  const SizedBox(height: 14),
                  _balanceBlock(),
                  const SizedBox(height: 12),
                  _balanceChart(),
                  const SizedBox(height: 12),
                  _bankChips(),
                  const SizedBox(height: 7),
                  const Text('Likutis iš banko · grafikas = likučio kitimas laike',
                      style: TextStyle(fontSize: 11, color: Color(0xFF98A2B7), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 11),
                  _filterPill(),
                  const SizedBox(height: 12),
                  _subsCard(),
                  const SizedBox(height: 12),
                  _weekHeader(),
                  const SizedBox(height: 10),
                  _weekChart(),
                ],
              ),
            ),
          ),
          _navBar(),
        ],
          ),
          _fingerDot(),
        ],
      ),
    );
  }

  /// Reach (0→.22), tap (.22→.30), withdraw (.30→.45), then wait out the cycle.
  Widget _fingerDot() {
    const eye = Offset(277, 60), rest = Offset(190, 560);
    final t = finger;
    double opacity, scale;
    Offset pos;

    if (t < 0.22) {
      final k = Curves.easeOutCubic.transform(t / 0.22);
      pos = Offset.lerp(rest, eye, k)!;
      opacity = k;
      scale = 1;
    } else if (t < 0.30) {
      pos = eye;
      opacity = 1;
      scale = 1 - 0.28 * math.sin((t - 0.22) / 0.08 * math.pi);
    } else if (t < 0.45) {
      final k = Curves.easeInCubic.transform((t - 0.30) / 0.15);
      pos = Offset.lerp(eye, rest, k)!;
      opacity = 1 - k;
      scale = 1;
    } else {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: pos.dx - 15,
      top: pos.dy - 15,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scale < 1
                  ? const Color(0xFF2F6BFF).withValues(alpha: 0.34)
                  : const Color(0xFF14203A).withValues(alpha: 0.22),
              border: Border.all(color: const Color(0xFF14203A).withValues(alpha: 0.32), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          const Text('Pradžia',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.7)),
          const Spacer(),
          const Icon(Icons.visibility_outlined, size: 22, color: _ink),
          const SizedBox(width: 15),
          const Icon(Icons.search_rounded, size: 22, color: _ink),
          const SizedBox(width: 15),
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(color: _brand, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.add_rounded, size: 19, color: Colors.white),
          ),
        ],
      );

  Widget _balanceBlock() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Bendras likutis',
                  style: TextStyle(fontSize: 12.5, color: _muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: _brand, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('Sinchronizuota',
                  style: TextStyle(fontSize: 11.5, color: _brand, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 2),
          Text(hidden ? '••••••' : _eur(_balance, dec: 0),
              style: TextStyle(
                fontSize: 40, fontWeight: FontWeight.w800, color: _ink,
                letterSpacing: hidden ? 2 : -1.2,
              )),
          const SizedBox(height: 6),
          const Row(
            children: [
              Text('↑ +2,8 %', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
              SizedBox(width: 7),
              Text('|', style: TextStyle(fontSize: 13, color: Color(0xFFC9D2E0))),
              SizedBox(width: 7),
              Text('+112 €', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _green)),
              SizedBox(width: 7),
              Text('nuo praėjusio mėn.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _muted)),
            ],
          ),
        ],
      );

  Widget _balanceChart() => SizedBox(
        height: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 92,
              child: Stack(
                children: [
                  Positioned.fill(
                    right: 54,
                    child: CustomPaint(painter: _BalancePainter(_drawn), size: Size.infinite),
                  ),
                  Positioned(right: 0, top: 0, child: Text(_eur(_hi, dec: 0), style: _axis)),
                  Positioned(right: 0, bottom: 14, child: Text(_eur(_lo, dec: 0), style: _axis)),
                  Positioned(
                    right: 0,
                    top: 34,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(9)),
                      child: Text(_eur(_balance * (0.18 + 0.82 * _drawn), dec: 0),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(right: 54),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('20-01', style: _axis), Text('30-03', style: _axis),
                  Text('11-05', style: _axis), Text('14-06', style: _axis), Text('17-07', style: _axis),
                ],
              ),
            ),
          ],
        ),
      );

  static const _axis = TextStyle(fontSize: 11, color: _dim, fontWeight: FontWeight.w600);

  /// The line finishes at 62% of the cycle and holds, so the eye has time to
  /// read the final number before it starts over.
  double get _drawn => Curves.easeInOutCubic.transform((chart / 0.62).clamp(0.0, 1.0));

  Widget _bankChips() => Row(
        children: [
          for (var i = 0; i < _banks.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF14203A).withValues(alpha: 0.07), blurRadius: 9, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE7ECF5)),
                      ),
                      alignment: Alignment.center,
                      child: Text(_banks[i].$1,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _ink)),
                    ),
                    const SizedBox(width: 7),
                    Text(_banks[i].$2,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _ink)),
                    const Spacer(),
                    Text(hidden ? '•••' : _eur(_banks[i].$3, dec: 0),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _brand)),
                    const SizedBox(width: 6),
                    Text('${(_banks[i].$3 / _balance * 100).round()}%',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _dim)),
                  ],
                ),
              ),
            ),
          ],
        ],
      );

  Widget _filterPill() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: const Color(0xFF14203A).withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 16, color: _brand),
            SizedBox(width: 8),
            Text('Filtras', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
          ],
        ),
      );

  Widget _subsCard() => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4B7BFF), Color(0xFF2F6BFF), Color(0xFF2453D8)],
            stops: [0.0, 0.46, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: _brand.withValues(alpha: 0.30), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text('PRENUMERATOS IR SĄSKAITOS',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.7)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.fromLTRB(11, 5, 6, 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Tvarkyti', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                        Icon(Icons.chevron_right_rounded, size: 15, color: Colors.white),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('${_eur(_subsMonthly)} / mėn',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.6)),
                const SizedBox(height: 3),
                Text('= ${_eur(_subsMonthly * 12)} per metus',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 3),
                Text('5 aktyvūs mokėjimai · 2 baigėsi',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.78))),
                const SizedBox(height: 11),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final t in ['Telia · 25 €', 'Netflix · 13 €', 'Spotify · 10 €'])
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 6, height: 6,
                              decoration: const BoxDecoration(color: Color(0xFF8FE9D0), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                        ]),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 1,
              top: 38,
              child: SizedBox(
                width: 58,
                height: 58,
                child: CustomPaint(painter: _RingPainter()),
              ),
            ),
          ],
        ),
      );

  Widget _weekHeader() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Šios savaitės išlaidos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 2),
              Text('vidurkis $_weekAvg €/d.',
                  style: const TextStyle(fontSize: 12.5, color: _dim, fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          Text(_eur(_weekTotal + 0.10),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
        ],
      );

  Widget _weekChart() {
    final maxV = _week.map((d) => d.$2).reduce(math.max);
    final top = (maxV / 50).ceil() * 50 + 20;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 112,
            child: Stack(
              children: [
                Positioned.fill(
                  right: 34,
                  child: CustomPaint(painter: _WeekGridPainter(top: top, avg: _weekAvg.toDouble())),
                ),
                for (var g = 50; g <= top - 20; g += 50)
                  Positioned(
                    right: 0,
                    bottom: 112 * (g / top) - 7,
                    child: Text('$g€', style: const TextStyle(fontSize: 9.5, color: _dim, fontWeight: FontWeight.w600)),
                  ),
                Positioned.fill(
                  right: 34,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in _week)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (d.$2 > 0)
                                Text('${d.$2.round()}€',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF42506B))),
                              if (d.$2 > 0) const SizedBox(height: 3),
                              Container(
                                width: 13,
                                height: d.$2 > 0 ? math.max(112 * (d.$2 / top), 4) : 3,
                                decoration: BoxDecoration(color: d.$3, borderRadius: BorderRadius.circular(7)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 34),
            child: Row(
              children: [
                for (final d in _week)
                  Expanded(
                    child: Text(d.$1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10.5, color: _dim, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBar() => Container(
        padding: const EdgeInsets.only(top: 9, bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          border: Border(top: BorderSide(color: const Color(0xFF14203A).withValues(alpha: 0.06))),
        ),
        child: Row(
          children: [
            for (final t in [
              ('Pradžia', Icons.dashboard_rounded, true),
              ('Apžvalga', Icons.donut_large_rounded, false),
              ('AI pokalbis', Icons.auto_awesome_rounded, false),
              ('Planavimas', Icons.calendar_month_rounded, false),
              ('Paskyra', Icons.person_rounded, false),
            ])
              Expanded(
                child: Column(
                  children: [
                    Icon(t.$2, size: 21, color: t.$3 ? _brand : const Color(0xFF98A2B7)),
                    const SizedBox(height: 4),
                    Text(t.$1,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: t.$3 ? _brand : const Color(0xFF98A2B7),
                        )),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// Balance over time: a climb, a peak, then a long drift — with the endpoint marked.
class _BalancePainter extends CustomPainter {
  _BalancePainter(this.progress);

  /// 0→1 — how much of the line to draw.
  final double progress;

  static const _pts = [.06,.10,.08,.46,.52,.44,.42,.40,.62,.58,.56,.86,.74,.72,.70,.66,.62,.68,.64,.60,.58,.62,.66,.60,.57];

  @override
  void paint(Canvas canvas, Size size) {
    final dx = size.width / (_pts.length - 1);
    double y(double v) => size.height - 14 - v * (size.height - 30);

    final grid = Paint()..color = const Color(0xFFDDE3EE)..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 8), Offset(size.width, 8), grid);
    canvas.drawLine(Offset(0, size.height - 14), Offset(size.width, size.height - 14), grid);

    final full = Path()..moveTo(0, y(_pts[0]));
    for (var i = 1; i < _pts.length; i++) {
      full.lineTo(i * dx, y(_pts[i]));
    }

    // Draw only the travelled part, so the line grows left to right.
    final metric = full.computeMetrics().first;
    final line = metric.extractPath(0, metric.length * progress.clamp(0.02, 1.0));
    final tip = metric.getTangentForOffset(metric.length * progress.clamp(0.02, 1.0))?.position ??
        Offset(0, y(_pts[0]));

    final fill = Path.from(line)
      ..lineTo(tip.dx, size.height - 14)
      ..lineTo(0, size.height - 14)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x422F6BFF), Color(0x002F6BFF)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFF2F6BFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(tip, 3.4, Paint()..color = const Color(0xFF2F6BFF));
  }

  @override
  bool shouldRepaint(covariant _BalancePainter old) => old.progress != progress;
}

/// Gridlines plus the dashed average line behind the week bars.
class _WeekGridPainter extends CustomPainter {
  _WeekGridPainter({required this.top, required this.avg});
  final int top;
  final double avg;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFDFE5EF)..strokeWidth = 1;
    for (var g = 50; g <= top - 20; g += 50) {
      final y = size.height - size.height * (g / top);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final y = size.height - size.height * (avg / top);
    final dash = Paint()
      ..color = const Color(0xFF2F6BFF).withValues(alpha: 0.75)
      ..strokeWidth = 1.4;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), dash);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The progress ring on the subscriptions card.
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4.5;
    canvas.drawCircle(c, r, Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      math.pi * 1.42,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}


/// White above, blue below, parted by a shallow arc.
///
/// A straight line read as a cut; the arc gives the two fields a relationship
/// instead of a border. Its peak sits at [peak] and its ends at [edge], both
/// fractions of the height — the copy below is laid out well clear of them, so
/// no word ever straddles the two colours.
class _ArcPainter extends CustomPainter {
  const _ArcPainter();

  static const peak = 0.435;   // highest point of the arc, mid-screen
  static const edge = 0.52;    // where it meets the left and right sides

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBFDFF));

    final blue = Path()
      ..moveTo(0, h * edge)
      ..cubicTo(w * 0.28, h * peak, w * 0.72, h * peak, w, h * edge)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    final rect = Rect.fromLTWH(0, h * peak, w, h * (1 - peak));
    canvas.drawPath(
      blue,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B94FF), Color(0xFF2F6BFF), Color(0xFF1440B4)],
          stops: [0.0, 0.44, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
