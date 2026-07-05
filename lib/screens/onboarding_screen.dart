import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../expense_categories.dart';
import '../main.dart';
import '../widgets/subscription_icons.dart';
import 'auth_screen.dart';

/// Three-screen onboarding built entirely with Flutter widgets (no artwork
/// assets). Bilingual LT/EN. New users swipe/tap through 1 → 2 → 3, then land
/// on the auth screen.
///
/// The middle screen renders in the app's dark (graphite) palette so new users
/// see, at a glance, that Vaultie ships both a light and a dark theme.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const route = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// A minimal palette so each onboarding page can render light or dark.
class _Pal {
  const _Pal({
    required this.bg,
    required this.card,
    required this.ink,
    required this.subtle,
    required this.line,
    required this.accent,
  });
  final Color bg, card, ink, subtle, line, accent;

  static const light = _Pal(
    bg: Color(0xFFF4F8F5),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF11231A),
    subtle: Color(0xFF6B7E74),
    line: Color(0xFFE1E8E3),
    accent: Color(0xFF2E7D4F),
  );
  // Matches content_theme.dart's graphite dark palette.
  static const dark = _Pal(
    bg: Color(0xFF111316),
    card: Color(0xFF1C2024),
    ink: Color(0xFFF1F3F4),
    subtle: Color(0xFF9AA0A6),
    line: Color(0xFF2A2F35),
    accent: Color(0xFF4CAF72),
  );
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller =
      PageController(initialPage: const int.fromEnvironment('ONBOARD_PAGE'));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await Hive.box(HiveBoxes.settings).put('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final continueLabel = isLt ? 'Toliau →' : 'Continue →';
    final getStartedLabel = isLt ? 'Pradėti →' : 'Get Started →';

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(), // button-only
        children: [
          _OnboardPage(
            index: 0,
            pal: _Pal.light,
            label: continueLabel,
            onPressed: _next,
            content: _screen1(isLt, _Pal.light),
          ),
          _OnboardPage(
            index: 1,
            pal: _Pal.dark,
            label: continueLabel,
            onPressed: _next,
            content: _screen2(isLt, _Pal.dark),
          ),
          _OnboardPage(
            index: 2,
            pal: _Pal.light,
            label: getStartedLabel,
            onPressed: _finish,
            content: _screen3(isLt, _Pal.light),
          ),
        ],
      ),
    );
  }

  // ── Screen 1: all recurring payments + spending donut ────────────────────

  Widget _screen1(bool isLt, _Pal pal) {
    final rows = <Widget>[
      _payRow(pal, isLt ? 'Nuoma' : 'Rent', 'housing',
          isLt ? 'po 5 d.' : 'in 5 days', '€650'),
      _payRow(pal, isLt ? 'Auto draudimas' : 'Car insurance', 'insurance',
          isLt ? 'kas mėnesį' : 'monthly', '€45'),
      _payRow(pal, isLt ? 'Sporto klubas' : 'Gym', 'health',
          isLt ? 'kas mėnesį' : 'monthly', '€30'),
      _payRow(pal, 'Netflix', 'entertainment', isLt ? 'po 12 d.' : 'in 12 days',
          '€15.99'),
    ];
    // Donut segments mirror the payment rows above (category → colour).
    final segments = [
      _Seg(650, categoryFor('housing').color),
      _Seg(45, categoryFor('insurance').color),
      _Seg(30, categoryFor('health').color),
      _Seg(15.99, categoryFor('entertainment').color),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(
            isLt
                ? 'Visi mokėjimai\nvienoje vietoje.'
                : 'All your payments,\nin one place.',
            pal),
        const SizedBox(height: 12),
        _Subtitle(
            isLt
                ? 'Nuoma, komunaliniai, draudimas, sporto salė, prenumeratos — sek viską, už ką moki reguliariai, ne tik programėles.'
                : 'Rent, utilities, insurance, gym, subscriptions — track everything you pay for regularly, not just apps.',
            pal),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDeco(pal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spend total on the left, category donut on the right.
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isLt ? 'Mėnesio išlaidos' : 'Monthly spend',
                            style: TextStyle(color: pal.subtle, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('€740.99',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: pal.ink)),
                      ],
                    ),
                  ),
                  _Donut(
                    segments: segments,
                    size: 104,
                    center: '€741',
                    centerSub: isLt ? '/ mėn.' : '/ mo',
                    ink: pal.ink,
                    subtle: pal.subtle,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              for (var i = 0; i < rows.length; i++) ...[
                Divider(height: 20, color: pal.line),
                rows[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final key in const [
              'housing',
              'utilities',
              'insurance',
              'transport',
              'health',
              'entertainment',
            ])
              _catChip(key, isLt, pal),
          ],
        ),
      ],
    );
  }

  /// A payment row using the real category icon + colour, so the breadth of
  /// categories (rent, insurance, gym, subscriptions…) is obvious.
  Widget _payRow(_Pal pal, String name, String catKey, String sub, String price) {
    final cat = categoryFor(catKey);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cat.color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(cat.icon, color: cat.color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: pal.ink)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(color: pal.subtle, fontSize: 12)),
            ],
          ),
        ),
        Text(price,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: pal.ink)),
      ],
    );
  }

  /// A vivid category pill: the category's own colour + icon, so the breadth of
  /// what Vaultie tracks reads at a glance.
  Widget _catChip(String key, bool isLt, _Pal pal) {
    final cat = categoryFor(key);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cat.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cat.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cat.icon, size: 15, color: cat.color),
          const SizedBox(width: 6),
          Text(categoryLabel(key, isLt),
              style: TextStyle(
                  color: pal.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Screen 2 (dark): insights, export & everything together ──────────────

  Widget _screen2(bool isLt, _Pal pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(
            isLt
                ? 'Matyk, kur keliauja\ntavo pinigai.'
                : 'See where your\nmoney goes.',
            pal),
        const SizedBox(height: 20),
        Row(
          children: [
            _statCard(pal, '€127', isLt ? 'per mėn.' : 'per month'),
            const SizedBox(width: 10),
            _statCard(pal, '€1.5K', isLt ? 'per metus' : 'per year'),
            const SizedBox(width: 10),
            _statCard(pal, '€4.19', isLt ? 'per dieną' : 'per day'),
          ],
        ),
        const SizedBox(height: 20),
        _featureCard(
          pal,
          Icons.donut_large_rounded,
          isLt ? 'Išlaidų analitika' : 'Spending analytics',
          isLt
              ? 'Diagramos ir įžvalgos pagal kategorijas'
              : 'Charts and insights by category',
        ),
        const SizedBox(height: 12),
        _featureCard(
          pal,
          Icons.ios_share_rounded,
          isLt ? 'Eksportas PDF ir CSV' : 'Export as PDF & CSV',
          isLt
              ? 'Atsisiųsk savo duomenis bet kada'
              : 'Download your data anytime',
        ),
        const SizedBox(height: 12),
        _featureCard(
          pal,
          Icons.notifications_active_rounded,
          isLt ? 'Mokėjimų priminimai' : 'Payment reminders',
          isLt
              ? 'Pranešime ~24 val. iki kiekvieno mokėjimo'
              : 'We notify you ~24h before every payment',
        ),
        const SizedBox(height: 24),
        Text(
          isLt ? 'Veikia su viskuo, ką naudoji' : 'Works with all your favourites',
          style: TextStyle(
              color: pal.subtle, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            BrandLogo(brand: Brand.netflix, size: 52),
            BrandLogo(brand: Brand.spotify, size: 52),
            BrandLogo(brand: Brand.youtube, size: 52),
            BrandLogo(brand: Brand.primeVideo, size: 52),
            BrandLogo(brand: Brand.disneyPlus, size: 52),
            BrandLogo(brand: Brand.appleTv, size: 52),
            BrandLogo(brand: Brand.icloud, size: 52),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          isLt ? '…ir bet kokį kitą mokėjimą' : '…and any other payment',
          style: TextStyle(color: pal.subtle, fontSize: 12),
        ),
      ],
    );
  }

  Widget _statCard(_Pal pal, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          decoration: _cardDeco(pal),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: pal.ink)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(color: pal.subtle, fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _featureCard(_Pal pal, IconData icon, String title, String desc) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(pal),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: pal.accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: pal.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: pal.ink)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(color: pal.subtle, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, color: pal.subtle),
          ],
        ),
      );

  // ── Screen 3: the extra tools that keep money on track ───────────────────

  Widget _screen3(bool isLt, _Pal pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(
            isLt
                ? 'Viskas, ko reikia,\nkad valdytum.'
                : 'Everything you need\nto stay on top.',
            pal),
        const SizedBox(height: 12),
        _Subtitle(
            isLt
                ? 'Paprasti įrankiai, kad pinigai visada būtų po kontrole.'
                : 'Simple tools that keep your money on track.',
            pal),
        const SizedBox(height: 22),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _featureTile(
                    pal,
                    Icons.savings_rounded,
                    isLt ? 'Santaupų sekimas' : 'Savings tracker',
                    isLt
                        ? 'Kiek sutaupai atsisakęs prenumeratų'
                        : 'See what cancelling saves you'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _featureTile(
                    pal,
                    Icons.account_balance_wallet_rounded,
                    isLt ? 'Mėnesio biudžetas' : 'Monthly budget',
                    isLt
                        ? 'Nustatyk ribą ir gauk įspėjimą'
                        : 'Set a limit and get a heads-up'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _featureTile(
                    pal,
                    Icons.calendar_month_rounded,
                    isLt ? 'Mėnesio apžvalga' : 'Monthly recap',
                    isLt
                        ? 'Tavo mėnuo — trumpai ir aiškiai'
                        : 'Your month at a glance'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _featureTile(
                    pal,
                    Icons.lock_rounded,
                    isLt ? 'Privatu ir saugu' : 'Private & secure',
                    isLt
                        ? 'Duomenys lieka tavo įrenginyje'
                        : 'Your data stays on your device'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _featureTile(
                    pal,
                    Icons.public_rounded,
                    isLt ? 'Bet kokia valiuta' : 'Any currency',
                    isLt
                        ? 'Sumos rodomos tavo valiuta'
                        : 'See amounts in your currency'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _featureTile(
                    pal,
                    Icons.wifi_off_rounded,
                    isLt ? 'Veikia be interneto' : 'Works offline',
                    isLt
                        ? 'Viskas saugoma tavo telefone'
                        : 'Everything stored on your phone'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A square feature tile (icon on top) used in the closing 2×2 grid. Uses a
  /// solid green icon badge + green frame so each feature reads boldly.
  Widget _featureTile(_Pal pal, IconData icon, String title, String desc) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: pal.accent.withValues(alpha: 0.40), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: pal.accent.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: pal.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: pal.accent.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15, color: pal.ink)),
            const SizedBox(height: 4),
            Text(desc,
                style:
                    TextStyle(color: pal.subtle, fontSize: 12.5, height: 1.3)),
          ],
        ),
      );

}

// ── Donut chart ────────────────────────────────────────────────────────────

class _Seg {
  const _Seg(this.value, this.color);
  final double value;
  final Color color;
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.segments,
    required this.size,
    required this.center,
    required this.centerSub,
    required this.ink,
    required this.subtle,
  });

  final List<_Seg> segments;
  final double size;
  final String center, centerSub;
  final Color ink, subtle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _DonutPainter(segments)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: size * 0.17,
                      color: ink)),
              Text(centerSub,
                  style: TextStyle(fontSize: size * 0.1, color: subtle)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments);
  final List<_Seg> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    final stroke = size.width * 0.15;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    const gap = 0.05;
    for (final s in segments) {
      final sweep = (s.value / total) * (2 * math.pi);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = s.color;
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => false;
}

