import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../services/fx_rates.dart';
import 'splash_screen.dart';

/// Onboarding page 6 — the last page before the bank connect: everything
/// the intro had no room to demonstrate.
///
/// 2026-08-19: rebuilt on a supplied reference mockup — a plain ambient
/// gradient field (page6_bg.png) with the mark, a two-tone headline, seven
/// left-rule feature rows and a capability chip strip, all real Flutter
/// text/widgets (the mockup's own text is baked into its OWN copy of the
/// image and isn't reachable from code — page6_bg.png is deliberately the
/// EMPTY version of that render, supplied separately, so every word here
/// can still be localised/edited). Scrollable: seven rows plus the chip
/// strip is more copy than any other page in the chain, and unlike a fixed
/// cap-and-shrink artwork (the previous page's Android strategy) a plain
/// static background never NEEDS the room back, so letting the copy scroll
/// over it is the simplest thing that always fits.
///
/// Each row is a feature that exists in the code — receipts (`ScanService`),
/// the budget (`AppPrefs.budget`), bills/subscriptions (`LiveRecurringScreen`),
/// the currency conversion (`FxRates`), CSV/PDF export, the lock (`AppLock`)
/// and the language/theme choice (`AppPrefs.locale`/`darkMode`). An intro
/// that lists things the app cannot do is worse than an intro that lists
/// fewer things.
class OnbFeatures extends StatelessWidget {
  const OnbFeatures({super.key, required this.next});

  final Widget next;

  static const _deep = Color(0xFF030B24);

  void _next(BuildContext context) {
    HapticFeedback.lightImpact();
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
                image: AssetImage('assets/onboarding/page6_bg.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(26, 8, 26, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Same off-center RadialGradient formula as the
                          // splash's own mark tile — a bright spot near one
                          // corner fading to a deep navy anchor.
                          Container(
                            width: 46,
                            height: 46,
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: const RadialGradient(
                                center: Alignment(-0.6, -1.0),
                                radius: 1.6,
                                colors: [
                                  Color(0xFF3E63FF),
                                  Color(0xFF081A4D)
                                ],
                                stops: [0.0, 0.65],
                              ),
                            ),
                            child: Image.asset('assets/icon/logo_mark.png',
                                fit: BoxFit.contain),
                          ),
                          const SizedBox(height: 20),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                                height: 1.16,
                                letterSpacing: -0.8,
                              ),
                              children: [
                                TextSpan(
                                    text: tr('Daugiau funkcijų.\n'),
                                    style:
                                        const TextStyle(color: Colors.white)),
                                TextSpan(
                                    text: tr('Daugiau kontrolės.'),
                                    style: const TextStyle(
                                        color: Color(0xFF6E9CFF))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Tvarkyk išlaidas, biudžetą, sąskaitas ir kasdienius pinigus vienoje aplikacijoje.'),
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _row(
                            tr('Išlaidos ir kvitai'),
                            tr('Skenuok kvitus ir automatiškai rūšiuok pirkinius į kategorijas.'),
                          ),
                          _row(
                            tr('Biudžetas ir tikslai'),
                            tr('Nustatyk biudžetus, stebėk išlaidas ir siek savo finansinių tikslų.'),
                          ),
                          _row(
                            tr('Sąskaitos ir mokėjimai'),
                            tr('Dalinkis sąskaitomis, valdyk mokėjimus ir gauk priminimus laiku.'),
                          ),
                          _row(
                            tr('Bankai ir valiutos'),
                            // The count comes from the catalogue, not from
                            // prose — see _row's own note on why this is
                            // composed here rather than passed as a literal.
                            // 'valiutas' (accusative) — direct object of "konvertuok",
                            // not the genitive 'valiutų' this used to read.
                            '${tr('Prijunk bankus, stebėk sąskaitas ir konvertuok')} ${kCurrencies.length} ${tr('skirtingas valiutas.')}',
                          ),
                          _row(
                            tr('Eksportas ir atsarginės kopijos'),
                            tr('Eksportuok duomenis į CSV arba PDF formatus ir turėk viską po ranka.'),
                          ),
                          _row(
                            tr('Saugumas ir patogumas'),
                            tr('Face ID, PIN kodas ir kiti saugumo sprendimai, kuriais gali pasitikėti.'),
                          ),
                          _row(
                            tr('Pritaikyta tau'),
                            tr('Pasirink kalbą (LT / EN) ir temą (šviesi / tamsi) taip, kaip tau patogiausia.'),
                          ),
                          const SizedBox(height: 18),
                          _chips(),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 16),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => _next(context),
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
                            child: Text(tr('Toliau'),
                                style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1846E6))),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _dots(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ));

  Widget _row(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 2.5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3E63FF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15.5,
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
        ),
      );

  /// The capability strip from the reference mockup — a quick, scannable
  /// "yes, it really does all this" summary right under the feature rows.
  Widget _chips() {
    const items = [
      'Face ID',
      'PIN',
      'CSV / PDF',
      'LT / EN',
      'Dark / Light',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Text('•',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 13)),
            Text(items[i],
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9))),
          ],
        ],
      ),
    );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 5 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 5 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
