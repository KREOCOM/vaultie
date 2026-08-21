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
/// What is here stays checkable, same as before: the login happens on the
/// bank's own page (Open Banking / PSD2), the access is read-only, and the
/// data stays under the person's own control. Those are the things someone
/// wants to know before handing over a bank connection.
class OnbConnect extends StatelessWidget {
  const OnbConnect({super.key, required this.next});

  /// Where "Toliau" leads. Per the agreed order that is the sign-in: the
  /// bank calls all call `_require_auth`, so an account has to exist before
  /// the bank list can even be fetched.
  final Widget next;

  static const _deep = Color(0xFF041038);

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
        pageBuilder: (_, __, ___) => next,
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
                      // starts clear of them, not on top of them.
                      padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 270),
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
                                    text: tr('Prijunk savo banką\n'),
                                    style: const TextStyle(
                                        color: Colors.white)),
                                TextSpan(
                                    text: tr('saugiai ir greitai'),
                                    style: const TextStyle(
                                        color: Color(0xFF8FB2FF))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('Prisijunk prie banko per savo banko sistemą. Vaultie niekada nemato tavo prisijungimo duomenų.'),
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
                          _point(
                            Icons.person_outline_rounded,
                            tr('Tu kontroliuoji prieigą'),
                            tr('Tu nusprendi, kokius duomenis bendrinti ir kada atšaukti prieigą.'),
                          ),
                          _point(
                            Icons.verified_user_outlined,
                            tr('Saugumas pirmoje vietoje'),
                            tr('Jungiamės per licencijuotą Open Banking infrastruktūrą pagal PSD2 standartą.'),
                          ),
                          _point(
                            Icons.visibility_outlined,
                            tr('Tik skaitymo prieiga'),
                            tr('Mes galime tik skaityti tavo duomenis. Mokėjimų neatliekame.'),
                          ),
                          _point(
                            Icons.lock_outline_rounded,
                            tr('Tavo duomenys – tavo nuosavybė'),
                            tr('Duomenys yra apsaugoti ir naudojami tik tavo Vaultie patirčiai pagerinti.'),
                          ),
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

  Widget _point(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Icon(icon, size: 19, color: const Color(0xFF6E9CFF)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.68))),
                ],
              ),
            ),
          ],
        ),
      );
}
