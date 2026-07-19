import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';

/// Onboarding page 1 — the intro, copied from the reference design.
///
/// Colours were sampled from the reference rather than guessed: the ground is
/// #FDFDFE above the arc and a #0045D5 → #0137BE gradient below it, the arc
/// meets the sides at 37.1 % of the height, the headline is #061439 and the
/// subhead #8C91AB.
///
/// The bank tiles rotate. Only logos that actually exist in assets/logos are
/// used — a brand mark cannot be invented, so adding Santander, DNB or N26 is
/// a matter of dropping the PNG in and adding one line to [_pool].
class OnbIntro extends StatefulWidget {
  const OnbIntro({super.key, required this.next});
  final Widget next;

  @override
  State<OnbIntro> createState() => _OnbIntroState();
}

const _ink = Color(0xFF061439);
/// The subhead. Blue rather than the reference's grey, which only reached
/// 3.06:1 on this near-white ground; this clears AA at 5.72:1.
const _subtitle = Color(0xFF2F5BD8);
const _blueTop = Color(0xFF0045D5);
const _blueBottom = Color(0xFF0137BE);
const _accent = Color(0xFF1146F0);
const _paper = Color(0xFFFDFDFE);

/// Where the arc meets the left and right edges, as a fraction of the height.
const _arcEdge = 0.371;

class _Bank {
  const _Bank(this.name, this.asset);
  final String name;
  final String asset;
}

/// Every one of these is a real file in assets/logos. These eight are all the
/// financial marks the project has — the rest of that folder is subscription
/// brands (Netflix, Spotify, Maxima…). Reaching thirty means adding thirty
/// PNGs; a bank's mark cannot be drawn from memory.
const _pool = <_Bank>[
  _Bank('Swedbank', 'swedbank'),
  _Bank('SEB', 'seb'),
  _Bank('Luminor', 'luminor'),
  _Bank('Revolut', 'revolut'),
  _Bank('Citadele', 'citadele'),
  _Bank('Paysera', 'paysera'),
  _Bank('Wise', 'wise'),
  _Bank('Inbank', 'inbank'),
];

/// How many tiles the row shows.
const _slots = 6;

