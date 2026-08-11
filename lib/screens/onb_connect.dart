import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_prefs.dart';
import '../i18n.dart';
import 'splash_screen.dart';

/// The bank-connect call to action — the last screen of the intro chain.
///
/// Two claims from the original reference are deliberately NOT here, and not
/// for design reasons:
///
///  * "Vaultie … yra registruota mokėjimo įstaiga" — Vaultie holds no licence.
///    Enable Banking does, and the app operates under theirs, so the credit
///    goes to the party that actually holds it.
///  * "užtrunka mažiau nei 60 sekundžių" — the app's own scan screen says the
///    scan alone can take up to a minute, after the bank's own login. A promise
///    the product contradicts on the next screen is worse than no promise.
///
/// What is here is checkable: the login happens on the bank's own page, the
/// access is read-only, the licence is Enable Banking's, the consent runs 90
/// days, and the data stays on the device. Those are the things someone wants
/// to know before handing over a bank connection, so they get the room rather
/// than adjectives.
///
/// iOS and Android built from ONE shared shell (colours, gradients, `_point`
/// widget) but two different layout strategies below [build] — see the same
/// note on [OnbFeatures]. iOS keeps the build already submitted to App
/// Review (five short trust points, full-width artwork, a Spacer); Android
/// gets the artwork-height guarantee and the three-point copy it needed to
/// stop scrolling on shorter screens. Do not merge the two back together.
class OnbConnect extends StatefulWidget {
  const OnbConnect({super.key, required this.next});

  /// Where "Prijungti banką" leads. Per the agreed order that is the sign-in:
  /// the bank callables all call `_require_auth`, so an account has to exist
  /// before the bank list can even be fetched.
  final Widget next;

  @override
  State<OnbConnect> createState() => _OnbConnectState();
}

class _OnbConnectState extends State<OnbConnect> {
  static const _deep = Color(0xFF041038);

  /// Android only. Measured height of the copy block, the same way
  /// [OnbScenePage] measures it. A fixed cap on the artwork's height stopped
  /// it colliding with the copy, but a fixed cap can still leave less room
  /// than the trust points need on a short screen — the page scrolled
  /// instead of the artwork making way. Shrinking the artwork to whatever is
  /// left AFTER the copy's own measured height is the same guarantee
  /// [OnbScenePage] uses: the copy always gets the room it needs first.
  final GlobalKey _copyKey = GlobalKey();
  double? _copyH;

