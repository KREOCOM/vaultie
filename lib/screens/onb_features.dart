import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import 'splash_screen.dart';

/// Onboarding page 7 — the last page before the bank connect: everything
/// the intro had no room to demonstrate.
///
/// 2026-09-02 rework, per explicit request ("atrodo labai daug teksto"):
/// the previous version's seven left-rule rows plus a capability chip strip
/// was more copy than any other page in the chain and read as a wall of
/// text. Condensed to five icon-tile cards (same idea as a supplied
/// reference mockup) covering the exact same real features, just paired up
/// — receipts/budget stay separate (the two things someone actually opens
/// daily), while banks+currencies+export merge into one "data" card and
/// security+language/theme merge into one "personalise" card. Nothing
/// listed here that isn't in the app: receipts (`ScanService`), the budget
/// (`AppPrefs.budget`), bills/subscriptions (`LiveRecurringScreen`), the
/// currency conversion (`FxRates`) and CSV/PDF export, the lock (`AppLock`),
/// and the language/theme choice (`AppPrefs.locale`/`darkMode`).
///
/// The cards stagger in one at a time, alternating left/right, rather than
/// appearing all at once — per explicit request, so the list reads as a
/// sequence of things being pointed out instead of a static block of text
/// landing all together.
class OnbFeatures extends StatefulWidget {
  const OnbFeatures({super.key, required this.next});

  final Widget next;

  @override
  State<OnbFeatures> createState() => _OnbFeaturesState();
}

class _OnbFeaturesState extends State<OnbFeatures>
    with SingleTickerProviderStateMixin {
  static const _deep = Color(0xFF030B24);

  static const _cards = [
    (
      icon: Icons.document_scanner_outlined,
      title: 'Išlaidos ir kvitai',
      sub: 'Skenuok kvitus, sek išlaidas ir kategorijas.',
    ),
    (
      icon: Icons.track_changes_rounded,
      title: 'Biudžetas ir tikslai',
      sub: 'Nustatyk biudžetus ir siek savo tikslų.',
    ),
    (
      icon: Icons.notifications_active_rounded,
      title: 'Sąskaitos ir priminimai',
      sub: 'Sek prenumeratas, sąskaitas ir mokėk laiku.',
    ),
    (
      icon: Icons.account_balance_rounded,
      title: 'Bankai, valiutos, eksportas',
      sub: 'Prijunk bankus, konvertuok valiutas, eksportuok duomenis.',
    ),
    (
      icon: Icons.lock_rounded,
      title: 'Saugumas ir pritaikymas',
      sub: 'Face ID, PIN, kalba ir tema — kaip tau patogu.',
    ),
  ];

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 500 + _cards.length * 170),
  )..forward();

  /// Card [i]'s own slice of the shared controller — staggered by 170ms per
  /// card, each running over ~500ms of it, so card 2 is already sliding in
  /// while card 1 is still settling rather than waiting its turn.
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

  void _next(BuildContext context) {
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
                                // 2026-09-04: was a paler blue, then a
                                // gradient accent — both reverted per
                                // explicit feedback (too faint / only page
                                // 1 keeps the blue accent). Plain white,
                                // matching the first line.
                                TextSpan(
                                    text: tr('Daugiau kontrolės.'),
                                    style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Tvarkyk savo kasdienius finansus vienoje vietoje.'),
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.45,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(height: 22),
                          for (var i = 0; i < _cards.length; i++)
                            _card(i),
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

  /// Card [i] slides in from the right on even indexes, from the left on
  /// odd ones, fading in over the same span — per explicit request, so the
  /// list reads as items being pointed out one at a time rather than a
  /// block of text landing all at once.
  Widget _card(int i) {
    final c = _cards[i];
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3E63FF), Color(0xFF1B2E7A)],
                  ),
                ),
                child: Icon(c.icon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(c.title),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(tr(c.sub),
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: Colors.white.withValues(alpha: 0.65))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.35), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 7; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == 6 ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: i == 6 ? 1 : 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}