class _OnbIntroState extends State<OnbIntro> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  /// Types the subhead out once, left to right, then stops. No repeat: a line
  /// that keeps retyping itself reads as a glitch rather than as writing.
  ///
  /// 2.4 s across ~62 characters is about 26 a second — brisk, the pace of
  /// someone typing quickly. At 1.3 s it was nearer 48 a second, which stopped
  /// reading as typing and just looked like the text was being wiped in.
  late final AnimationController _type =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  /// One tile changes every 0.6 s, moving along the row.
  ///
  /// Swapping all six at once at this speed reads as flicker rather than
  /// rotation — nothing stays on screen long enough to be recognised. Changing
  /// one at a time gives the same ~33 logo changes across twenty seconds while
  /// the row still looks calm.
  Timer? _tick;

  /// Which bank each slot currently shows.
  late final List<int> _shown = List.generate(_slots, (i) => i % _pool.length);
  int _cursor = 0;
  int _nextBank = _slots;

  @override
  void initState() {
    super.initState();
    // starts as the page opens, just behind the fade so the first letters are
    // not written onto an invisible screen
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _type.forward();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (!mounted) return;
      setState(() {
        _shown[_cursor] = _nextBank % _pool.length;
        _cursor = (_cursor + 1) % _slots;
        _nextBank++;
      });
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _enter.dispose();
    _type.dispose();
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
      backgroundColor: _paper,
      body: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxHeight / 844;
          return Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: _Ground())),
              Positioned.fill(
                child: SafeArea(
                  child: AnimatedBuilder(
                    animation: _enter,
                    builder: (context, child) {
                      final t = Curves.easeOutCubic.transform(_enter.value);
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
                      );
                    },
                    child: _content(context, s),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, double s) => Padding(
        padding: EdgeInsets.fromLTRB(20 * s, 14 * s, 20 * s, 20 * s),
        child: Column(
          children: [
            SizedBox(height: 18 * s),
            Text(
              tr('Geriau suprask\nsavo pinigus'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 30 * s, fontWeight: FontWeight.w800, height: 1.16,
                  letterSpacing: -0.9 * s, color: _ink),
            ),
            SizedBox(height: 14 * s),
            _typedSubhead(s),
            SizedBox(height: 20 * s),

            // globe + the count card, the globe overlapping its top edge
            // The card is the Stack's non-positioned child, so the Stack takes
            // its height instead of a number I have to keep in step — the
            // hand-set 158 was 4pt short and clipped the card's bottom corners.
            // clipBehavior none lets the globe hang above the top edge.
            SizedBox(
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 26 * s),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(18 * s, 30 * s, 18 * s, 18 * s),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22 * s),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF0A2260).withValues(alpha: 0.10),
                              blurRadius: 26 * s, offset: Offset(0, 10 * s)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(tr('Prisijungimai prie'),
                              style: TextStyle(fontSize: 14.5 * s, color: const Color(0xFF5C6A85))),
                          SizedBox(height: 2 * s),
                          Text('2500+ ${tr('bankų')}',
                              style: TextStyle(
                                  fontSize: 28 * s, fontWeight: FontWeight.w800,
                                  color: _accent, letterSpacing: -0.8 * s)),
                          SizedBox(height: 2 * s),
                          Text(tr('visoje Europoje'),
                              style: TextStyle(fontSize: 14.5 * s, color: const Color(0xFF5C6A85))),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 50 * s,
                    height: 50 * s,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0xFFE8EEFC), shape: BoxShape.circle),
                    child: Icon(Icons.public_rounded, size: 25 * s, color: _accent),
                  ),
                ],
              ),
            ),

            SizedBox(height: 18 * s),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('Populiariausi bankai'),
                  style: TextStyle(fontSize: 14 * s, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            SizedBox(height: 12 * s),
            _banks(s),

            SizedBox(height: 20 * s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52 * s,
                  height: 52 * s,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: Icon(Icons.shield_rounded, size: 25 * s, color: Colors.white),
                ),
                SizedBox(width: 14 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Jūsų pasitikėjimas mums svarbiausias'),
                          style: TextStyle(
                              fontSize: 15.5 * s, fontWeight: FontWeight.w800, color: Colors.white)),
                      SizedBox(height: 6 * s),
                      Text(
                        tr('Naudojame bankų lygio saugumą, esame licencijuoti ir atitinkame visus ES standartus.'),
                        style: TextStyle(
                            fontSize: 12.5 * s, height: 1.4,
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(height: 16 * s),
            _trustRow(s),

            const Spacer(),
            _dots(s),
            SizedBox(height: 18 * s),
            GestureDetector(
              onTap: () => _start(context),
              child: Container(
                height: 54 * s,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16 * s),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF041A5E).withValues(alpha: 0.22),
                        blurRadius: 18 * s, offset: Offset(0, 8 * s)),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(tr('Pradėti'),
                    style: TextStyle(
                        fontSize: 16.5 * s, fontWeight: FontWeight.w700, color: const Color(0xFF2950F8))),
              ),
            ),
          ],
        ),
      );

  /// The subhead, written out a letter at a time.
  ///
  /// A full invisible copy sits underneath to hold the height: without it the
  /// block grows from one line to two as the text arrives and everything below
  /// jumps down mid-animation.
  Widget _typedSubhead(double s) {
    final full = tr('Stebėk išlaidas, analizuok įpročius\nir atrask, kur gali sutaupyti.');
    final style = TextStyle(fontSize: 15 * s, height: 1.45, color: _subtitle);

    return AnimatedBuilder(
      animation: _type,
      builder: (context, _) {
        final shown = full.substring(0, (full.length * _type.value).round());
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            Opacity(opacity: 0, child: Text(full, textAlign: TextAlign.center, style: style)),
            Text(shown, textAlign: TextAlign.center, style: style),
          ],
        );
      },
    );
  }

  /// Five tiles plus "and more". Each slot walks the pool at its own offset, so
  /// the row keeps changing without ever showing the same bank twice at once.
  Widget _banks(double s) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var slot = 0; slot < _slots; slot++) _tile(_pool[_shown[slot]], s),
        ],
      );

  Widget _tile(_Bank b, double s) => SizedBox(
        width: 48 * s,
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              child: Container(
                key: ValueKey(b.asset),
                width: 48 * s,
                height: 48 * s,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15 * s),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset('assets/logos/${b.asset}.png', fit: BoxFit.cover),
              ),
            ),
            SizedBox(height: 7 * s),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              child: Text(b.name,
                  key: ValueKey(b.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5 * s, color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _trustRow(double s) => Row(
        children: [
          _trust(Icons.verified_user_outlined, tr('Bankų lygio\napsauga'), s),
          _sep(s),
          _trust(Icons.description_outlined, tr('Licencijuoti\nES'), s),
          _sep(s),
          _trust(Icons.stars_rounded, tr('Atitinka PSD2\nreglamentą'), s),
        ],
      );

  Widget _trust(IconData icon, String label, double s) => Expanded(
        child: Row(
          children: [
            Icon(icon, size: 19 * s, color: Colors.white),
            SizedBox(width: 7 * s),
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 10.5 * s, height: 1.25, color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _sep(double s) => Container(
        width: 1,
        height: 30 * s,
        color: Colors.white.withValues(alpha: 0.28),
        margin: EdgeInsets.symmetric(horizontal: 6 * s),
      );

  Widget _dots(double s) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 3 * s),
              width: (i == 0 ? 20 : 6) * s,
              height: 6 * s,
              decoration: BoxDecoration(
                color: i == 0 ? Colors.white : Colors.white.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(6 * s),
              ),
            ),
        ],
      );
}

/// White above, blue below, parted by a shallow arc that meets the sides at
/// [_arcEdge] and rises in the middle — the shape in the reference.
class _Ground extends CustomPainter {
  const _Ground();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);

    final edge = size.height * _arcEdge;
    final path = Path()
      ..moveTo(0, edge)
      ..quadraticBezierTo(size.width / 2, edge - size.height * 0.052, size.width, edge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_blueTop, _blueBottom],
        ).createShader(Rect.fromLTWH(0, edge, size.width, size.height - edge)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
