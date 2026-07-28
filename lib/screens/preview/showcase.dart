import 'dart:async';
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

  /// Drives the home chart's continuous motion, separately from [_c].
  ///
  /// [_c] is a one-shot: it draws each screen in and stops. The chart needed to
  /// keep going — a line that rises once and then freezes reads as a picture of
  /// an app, not an app — so it gets its own repeating clock. Kept apart so the
  /// looping repaint touches the chart alone and not every widget on the page.
  late final AnimationController _live = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  /// Which half the subscriptions page is showing. Flipped on a timer so both
  /// halves get seen without the person having to do anything.
  bool _billsTab = false;
  Timer? _tabTimer;

  @override
  void initState() {
    super.initState();
    if (widget.kind == ShowcaseKind.budget) {
      // Long enough to read the subscriptions first, short enough that the bills
      // arrive before anyone taps "Toliau".
      _tabTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) setState(() => _billsTab = !_billsTab);
      });
    }
  }

  @override
  void dispose() {
    _tabTimer?.cancel();
    _c.dispose();
    _live.dispose();
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
          const SizedBox(height: 14),
          _bankChips(t),
          const SizedBox(height: 14),
          SizedBox(
            height: 108,
            child: AnimatedBuilder(
              animation: _live,
              builder: (_, __) => CustomPaint(
                painter: _LiveSparkPainter(draw: t, phase: _live.value),
                size: const Size.fromHeight(108),
              ),
            ),
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
        // Two rings, not one. The screen used to show only what was spent, which
        // is half a month: without the money that came IN, the figure below it
        // ("+864 €") had nothing to be the difference of. Side by side is also
        // how the app's own Apžvalga puts them.
        Row(children: [
          Expanded(
            child: _donut(
              value: 1836,
              label: 'Išleista',
              sign: '−',
              segments: [for (final c in cats) (c.$2, c.$3)],
              t: t,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _donut(
              value: 2700,
              label: 'Gauta',
              sign: '+',
              segments: const [(2380.0, _amber), (320.0, _violet)],
              t: t,
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
        const SizedBox(height: 14),
        for (final c in cats)
          _catRow(c.$4, c.$3, c.$1, c.$2, c.$2 / 1836 * 100, t),
        const SizedBox(height: 4),
        _months(t),
      ],
    );
  }

  /// One ring with its total in the middle.
  Widget _donut({
    required double value,
    required String label,
    required String sign,
    required List<(double, Color)> segments,
    required double t,
  }) =>
      AspectRatio(
        aspectRatio: 1,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
              size: Size.infinite, painter: _DonutPainter(segments, t)),
          // Confined to the hole. Left to the full width, "1 836 €" ran out over
          // the ring itself — the figure and the arc drawn on top of each other.
          // 0.62 is the inner diameter (1 − 2×thickness) with a margin.
          FractionallySizedBox(
            widthFactor: 0.62,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(sign,
                  style:
                      const TextStyle(fontSize: 19, height: 1, color: _muted)),
              const SizedBox(height: 2),
              FittedBox(
                child: Text('${_eur(value * t)} €',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: _ink)),
              ),
              FittedBox(
                child: Text(tr(label),
                    style: const TextStyle(fontSize: 16, color: _muted)),
              ),
            ]),
          ),
        ]),
      );

  /// Five months of spending, so the month on screen has something to be
  /// compared against — the empty strip under the categories was the only part
  /// of this screen carrying nothing.
  Widget _months(double t) {
    const data = [
      ('Lie', 1640.0, _violet),
      ('Rgp', 1910.0, _green),
      ('Rgs', 1720.0, _amber),
      ('Spa', 2050.0, _rose),
      ('Lap', 1836.0, _blue),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration:
          BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Paskutiniai 5 mėn.'),
            style: const TextStyle(fontSize: 17, color: _muted)),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: Stack(children: [
            // Guide lines behind the bars. Without them the columns floated at
            // arbitrary heights with nothing to be measured against, which is
            // what made them look scattered rather than compared.
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var g = 0; g < 3; g++)
                    Container(
                      height: 1,
                      color: _muted.withValues(alpha: g == 2 ? 0.35 : 0.14),
                    ),
                ],
              ),
            ),
            Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < data.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        child: Text(_eur(data[i].$2),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: i == data.length - 1 ? _ink : _muted)),
                      ),
                      const SizedBox(height: 5),
                      // Narrow and centred rather than filling the column: at
                      // full width these were five slabs, and slabs hide the very
                      // thing a bar chart is for.
                      //
                      // Height is scaled between 1 500 and 2 100 rather than from
                      // zero. Straight proportion put every month within nine
                      // pixels of the next — technically honest, visually flat —
                      // because no month is anywhere near zero.
                      Container(
                        width: 15,
                        height: (16 +
                                60 *
                                    ((data[i].$2 - 1500) / 600)
                                        .clamp(0.0, 1.0)) *
                            t,
                        decoration: BoxDecoration(
                          color: data[i].$3,
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(tr(data[i].$1),
                          style:
                              const TextStyle(fontSize: 15, color: _muted)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          ]),
        ),
      ]),
    );
  }

  // ── Chat: a question and an answer, large enough to actually read ──
  Widget _chat(double t) => _page(
        title: 'Tavo AI agentas',
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
    ('chatgpt', 'ChatGPT Plus', 22.99, 'Rugpjūčio 9'),
    ('strava', 'Strava', 5.99, 'Rugpjūčio 12'),
  ];

  /// The bills the app finds alongside the subscriptions — the other half of
  /// what "recurring" means, and the half with the big numbers in it.
  static const _bills = <(IconData, Color, String, double, String)>[
    (Icons.home_rounded, _blue, 'Nuoma', 620.00, 'Rugpjūčio 1'),
    (Icons.shield_rounded, _violet, 'Būsto draudimas', 18.50, 'Rugpjūčio 3'),
    (Icons.bolt_rounded, _amber, 'Elektra', 46.20, 'Rugpjūčio 8'),
    (Icons.wifi_rounded, _green, 'Internetas', 22.00, 'Rugpjūčio 10'),
    (Icons.phone_iphone_rounded, _rose, 'Mobilusis', 14.99, 'Rugpjūčio 12'),
    (Icons.water_drop_rounded, _blue, 'Vanduo', 12.40, 'Rugpjūčio 15'),
    (Icons.fitness_center_rounded, _green, 'Sporto klubas', 34.90, 'Rugpjūčio 18'),
    (Icons.directions_car_rounded, _amber, 'Automobilio draudimas', 27.30, 'Rugpjūčio 22'),
  ];

  /// Subscriptions, then bills, then back — the screen shows both halves of what
  /// the page promises instead of only the one that fitted.
  ///
  /// Rows no longer fade in one after another. That stagger meant the first
  /// fraction of a second on this page was a heading over nothing, which read as
  /// a different screen appearing first and then switching to this one.
  Widget _budget(double t) {
    final bills = _billsTab;
    final total = bills ? 796.29 : 86.92;
    return _page(
      title: bills ? 'Sąskaitos' : 'Prenumeratos',
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Per mėnesį'),
                style: const TextStyle(fontSize: 19, color: _muted)),
            Text('${_eur2(total * t)} €',
                style: const TextStyle(
                    fontSize: 38,
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
            child: Text(bills ? '8 ${tr('sąskaitos')}' : '8 ${tr('aktyvios')}',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: _blue)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('${tr('Per metus')} ${_eur(total * 12)} €',
            style: const TextStyle(fontSize: 18, color: _muted)),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: Column(
            key: ValueKey(bills),
            children: bills
                ? [for (final b in _bills) _billRow(b)]
                : [for (final s in _subs) _subRow(s)],
          ),
        ),
      ],
    );
  }

  Widget _billRow((IconData, Color, String, double, String) b) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: b.$2.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13)),
            child: Icon(b.$1, size: 24, color: b.$2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(b.$3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
                Text('${tr('kitas')} ${tr(b.$5)}',
                    style: const TextStyle(fontSize: 16, color: _muted)),
              ],
            ),
          ),
          Text('${_eur2(b.$4)} €',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
        ]),
      );

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
              // Flexible + scaleDown, not a plain Text: the titles used to be one
              // short word each ("Pradžia", "Apžvalga"), and "Tavo AI agentas"
              // plus the two icons is wider than the glass. It shrinks rather
              // than overflowing or being cut with an ellipsis.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(tr(title),
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: _ink)),
                ),
              ),
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

  /// The banks feeding this balance, as two chips under the number.
  ///
  /// Without them the figure is just a figure: nothing on the screen says it was
  /// pulled from real accounts rather than typed in. Real marks from
  /// `assets/logos/` — the same files the bank list uses — because a generic
  /// building glyph would undercut exactly the point being made.
  Widget _bankChips(double t) => Opacity(
        opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
        child: Row(children: [
          _bankChip('swedbank', 'Swedbank'),
          const SizedBox(width: 8),
          _bankChip('revolut', 'Revolut'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
                color: _card, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: _green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(tr('gyvai'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: _muted)),
            ]),
          ),
        ]),
      );

  Widget _bankChip(String asset, String name) => Container(
        padding: const EdgeInsets.fromLTRB(7, 6, 12, 6),
        decoration:
            BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset('assets/logos/$asset.png',
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 24)),
          ),
          const SizedBox(width: 7),
          Text(name,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        ]),
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
          // The share used to be muted grey at 17 and was the first thing to
          // disappear once the whole screen is shrunk into the artwork's glass.
          // Now it sits in a tinted chip in the category's own colour, which
          // both lifts it and ties the number to its ring segment.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('${pct.round()} %',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, color: c)),
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
/// The balance line, drawn once and then kept moving.
///
/// [draw] is the one-shot entry sweep (0 → 1). [phase] is a repeating 0 → 1 clock
/// that scrolls the curve leftwards for as long as the page is on screen, with a
/// euro figure riding the leading edge — so the chart reads as data still coming
/// in rather than a screenshot of a chart.
///
/// The curve is a sum of sines at WHOLE-number frequencies, sampled over exactly
/// one period. That is the whole trick behind the loop: at `phase == 1` every
/// sample is identical to `phase == 0`, so it repeats forever with no jump — no
/// duplicated buffer of points, no seam to hide.
class _LiveSparkPainter extends CustomPainter {
  _LiveSparkPainter({required this.draw, required this.phase});