// ── Shared bits ──────────────────────────────────────────────────────────

BoxDecoration _cardDeco(_Pal pal) => BoxDecoration(
      color: pal.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: pal.line),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );

class _Title extends StatelessWidget {
  const _Title(this.text, this.pal);
  final String text;
  final _Pal pal;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: pal.ink,
        ),
      );
}

class _Subtitle extends StatelessWidget {
  const _Subtitle(this.text, this.pal);
  final String text;
  final _Pal pal;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: pal.subtle,
        ),
      );
}

/// Page chrome shared by all three screens: top-left logo, scrollable content,
/// a page indicator, and the CTA. Wrapped in SafeArea so nothing sits under the
/// notch / Dynamic Island. The [pal] drives light vs dark rendering.
class _OnboardPage extends StatelessWidget {
  const _OnboardPage({
    required this.index,
    required this.pal,
    required this.content,
    required this.label,
    required this.onPressed,
  });

  final int index;
  final _Pal pal;
  final Widget content;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: pal.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo, top-left.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset('assets/icon/app_icon.png',
                        width: 40, height: 40, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Text('Vaultie',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: pal.ink)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: content,
              ),
            ),
            // Page indicator.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final active = i == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? pal.accent
                        : pal.accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: _CtaButton(label: label, onPressed: onPressed),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared dark-green pill button used at the bottom of every screen.
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF174E35).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF174E35),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
