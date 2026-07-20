import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../i18n.dart';

/// The bank-connect call to action, shown after onboarding.
///
/// Copied from the reference. Colours sampled rather than guessed: the ground
/// is #FAFBFD above the arc and #013FE5 → #012FB1 below, the arc meets the
/// sides at 43.2 % of the height.
///
/// Two claims in the reference were changed, and neither for design reasons:
///
///  * "Vaultie … yra registruota mokėjimo įstaiga" — Vaultie holds no licence;
///    Enable Banking does, and the app operates under theirs. Claiming to be a
///    registered payment institution states a regulatory status the company
///    does not have, so the credit goes to the party that actually holds it.
///  * "užtrunka mažiau nei 60 sekundžių" — the app's own scan screen says
///    "Tai gali užtrukti iki minutės", and that is the scan alone, after the
///    bank's own login. A promise the product contradicts on the next screen
///    is worse than no promise, so the timing claim is gone.
class OnbConnect extends StatelessWidget {
  const OnbConnect({super.key, required this.next});

  /// Where "Prijungti banką" leads. Per the agreed order that is the sign-in:
  /// the bank callables all call `_require_auth`, so an account has to exist
  /// before the bank list can even be fetched.
  final Widget next;

  /// Last screen of the intro chain, so this is where the chain is recorded as
  /// walked — before navigating, so a user who never signs in still isn't shown
  /// the whole intro again on the next launch. Quitting mid-chain deliberately
  /// leaves the flag unset: an unfinished intro should resume from the start.
  Future<void> _finish(BuildContext context) async {
    await AppPrefs.setOnboarded(true);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  static const _ink = Color(0xFF0B1533);
  static const _sub = Color(0xFF4C5B7D);
  static const _paper = Color(0xFFFAFBFD);
  static const _blueTop = Color(0xFF013FE5);
  static const _blueBottom = Color(0xFF012FB1);
  static const _accent = Color(0xFF0435D0);
  static const _arcEdge = 0.432;

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
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(22 * s, 0, 22 * s, 16 * s),
                    child: Column(
                      children: [
                        SizedBox(height: 14 * s),
                        Container(
                          width: 56 * s,
                          height: 56 * s,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF1FC),
                            borderRadius: BorderRadius.circular(18 * s),
                          ),
                          child: Icon(Icons.account_balance_rounded,
                              size: 29 * s, color: _accent),
                        ),
                        SizedBox(height: 14 * s),
                        Text(
                          tr('Suprask savo\npinigus geriau'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28 * s, fontWeight: FontWeight.w800,
                              height: 1.15, letterSpacing: -0.9 * s, color: _ink),
                        ),
                        SizedBox(height: 12 * s),
                        Text(
                          tr('Prijunk banką ir Vaultie automatiškai\natras tai, ko nepastebi banko programėlė.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14 * s, height: 1.45, color: _sub),
                        ),
                        SizedBox(height: 16 * s),
                        _countCard(s),

                        SizedBox(height: 16 * s),
                        _point(s, Icons.lock_rounded, tr('Banko lygio saugumas'),
                            tr('Naudojame bankų lygio šifravimą ir laikomės aukščiausių ES saugumo standartų.')),
                        _divider(s),
                        _point(s, Icons.bolt_rounded, tr('Greitas prisijungimas'),
                            tr('Prisijungi savo banko puslapyje — taip pat, kaip įprastai.')),
                        _divider(s),
                        _point(s, Icons.person_outline_rounded, tr('Jūsų duomenys – jūsų kontrolėje'),
                            tr('Jūsų prisijungimo duomenys niekada nėra saugomi Vaultie.')),

                        SizedBox(height: 12 * s),
                        _regulated(s),

                        SizedBox(height: 16 * s),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _finish(context),
                          child: Container(
                            height: 58 * s,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16 * s),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF041A5E).withValues(alpha: 0.24),
                                    blurRadius: 18 * s, offset: Offset(0, 8 * s)),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(tr('Prijungti banką'),
                                    style: TextStyle(
                                        fontSize: 17 * s, fontWeight: FontWeight.w700, color: _accent)),
                                SizedBox(width: 10 * s),
                                Icon(Icons.arrow_forward_rounded, size: 19 * s, color: _accent),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 14 * s),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 12 * s,
                                color: Colors.white.withValues(alpha: 0.75)),
                            SizedBox(width: 6 * s),
                            Text(tr('Saugu. Patikima. Sukurta jums.'),
                                style: TextStyle(
                                    fontSize: 11.5 * s,
                                    color: Colors.white.withValues(alpha: 0.75))),
                          ],
                        ),
                        SizedBox(height: 3 * s),
                        Text(tr('Jūsų finansinė informacija yra visiškai apsaugota.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11.5 * s,
                                color: Colors.white.withValues(alpha: 0.65))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _countCard(double s) => Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 20 * s, vertical: 16 * s),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18 * s),
          boxShadow: [
            BoxShadow(color: const Color(0xFF0A2260).withValues(alpha: 0.08),
                blurRadius: 22 * s, offset: Offset(0, 8 * s)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_rounded, size: 34 * s, color: _accent),
            SizedBox(width: 14 * s),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('2500+ ${tr('bankų')}',
                    style: TextStyle(
                        fontSize: 24 * s, fontWeight: FontWeight.w800,
                        color: _ink, letterSpacing: -0.6 * s)),
                Text(tr('visoje Europoje'),
                    style: TextStyle(fontSize: 14 * s, color: _sub)),
              ],
            ),
          ],
        ),
      );

  Widget _point(double s, IconData icon, String title, String body) => Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42 * s,
              height: 42 * s,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, size: 20 * s, color: Colors.white),
            ),
            SizedBox(width: 14 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15 * s, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 2 * s),
                  Text(body,
                      style: TextStyle(
                          fontSize: 12 * s, height: 1.32,
                          color: Colors.white.withValues(alpha: 0.88))),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _divider(double s) => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.16),
      );

  /// The licence belongs to Enable Banking, and this says so.
  Widget _regulated(double s) => Container(
        padding: EdgeInsets.all(12 * s),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16 * s),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.stars_rounded, size: 30 * s, color: Colors.white),
            SizedBox(width: 13 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Reguliuojama ir licencijuota'),
                      style: TextStyle(
                          fontSize: 15 * s, fontWeight: FontWeight.w800, color: Colors.white)),
                  SizedBox(height: 3 * s),
                  Text(
                    tr('Prisijungimą vykdo licencijuota Enable Banking, veikianti pagal PSD2 direktyvą.'),
                    style: TextStyle(
                        fontSize: 12.5 * s, height: 1.35,
                        color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Ground extends CustomPainter {
  const _Ground();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = OnbConnect._paper);

    final edge = size.height * OnbConnect._arcEdge;
    final path = Path()
      ..moveTo(0, edge)
      ..quadraticBezierTo(size.width / 2, edge - size.height * 0.055, size.width, edge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [OnbConnect._blueTop, OnbConnect._blueBottom],
        ).createShader(Rect.fromLTWH(0, edge, size.width, size.height - edge)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
