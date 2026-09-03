import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';
import '../i18n.dart';
import 'splash_screen.dart';

/// The bank-connect call to action — the last screen of the intro chain.
///
/// 2026-08-19: rebuilt on a supplied reference mockup — a plain ambient
/// field (page7_bg.png) showing a bank tile, a shield/lock, and the Vaultie
/// tile connected by light streaks, with a two-tone headline and four
/// icon-square trust points below. Same reasoning as [OnbFeatures]: the
/// mockup's own copy is baked into its OWN separate render and isn't
/// reachable from code, so page7_bg.png is deliberately the EMPTY version,
/// supplied separately, and every word here is real Flutter text.
///
/// 2026-09-02: photo swapped for a new supplied render (same 853×1844 size,
/// same bank/shield/Vaultie-tile composition), and the four trust points
/// restyled to match OnbFeatures' card treatment — a bordered tile with an
/// icon square, staggered into place one at a time (alternating left/right)
/// rather than appearing all at once, for the same reason and via the same
/// mechanism (a single staggered AnimationController).
///
/// What is here stays checkable, same as before: the login happens on the
/// bank's own page (Open Banking / PSD2), the access is read-only, and the
/// data stays under the person's own control. Those are the things someone
/// wants to know before handing over a bank connection.
class OnbConnect extends StatefulWidget {
  const OnbConnect({super.key, required this.next});

  /// Where "Toliau" leads. Per the agreed order that is the sign-in: the
  /// bank calls all call `_require_auth`, so an account has to exist before
  /// the bank list can even be fetched.
  final Widget next;

  @override
  State<OnbConnect> createState() => _OnbConnectState();
}

class _OnbConnectState extends State<OnbConnect>
    with SingleTickerProviderStateMixin {
  static const _deep = Color(0xFF041038);

  static const _points = [
    (
      icon: Icons.person_outline_rounded,
      title: 'Tu kontroliuoji prieigą',
      sub: 'Tu nusprendi, kokius duomenis bendrinti ir kada atšaukti prieigą.',
    ),
    (
      icon: Icons.verified_user_outlined,
      title: 'Saugumas pirmoje vietoje',
      sub: 'Jungiamės per licencijuotą Open Banking infrastruktūrą pagal PSD2 standartą.',
    ),
    (
      icon: Icons.visibility_outlined,
      title: 'Tik skaitymo prieiga',
      sub: 'Mes galime tik skaityti tavo duomenis. Mokėjimų neatliekame.',
    ),
    (
      icon: Icons.lock_outline_rounded,
      title: 'Tavo duomenys – tavo nuosavybė',
      sub: 'Duomenys yra apsaugoti ir naudojami tik tavo Vaultie patirčiai pagerinti.',
    ),
  ];

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 500 + _points.length * 170),
  )..forward();

  /// Same staggering as OnbFeatures' own _cardAnim — see that widget's doc.
  Animation<double> _cardAnim(int i) {
    final total = _ctrl.duration!.inMilliseconds;
    final start = (i * 170) / total;
    final end = ((i * 170) + 500) / total;
    return CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start, end.clamp(start, 1.0), curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Last screen of the intro chain, so this is where the chain is recorded
  /// as walked — before navigating, so a user who never signs in still
  /// isn't shown the whole intro again on the next launch. Quitting
  /// mid-chain deliberately leaves the flag unset: an unfinished intro
  /// should resume from the start.
  Future<void> _finish(BuildContext context) async {
    // A firmer tick than the other pages' "Toliau" gets: this is the tap
    // that ends the intro and hands over to the sign-in.
    HapticFeedback.mediumImpact();
    await AppPrefs.setOnboarded(true);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => wrapOnbStatusBar(Scaffold(
        backgroundColor: _deep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(
                image: AssetImage('assets/onboarding/page7_bg.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      // The bank/shield/Vaultie tiles run roughly the top
                      // quarter of the render (measured the same way as the
                      // rest of the chain's full-bleed pages) — the copy
                      // starts clear of them, not on top of them. Bumped
                      // from 270 to 310 for the 2026-09-02 photo — its own
                      // reflection glow runs a little further down than the
                      // previous render's did, measured the same way.
                      padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 310),
                          // 2026-08-19 v2: the solid gradient card didn't fit
                          // this particular photo — plain text with a soft
                          // drop shadow instead, same as the rest of the
                          // chain.
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                height: 1.16,
                                letterSpacing: -0.6,
                                shadows: [
                                  Shadow(
                                      color: Color(0xB3000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 3)),
                                  Shadow(
                                      color: Color(0x66000000),
                                      blurRadius: 30),
                                ],
                              ),
                              children: [
                                TextSpan(
                                    text: tr('Prijunk savo '),
                                    style: const TextStyle(
                                        color: Colors.white)),
                                // 2026-09-04: one word per onboarding page
                                // picked out in the same blue gradient as
                                // page 1's "finansus" — see that page's own
                                // doc.
                                TextSpan(
                                    text: tr('banką\n'),
                                    style: TextStyle(
                                      foreground: Paint()
                                        ..shader = const LinearGradient(
                                          colors: [
                                            Color(0xFF7FB0FF),
                                            Color(0xFF0A4DFD)
                                          ],
                                        ).createShader(
                                            const Rect.fromLTWH(0, 0, 150, 30)),
                                    )),
                                TextSpan(
                                    text: tr('saugiai ir greitai'),
                                    style: const TextStyle(
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('Prisijunk prie banko per savo banko sistemą. Tavo prisijungimo duomenys lieka tik banke.'),
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                    color: Color(0xB3000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 2)),
                                Shadow(color: Color(0x66000000), blurRadius: 22),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          for (var i = 0; i < _points.length; i++) _card(i),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 16),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => _finish(context),
                          child: Container(
                            height: 54,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFF001450)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 22,
                                    offset: const Offset(0, 10)),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tr('Toliau'),
                                    style: const TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1846E6))),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 19, color: Color(0xFF1846E6)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 13,
                                color: Colors.white.withValues(alpha: 0.62)),
                            const SizedBox(width: 6),
                            Text(
                              tr('2 700+ bankų visoje Europoje'),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.62)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ));

  /// Card [i] slides in from the right on even indexes, from the left on
  /// odd ones — same mechanism as OnbFeatures' own `_card`, see its doc.
  Widget _card(int i) {
    final p = _points[i];
    final anim = _cardAnim(i);
    final fromRight = i.isEven;
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset((1 - anim.value) * (fromRight ? 48 : -48), 0),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3E63FF), Color(0xFF1B2E7A)],
                  ),
                ),
                child: Icon(p.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(p.title),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(tr(p.sub),
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.white.withValues(alpha: 0.65))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
