import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n.dart';
import '../ui/design_system.dart' show CategoryIcon;
import 'splash_screen.dart';

/// Onboarding page 6 — investing, inserted 2026-09-01 between OnbMonth
/// (page 3, at the time) and OnbOverview; moved 2026-09-02 to right before
/// OnbFeatures instead (dotCount 7 throughout; dotIndex 5).
///
/// Went through a live-demo rework and back out again (see git history —
/// a phone-in-photo, then full-screen, then framed DashboardPreview demo,
/// each chasing a real bug) before landing on a plain full-bleed still,
/// same as OnbBanks/OnbConnect. This latest pass (2026-09-02) swaps in a
/// third photo — bull vs bear only this time, no baked-in stock/crypto
/// logo cards like the previous one had — and, per explicit request, adds
/// three of its own icon-tile cards below the copy (same staggered
/// left/right entrance as OnbFeatures/OnbConnect) standing in for the
/// logos this photo doesn't have: stocks, crypto, and real-time price
/// changes — the three things the real Investing tab actually tracks.
class OnbInvest extends StatefulWidget {
  const OnbInvest({super.key, required this.next});

  final Widget next;

  @override
  State<OnbInvest> createState() => _OnbInvestState();
}

class _OnbInvestState extends State<OnbInvest>
    with SingleTickerProviderStateMixin {
  // 2026-09-02: per explicit request, the first two tiles show a REAL brand
  // logo instead of a generic glyph — same CategoryIcon + domain mechanism
  // investing_tab.dart already uses for these exact two (kStockCatalog's
  // Tesla/Bitcoin entries), which itself only ever calls Vaultie's OWN
  // public logo proxy (functions/main.py:merchant_logo), never a third
  // party directly — safe to use pre-login. `icon`/`color` are just the
  // fallback glyph/tile if that fetch ever fails. The third tile has no
  // single brand to show, so it keeps a plain icon instead of a domain.
  static const _cards = [
    (
      icon: Icons.show_chart_rounded,
      title: 'Akcijos',
      sub: 'Tesla, Apple, Google ir kitos populiariausios akcijos.',
      merchant: 'Tesla',
      domain: 'tesla.com',
    ),
    (
      icon: Icons.currency_bitcoin_rounded,
      title: 'Kriptovaliuta',
      sub: 'Bitcoin, Ethereum ir kitos kriptovaliutos.',
      merchant: 'Bitcoin',
      domain: 'bitcoin.org',
    ),
    (
      icon: Icons.bolt_rounded,
      title: 'Pokyčiai realiu laiku',
      sub: 'Kainos kyla ir krenta — matai iš karto.',
      merchant: null,
      domain: null,
    ),
  ];

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 500 + _cards.length * 170),
  )..forward();

  /// Same staggering as OnbFeatures/OnbConnect's own _cardAnim — see
  /// either's doc.
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
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    // This photo's own aspect is nearly identical to the device's, so
    // BoxFit.cover + a topCenter alignment has almost nothing to crop —
    // shifting alignment alone barely moves the artwork at all. Shifting
    // the image itself up by a real amount instead (per explicit request:
    // headline/cards were landing on top of the bull/bear) — height stays
    // at the screen's own height (not taller), so the shift opens a real
    // gap at the BOTTOM rather than stretching the photo to compensate;
    // that gap is filled by the Scaffold's own background colour, matched
    // to this photo's sampled bottom-row average, so the seam is invisible.
    const shift = 0.10;
    return wrapOnbStatusBar(Scaffold(
        backgroundColor: const Color(0xFF00021C),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -h * shift,
              left: 0,
              right: 0,
              height: h,
              child: const Image(
                image: AssetImage('assets/onboarding/page_invest_bg.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Shrunk further (630 -> 460 -> 330) alongside a
                          // bigger `shift` above — per explicit request, to
                          // fit the copy AND all three cards on screen
                          // without needing a scroll.
                          const SizedBox(height: 395),
                          // 2026-09-04: one word per onboarding page picked out in
                          // the same blue gradient as page 1's "finansus" — see
                          // that page's own doc.
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: tr('Investicijos'),
                                style: TextStyle(
                                  foreground: Paint()
                                    ..shader = const LinearGradient(
                                      colors: [Color(0xFF7FB0FF), Color(0xFF0A4DFD)],
                                    ).createShader(const Rect.fromLTWH(0, 0, 150, 32)),
                                ),
                              ),
                              TextSpan(text: tr(' šalia tavo finansų')),
                            ]),
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.4,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                    color: Color(0xB3000000),
                                    blurRadius: 14,
                                    offset: Offset(0, 3)),
                                Shadow(color: Color(0x66000000), blurRadius: 30),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr('Akcijas ir kriptovaliutas stebėk kartu su kasdieniais pinigais.'),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.35,
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
                          const SizedBox(height: 14),
                          for (var i = 0; i < _cards.length; i++) _card(i),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1846E6))),
                          ),
                        ),
                        const SizedBox(height: 18),
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
  }

  /// Card [i] slides in from the right on even indexes, from the left on
  /// odd ones — same mechanism as OnbFeatures/OnbConnect's own `_card`.
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
        padding: const EdgeInsets.only(bottom: 9),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              _tileFor(c),
              const SizedBox(width: 12),
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
            ],
          ),
        ),
      ),
    );
  }

  /// Real brand logo when the card has one (via Vaultie's own public logo
  /// proxy — see `_cards`' own doc), else the plain glyph tile; the
  /// "Real-time changes" card (no single brand to show) gets a tiny
  /// green/red mini-bar pair instead of either, standing in for "prices
  /// moving up and down" the way a logo would for a specific brand.
  Widget _tileFor(({IconData icon, String title, String sub, String? merchant, String? domain}) c) {
    if (c.domain != null) {
      return CategoryIcon(
        icon: c.icon,
        color: const Color(0xFF3E63FF),
        size: 38,
        circle: false,
        merchant: c.merchant,
        domain: c.domain,
      );
    }
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3E63FF), Color(0xFF1B2E7A)],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 5,
            height: 17,
            decoration: BoxDecoration(
              color: const Color(0xFF34C759),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Container(
            width: 5,
            height: 11,
            decoration: BoxDecoration(
              color: const Color(0xFFFF453A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 7; i++)
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
