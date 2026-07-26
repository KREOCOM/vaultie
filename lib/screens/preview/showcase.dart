import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../i18n.dart';

/// Which feature the phone in an onboarding scene is presenting.
enum ShowcaseKind { home, overview, chat, budget }

/// The screen shown inside the artwork's phone.
///
/// This is NOT the app's own dashboard shrunk to fit. The glass is about 37% of
/// the page width, so the real screens had to be squeezed to roughly 0.4 — which
/// turned 15pt body text into 6pt, and into 5pt on a narrow phone. Compensating
/// by scaling the UI up only traded one problem for another: it made the app
/// look like it has huge type, which it does not.
///
/// So this is a presentation of each feature, drawn at a size that survives the
/// reduction: one idea per screen, few rows, big numbers. The FIGURES and the
/// features are the app's own — the same demo month the rest of the onboarding
/// uses — only the layout is composed for being seen small.
class PhoneShowcase extends StatefulWidget {
  const PhoneShowcase({super.key, required this.kind});

  final ShowcaseKind kind;

  @override
  State<PhoneShowcase> createState() => _PhoneShowcaseState();
}

// The app's own light palette, so the phone in the scene and the app a person
// opens afterwards are recognisably the same product.
const _bg = Color(0xFFD6E1F5);
const _card = Color(0xFFEFF4FF);
const _ink = Color(0xFF14203A);
const _muted = Color(0xFF4A5878);
const _blue = Color(0xFF2F6BFF);
const _green = Color(0xFF12A150);
const _amber = Color(0xFFE9A21B);
const _violet = Color(0xFF8B5CF6);
const _rose = Color(0xFFE05563);