  void _measureCopy() {
    final box = _copyKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    if (_copyH != null && (_copyH! - h).abs() < 0.5) return;
    if (mounted) setState(() => _copyH = h);
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureCopy());
    }
    final auto = kOnbAutoAdvance;
    if (auto != null) {
      Future<void>.delayed(auto, () {
        if (mounted) _finish();
      });
    }
  }

  /// Last screen of the intro chain, so this is where the chain is recorded as
  /// walked — before navigating, so a user who never signs in still isn't shown
  /// the whole intro again on the next launch. Quitting mid-chain deliberately
  /// leaves the flag unset: an unfinished intro should resume from the start.
  Future<void> _finish() async {
    // A firmer tick than the "Toliau" pages get: this is the tap that ends the
    // intro and hands over to the sign-in, so it should not feel identical to
    // turning a page.
    HapticFeedback.mediumImpact();
    await AppPrefs.setOnboarded(true);
    if (!mounted) return;
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
  Widget build(BuildContext context) => wrapOnbStatusBar(
      Platform.isAndroid ? _buildAndroid(context) : _buildIOS(context));

  /// Unchanged from the build already submitted to App Review: full-width
  /// artwork, a Spacer pushing the copy to the bottom, five trust points. Do
  /// not "improve" this to match Android — it was never broken here.
  Widget _buildIOS(BuildContext context) {
    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The banks flowing into the phone — the one image on this page, and
          // the only thing on it that is not words. Its content sits in the top
          // half (21–52% of the render) and the rest is empty, so it is drawn
          // full width from the top and the copy takes the room below.
          //
          // The generated video that was here first is gone: its animation
          // dissolved the logos away to nothing, so most of the loop showed an
          // empty scene.
          Positioned(
            // Lifted by 8%: the render's top-left is empty floor, and drawn
            // from y=0 that corner read as a hole above the tiles.
            top: -MediaQuery.of(context).size.width * 1844 / 853 * 0.08,
            left: 0,
            right: 0,
            child: Image.asset('assets/onboarding/page7_scene.png',
                fit: BoxFit.fitWidth),
          ),

          // The render fades into the page before the copy starts, so its lower
          // edge is never a visible line.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00041038),
                      Color(0x00041038),
                      Color(0xCC041038),
                      _deep,
                    ],
                    stops: [0, 0.30, 0.44, 0.56],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B8CFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        tr('Prieigą\nkontroliuoji tu'),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.9,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _point(
                        Icons.account_balance_rounded,
                        'Pasirink, ką prijungti',
                        'Prijunk tik tas sąskaitas, kurias nori.',
                      ),
                      _point(
                        Icons.visibility_outlined,
                        'Tik skaitymo prieiga',
                        'Vaultie negali atlikti mokėjimų ar pervesti pinigų.',
                      ),
                      _point(
                        Icons.verified_user_outlined,
                        'Saugus prisijungimas',
                        'Prisijungimą patvirtini savo banke pagal PSD2 standartą.',
                      ),
                      _point(
                        Icons.shield_outlined,
                        'Tavo duomenys',
                        'Jie niekada neparduodami ir visada lieka tavo kontrolėje.',
                      ),
                      _point(
                        Icons.verified_outlined,
                        'Licencijuota paslauga',
                        'Duomenis teikia Enable Banking — licencijuota ES atviro bankininkystės tiekėja.',
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: _finish,
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
                          child: Text(tr('Prijungti banką'),
                              style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1846E6))),
                        ),
                      ),
                      const SizedBox(height: 11),
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          textAlign: TextAlign.center,
                          tr('2500+ bankų visoje Europoje'),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.62)),
                        ),
                      ),
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

  /// Android only. See the class doc: the artwork's height is capped and
  /// then shrunk to whatever room the (measured) copy hasn't claimed, so
  /// neither can collide with the other on the shorter/narrower screens this
  /// was built for. Three combined trust points, not five — the same
  /// content, grouped, so it can fit without scrolling.
  Widget _buildAndroid(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 300 is the ceiling — comfortably more than the tiles need on every
    // screen this was measured against. Once the copy below has been
    // measured, the artwork shrinks to whatever is actually left over
    // instead of holding that ceiling regardless, which is what let it
    // outgrow the screen and push the copy into a scroll.
    final imgH =
        _copyH == null ? 300.0 : (size.height - _copyH!).clamp(0.0, 300.0);
    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The bank tiles run from 5% to 66% of the render — the tallest
          // subject of any page in the chain — and five trust points is a lot
          // of copy to fit below it. Capping the artwork's height and
          // shrinking it to fit under the copy reserves the room instead of
          // hoping there's some left over.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: imgH,
            child: Stack(
              children: [
                ClipRect(
                  child: OverflowBox(
                    maxHeight: double.infinity,
                    alignment: Alignment.topCenter,
                    child: Transform.translate(
                      // Lifted by 8%: the render's top-left is empty floor,
                      // and drawn from y=0 that corner read as a hole above
                      // the tiles.
                      offset: Offset(
                          0,
                          -MediaQuery.of(context).size.width *
                              1844 /
                              853 *
                              0.08),
                      child: Image.asset('assets/onboarding/page7_scene.png',
                          width: MediaQuery.of(context).size.width,
                          fit: BoxFit.fitWidth),
                    ),
                  ),
                ),
                // The hard-capped box above gives the copy guaranteed room,
                // but cropping the render at a fixed height leaves a visible
                // straight edge where the artwork just stops — this fades
                // the last stretch of it into the page colour instead, so
                // the box reads as an intentional vignette rather than a cut.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x00041038),
                            Color(0xFF041038),
                          ],
                          stops: [0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // The render fades into the page before the copy starts, so its lower
          // edge is never a visible line.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00041038),
                      Color(0x00041038),
                      Color(0xCC041038),
                      _deep,
                    ],
                    stops: [0, 0.30, 0.44, 0.56],
                  ),
                ),
              ),
            ),
          ),
          // Measured the same way [OnbScenePage] measures its copy: the
          // block bottom-aligns in the full page and reports its own
          // rendered height, which is what [imgH] above shrinks the
          // artwork to make room for. No scrolling needed — the artwork
          // gives way instead.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                key: _copyKey,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      tr('Prieigą\nkontroliuoji tu'),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.12,
                        letterSpacing: -0.9,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _point(
                      Icons.account_balance_rounded,
                      'Pasirink, ką prijungti',
                      'Prijunk tik tas sąskaitas, kurias nori.',
                    ),
                    _point(
                      Icons.visibility_outlined,
                      'Tik skaitymo prieiga, saugus prisijungimas',
                      'Vaultie negali atlikti mokėjimų ar pervesti pinigų; prisijungimą patvirtini savo banke pagal PSD2 standartą.',
                    ),
                    _point(
                      Icons.shield_outlined,
                      'Tavo duomenys saugūs',
                      'Niekada neparduodami ir visada lieka tavo kontrolėje. Duomenis teikia Enable Banking — licencijuota ES atviro bankininkystės tiekėja.',
                    ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: _finish,
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
                        child: Text(tr('Prijungti banką'),
                            style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1846E6))),
                      ),
                    ),
                    const SizedBox(height: 11),
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        textAlign: TextAlign.center,
                        tr('2500+ bankų visoje Europoje'),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.62)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _point(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2F6BFF).withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 17, color: const Color(0xFFDBE6FF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(title),
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(tr(body),
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.34,
                          color: Colors.white.withValues(alpha: 0.78))),
                ],
              ),
            ),
          ],
        ),
      );
}
