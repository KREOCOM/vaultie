import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'splash_screen.dart';

/// The last page before the bank connect: everything the intro had no room to
/// demonstrate.
///
/// Each line here is a feature that exists in the code — the budget
/// (`AppPrefs.budget`), the lock (`AppLock`), the payment reminders
/// (`NotificationService.scheduleFromRecurring`), the monthly recap
/// (`RecapService`), the currency conversion (`FxRates`) and the light/dark
/// choice (`AppPrefs.darkMode`). An intro that lists things the app cannot do is
/// worse than an intro that lists fewer things.
///
/// Laid out as rows rather than as a grid because the copy earns full sentences,
/// and unlike every other page in the chain there is no phone to look at — the
/// render puts its subject in the top quarter and leaves the rest to words.
class OnbFeatures extends StatefulWidget {
  const OnbFeatures({super.key, required this.next});

  final Widget next;

  @override
  State<OnbFeatures> createState() => _OnbFeaturesState();
}

class _OnbFeaturesState extends State<OnbFeatures> {
  /// Sampled from the render's own foot (#010827), which is within a few units
  /// of the `_deep` the rest of the chain settles on — so the page ends on the
  /// same shade as its neighbours with no visible step.
  static const _deep = Color(0xFF030E30);

  @override
  void initState() {
    super.initState();
    final auto = kOnbAutoAdvance;
    if (auto != null) {
      Future<void>.delayed(auto, () {
        if (mounted) _next();
      });
    }
  }

  void _next() {
    HapticFeedback.lightImpact();
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deep,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The render's subject — the mark, a chart, a card, a bank — sits in
          // the top quarter and the rest is empty field, so it is drawn from the
          // top at full width and the copy takes everything below.
          const Align(
            alignment: Alignment.topCenter,
            child: Image(
              image: AssetImage('assets/onboarding/page_features.png'),
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
            ),
          ),

          // The render's own field already runs dark enough for white text; this
          // only closes the last stretch onto _deep so the foot of the page
          // matches the pages either side of it.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00030E30),
                      Color(0x66030E30),
                      Color(0xFF030E30),
                    ],
                    stops: [0.42, 0.66, 0.88],
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
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
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
                        tr('Pritaikyk\nVaultie sau'),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.9,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        tr('Kelios funkcijos, kurias nusistatai pagal save.'),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _row(
                        Icons.savings_outlined,
                        'Mėnesio biudžetas',
                        'Nusistatyk ribą, o Vaultie kasdien rodys, kiek dar gali išleisti.',
                      ),
                      _row(
                        Icons.lock_outline_rounded,
                        'PIN kodas ir Face ID',
                        'Uždaryta programėlė lieka užrakinta, net jei telefonas atrakintas.',
                      ),
                      _row(
                        Icons.notifications_none_rounded,
                        'Priminimai apie mokėjimus',
                        'Pranešam prieš nurašymą, kad nė vienas neužkluptų netikėtai.',
                      ),
                      _row(
                        Icons.calendar_today_rounded,
                        'Mėnesio santrauka',
                        'Mėnesiui pasibaigus — kur nukeliavo pinigai ir kiek sutaupei.',
                      ),
                      _row(
                        Icons.public_rounded,
                        'Kitos valiutos',
                        'Sąskaitos svarais ar doleriais suvedamos į vieną bendrą sumą.',
                      ),
                      _row(
                        Icons.dark_mode_outlined,
                        'Šviesus ir tamsus',
                        'Programėlė prisitaiko prie tavęs, ne atvirkščiai.',
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _next,
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
                      Center(child: _dots()),
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

  Widget _row(IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2F6BFF).withValues(alpha: 0.26),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.72))),
                ],
              ),
            ),
          ],
        ),
      );

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