class _PhoneShowcaseState extends State<PhoneShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => _body(Curves.easeOutCubic.transform(_c.value)),
            ),
          ),
          _nav(),
        ],
      ),
    );
  }

  Widget _body(double t) {
    switch (widget.kind) {
      case ShowcaseKind.home:
        return _home(t);
      case ShowcaseKind.overview:
        return _overview(t);
      case ShowcaseKind.chat:
        return _chat(t);
      case ShowcaseKind.budget:
        return _budget(t);
    }
  }

  // ── Home: the one number, its shape over time, and the month's two totals ──
  Widget _home(double t) => _page(
        title: 'Pradžia',
        children: [
          Text(tr('Bendras likutis'),
              style: const TextStyle(fontSize: 19, color: _muted)),
          const SizedBox(height: 4),
          Text('${_eur(2397 * t)} €',
              style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.5,
                  color: _ink)),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.arrow_upward_rounded, size: 20, color: _green),
            const Text(' +3,6 %',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: _green)),
            Flexible(
              child: Text('   ${tr('nuo praėjusio mėn.')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, color: _muted)),
            ),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 108,
            child: CustomPaint(
                painter: _SparkPainter(t), size: const Size.fromHeight(108)),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: _tile(tr('Pajamos'), '2 700 €', _green,
                    Icons.south_west_rounded)),
            const SizedBox(width: 12),
            Expanded(
                child: _tile(tr('Išlaidos'), '1 836 €', _rose,
                    Icons.north_east_rounded)),
          ]),
          const SizedBox(height: 16),
          _row(Icons.shopping_cart_rounded, _green, 'Maisto prekės', '−34,20 €'),
          _row(Icons.local_cafe_rounded, _amber, 'Kavinė', '−4,80 €'),
          _row(Icons.home_rounded, _blue, 'Nuoma', '−620,00 €'),
          _row(Icons.local_gas_station_rounded, _rose, 'Degalai', '−52,40 €'),
        ],
      );

  // ── Overview: one donut, then where the money went ──
  Widget _overview(double t) {
    const cats = [
      ('Būstas', 620.0, _blue, Icons.home_rounded),
      ('Maistas', 450.3, _green, Icons.restaurant_rounded),
      ('Transportas', 213.2, _amber, Icons.directions_car_rounded),
      ('Pramogos', 198.4, _violet, Icons.movie_rounded),
    ];
    return _page(
      title: 'Apžvalga',
      children: [
        Center(
          child: SizedBox(
            width: 210,
            height: 210,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                  size: const Size(210, 210),
                  painter: _DonutPainter(
                      [for (final c in cats) (c.$2, c.$3)], t)),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Išleista'),
                    style: const TextStyle(fontSize: 18, color: _muted)),
                Text('${_eur(1836 * t)} €',
                    style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: _ink)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        for (final c in cats)
          _catRow(c.$4, c.$3, c.$1, c.$2, c.$2 / 1836 * 100, t),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: _card, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            // "Mėnesio rezultatas" plus a four-digit sum is 7.5px more than the
            // card is wide; the label gives way rather than the row bursting.
            Flexible(
              child: Text(tr('Mėnesio rezultatas'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, color: _muted)),
            ),
            const SizedBox(width: 10),
            const Spacer(),
            Text('+${_eur(864 * t)} €',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: _green)),
          ]),
        ),
      ],
    );
  }

  // ── Chat: a question and an answer, large enough to actually read ──
  Widget _chat(double t) => _page(
        title: 'AI pokalbis',
        children: [
          _bubble(tr('Kiek išleidau šį mėnesį?'), true, t, 0.0),
          _bubble(
              tr('1 836 € — 32 % mažiau nei uždirbai. Daugiausia būstui (620 €) ir maistui (450 €).'),
              false,
              t,
              0.25),
          _bubble(tr('Kur galėčiau sutaupyti?'), true, t, 0.55),
          _bubble(
              tr('Prenumeratos — 57,94 € per mėnesį, 695 € per metus. Dvi nenaudotos nuo balandžio.'),
              false,
              t,
              0.72),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Row(children: [
              Expanded(
                  child: Text(tr('Klausk apie savo finansus…'),
                      style: const TextStyle(fontSize: 19, color: _muted))),
              const Icon(Icons.arrow_upward_rounded, size: 24, color: _blue),
            ]),
          ),
        ],
      );

  // ── Subscriptions: the actual services, with what each costs and when it
  // is next taken. A second donut was here first — but page 4 already spends
  // its screen on one, and a donut cannot say "Netflix on the 14th".
  static const _subs = <(String, String, double, String)>[
    ('netflix', 'Netflix', 12.99, 'Liepos 14'),
    ('youtube', 'YouTube Premium', 11.99, 'Liepos 18'),
    ('spotify', 'Spotify', 10.99, 'Liepos 21'),
    ('hbo', 'HBO Max', 9.99, 'Liepos 25'),
    ('disney', 'Disney+', 8.99, 'Rugpjūčio 2'),
    ('icloud', 'iCloud+', 2.99, 'Rugpjūčio 5'),
  ];

  Widget _budget(double t) {
    const total = 57.94;
    return _page(
      title: 'Prenumeratos',
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Per mėnesį'),
                style: const TextStyle(fontSize: 19, color: _muted)),
            Text('${_eur2(total * t)} €',
                style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.4,
                    color: _ink)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20)),
            child: Text('6 ${tr('aktyvios')}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: _blue)),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${tr('Per metus')} ${_eur(total * 12)} €',
            style: const TextStyle(fontSize: 18, color: _muted)),
        const SizedBox(height: 16),
        for (var i = 0; i < _subs.length; i++)
          Opacity(
            opacity: ((t - i * 0.08) / 0.2).clamp(0.0, 1.0),
            child: _subRow(_subs[i]),
          ),
      ],
    );
  }

  Widget _subRow((String, String, double, String) s) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(13)),
            child: Image.asset('assets/logos/${s.$1}.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: _ink)),
                Text('${tr('kitas')} ${tr(s.$4)}',
                    style: const TextStyle(fontSize: 16, color: _muted)),
              ],
            ),
          ),
          Text('${_eur2(s.$3)} €',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
        ]),
      );

  // ── shared chrome ──────────────────────────────────────────────────────────

  Widget _page({required String title, required List<Widget> children}) =>
      Padding(
        // The scene hands us the render's own status-bar height as the top
        // inset; without honouring it the title sat under the notch.
        padding: EdgeInsets.fromLTRB(
            20, MediaQuery.paddingOf(context).top + 6, 20, 8),
        // Each scene's glass has its own aspect, so the same content has a few
        // pixels more or less room depending on the page. Rather than tune four
        // layouts to four heights — and re-tune them on every copy change — the
        // page shrinks by whatever it is over. A percent or two is invisible;
        // an overflow is content the person never sees.
        child: LayoutBuilder(
          builder: (ctx, box) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: box.maxWidth,
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(tr(title),
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: _ink)),
              const Spacer(),
              const Icon(Icons.remove_red_eye_outlined, size: 26, color: _ink),
              const SizedBox(width: 16),
              const Icon(Icons.search_rounded, size: 26, color: _ink),
            ]),
            const SizedBox(height: 14),
            ...children,
          ],
              ),
            ),
          ),
        ),
      );

  Widget _tile(String label, String value, Color c, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 6),
            Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, color: _muted))),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800, color: _ink)),
        ]),
      );

  Widget _row(IconData icon, Color c, String name, String amount) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, size: 22, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(tr(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w600, color: _ink))),
          Text(amount,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
        ]),
      );

  Widget _catRow(IconData icon, Color c, String name, double amount, double pct,
          double t) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 21, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(tr(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w600, color: _ink))),
          Text('${_eur(amount * t)} €',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(width: 10),
          SizedBox(
            width: 54,
            child: Text('${pct.round()} %',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 17, color: _muted)),
          ),
        ]),
      );

  Widget _bubble(String text, bool mine, double t, double at) {
    final o = ((t - at) / 0.2).clamp(0.0, 1.0);
    return Opacity(
      opacity: o,
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          constraints: const BoxConstraints(maxWidth: 250),
          decoration: BoxDecoration(
            color: mine ? _blue : _card,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 6),
              bottomRight: Radius.circular(mine ? 6 : 20),
            ),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 19,
                  height: 1.35,
                  color: mine ? Colors.white : _ink)),
        ),
      ),
    );
  }

  Widget _nav() {
    const items = [
      (Icons.dashboard_rounded, 'Pradžia', ShowcaseKind.home),
      (Icons.donut_large_rounded, 'Apžvalga', ShowcaseKind.overview),
      (Icons.auto_awesome_rounded, 'AI', ShowcaseKind.chat),
      (Icons.event_note_rounded, 'Planavimas', ShowcaseKind.budget),
      (Icons.person_outline_rounded, 'Paskyra', null),
    ];
    return Container(
      color: _card,
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Row(children: [
        for (final it in items)
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(it.$1,
                  size: 26,
                  color: it.$3 == widget.kind ? _blue : _muted),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tr(it.$2),
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: it.$3 == widget.kind ? _blue : _muted)),
              ),
            ]),
          ),
      ]),
    );
  }

  static String _eur2(double v) {
    final whole = v.floor();
    final cents = ((v - whole) * 100).round().toString().padLeft(2, '0');
    return '${_eur(whole.toDouble())},$cents';
  }

  static String _eur(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// The balance line, drawn left to right as the screen arrives.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t);
  final double t;

  static const _pts = <double>[
    0.42, 0.46, 0.40, 0.52, 0.48, 0.60, 0.55, 0.68, 0.62, 0.74,
    0.70, 0.66, 0.78, 0.72, 0.84, 0.80, 0.90, 0.86, 0.95, 1.0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    Offset at(int i) => Offset(
          i / (_pts.length - 1) * size.width,
          size.height - 8 - _pts[i] * (size.height - 22),
        );
    path.moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < _pts.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * t + 0.5, size.height));
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x332F6BFF), Color(0x002F6BFF)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _blue);
    canvas.restore();

    // The tip rides the end of the drawn line.
    final seg = (t * (_pts.length - 1)).clamp(0.0, _pts.length - 1.0);
    final i = seg.floor().clamp(0, _pts.length - 2);
    final a = at(i), b = at(i + 1);
    final tip =
        Offset(size.width * t, a.dy + (b.dy - a.dy) * (seg - i));
    canvas.drawCircle(tip, 7, Paint()..color = Colors.white);
    canvas.drawCircle(tip, 4.5, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}

/// One donut for the month, sweeping in.
class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.t);
  final List<(double, Color)> segments;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (s, e) => s + e.$1);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width / 2 - 14);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..color = Colors.white.withValues(alpha: 0.55));
    var start = -math.pi / 2;
    for (final s in segments) {
      final sweep = s.$1 / total * math.pi * 2 * t;
      canvas.drawArc(
          rect,
          start,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 26
            ..strokeCap = StrokeCap.butt
            ..color = s.$2);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t;
}