  final double draw;
  final double phase;

  /// Balance the leading edge swings around, in euro.
  static const _base = 2397.0;
  static const _swing = 46.0;

  static const _steps = 56;

  /// Height at [x] (0 → 1 across the chart), 0 at the floor, 1 at the ceiling.
  double _h(double x) {
    final u = x + phase;
    final w = 0.55 +
        0.20 * math.sin(2 * math.pi * u) +
        0.10 * math.sin(2 * math.pi * 2 * u + 1.2) +
        0.05 * math.sin(2 * math.pi * 3 * u + 2.4);
    // A gentle rise left-to-right, so the month still reads as trending up.
    return (w + 0.16 * x).clamp(0.04, 0.98);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const top = 34.0; // room for the value pill above the line
    final floor = size.height - 8;
    Offset at(int i) {
      final x = i / (_steps - 1);
      return Offset(x * size.width, floor - _h(x) * (floor - top));
    }

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < _steps; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * draw + 0.5, size.height));

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
          colors: [Color(0x3D2F6BFF), Color(0x002F6BFF)],
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

    // ── Leading edge ──
    // Stops at 76% of the width, not at the right edge. The scene page draws this
    // screen into the artwork's glass with `BoxFit.cover` and a hard clip, so the
    // outermost strip is cropped away — a tip parked at 100% took its value pill
    // over the edge with it, which is why the figure was missing rather than
    // merely small.
    final xt = (draw.clamp(0.0, 1.0)) * 0.76;
    final tip = Offset(size.width * xt, floor - _h(xt) * (floor - top));

    // A halo that breathes on the repeating clock, so the point stays alive even
    // once the line has finished drawing.
    final pulse = 0.5 + 0.5 * math.sin(2 * math.pi * phase * 3);
    canvas.drawCircle(tip, 9 + 5 * pulse,
        Paint()..color = _blue.withValues(alpha: 0.16 * (1 - pulse)));
    canvas.drawCircle(tip, 7, Paint()..color = Colors.white);
    canvas.drawCircle(tip, 4.5, Paint()..color = _blue);

    // ── The figure riding the edge ──
    // Tied to the curve's height, so the number and the line can never disagree.
    final value = _base + (_h(xt) - 0.55) * _swing * 10;
    final tp = TextPainter(
      text: TextSpan(
        // Same grouped formatting as every other figure on these screens. Sized
        // up to 22: the glass shrinks this whole screen to roughly 40%, and at 17
        // the figure was the smallest thing on the page by some way.
        text: '${_PhoneShowcaseState._eur(value)} €',
        style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pillW = tp.width + 18, pillH = tp.height + 10;
    // Kept inside the chart at both ends rather than sliding off with the tip.
    final pillX = (tip.dx - pillW / 2).clamp(0.0, size.width - pillW);
    final pillY = (tip.dy - pillH - 12).clamp(0.0, size.height - pillH);
    final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillW, pillH), const Radius.circular(9));
    canvas.drawRRect(pill, Paint()..color = _blue);
    tp.paint(canvas, Offset(pillX + 9, pillY + 5));
  }

  @override
  bool shouldRepaint(_LiveSparkPainter old) =>
      old.draw != draw || old.phase != phase;
}

/// One donut for the month, sweeping in.
class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.t);
  final List<(double, Color)> segments;
  final double t;

  /// Ring thickness as a share of the diameter.
  ///
  /// Was a flat 26px, set when this screen had ONE ring 210 wide. Splitting it
  /// into two rings roughly 135 wide left that 26 looking like a doughnut rather
  /// than a chart, and swallowed the hole the figure sits in. Proportional means
  /// it stays right whatever size the ring is given.
  static const thickness = 0.105;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (s, e) => s + e.$1);
    if (total <= 0) return;
    final w = size.width * thickness;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero), radius: size.width / 2 - w / 2 - 1);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
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
            ..strokeWidth = w
            ..strokeCap = StrokeCap.butt
            ..color = s.$2);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.t != t;
}
