import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../expense_categories.dart';
import '../main.dart';
import 'auth_screen.dart';

/// Three-screen onboarding built entirely with Flutter widgets (no artwork
/// assets). Bilingual LT/EN. New users swipe/tap through 1 → 2 → 3, then land
/// on the auth screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const route = '/onboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
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
      backgroundColor: VaultieColors.surface,
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(), // button-only
        children: [
          _OnboardPage(
            index: 0,
            label: continueLabel,
            onPressed: _next,
            content: _screen1(isLt),
          ),
          _OnboardPage(
            index: 1,
            label: continueLabel,
            onPressed: _next,
            content: _screen2(isLt),
          ),
          _OnboardPage(
            index: 2,
            label: getStartedLabel,
            onPressed: _finish,
            content: _screen3(isLt),
          ),
        ],
      ),
    );
  }

  // ── Screen 1: all recurring payments (not just subscriptions) ────────────

  Widget _screen1(bool isLt) {
    final rows = <Widget>[
      _payRow(isLt ? 'Nuoma' : 'Rent', 'housing',
          isLt ? 'po 5 d.' : 'in 5 days', '€650'),
      _payRow(isLt ? 'Auto draudimas' : 'Car insurance', 'insurance',
          isLt ? 'kas mėnesį' : 'monthly', '€45'),
      _payRow(isLt ? 'Sporto klubas' : 'Gym', 'health',
          isLt ? 'kas mėnesį' : 'monthly', '€30'),
      _payRow('Netflix', 'entertainment', isLt ? 'po 12 d.' : 'in 12 days',
          '€15.99'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(isLt
            ? 'Visi mokėjimai\nvienoje vietoje.'
            : 'All your payments,\nin one place.'),
        const SizedBox(height: 12),
        _Subtitle(isLt
            ? 'Nuoma, komunaliniai, draudimas, sporto salė, prenumeratos — sek viską, už ką moki reguliariai, ne tik programėles.'
            : 'Rent, utilities, insurance, gym, subscriptions — track everything you pay for regularly, not just apps.'),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isLt ? 'Mėnesio išlaidos' : 'Monthly spend',
                  style: const TextStyle(
                      color: VaultieColors.subtle, fontSize: 13)),
              const SizedBox(height: 4),
              const Text('€740.99',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 20),
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
            for (final c in (isLt
                ? [
                    'Būstas',
                    'Komunaliniai',
                    'Draudimas',
                    'Transportas',
                    'Sporto salė',
                    'Prenumeratos'
                  ]
                : [
                    'Housing',
                    'Utilities',
                    'Insurance',
                    'Transport',
                    'Gym',
                    'Subscriptions'
                  ]))
              _chip(c),
          ],
        ),
      ],
    );
  }

  /// A payment row using the real category icon + colour, so the breadth of
  /// categories (rent, insurance, gym, subscriptions…) is obvious.
  Widget _payRow(String name, String catKey, String sub, String price) {
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
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(
                      color: VaultieColors.subtle, fontSize: 12)),
            ],
          ),
        ),
        Text(price,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ],
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: VaultieColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE1E8E3)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: VaultieColors.subtle,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      );

  // ── Screen 2: stats + features ───────────────────────────────────────────

  Widget _screen2(bool isLt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(isLt
            ? 'Taupyk nekeisdamas\ngyvenimo būdo.'
            : 'Save money without\nchanging lifestyle.'),
        const SizedBox(height: 20),
        Row(
          children: [
            _statCard('€127', isLt ? 'per mėn.' : 'per month'),
            const SizedBox(width: 10),
            _statCard('€1.5K', isLt ? 'per metus' : 'per year'),
            const SizedBox(width: 10),
            _statCard('€4.19', isLt ? 'per dieną' : 'per day'),
          ],
        ),
        const SizedBox(height: 20),
        _featureCard(
          Icons.insights_rounded,
          isLt ? 'Išlaidų analitika' : 'Spending analytics',
          isLt
              ? 'Matyk, kur tiksliai iškeliauja pinigai'
              : 'See exactly where your money goes',
        ),
        const SizedBox(height: 12),
        _featureCard(
          Icons.category_rounded,
          isLt ? 'Viskas vienoje vietoje' : 'Everything in one place',
          isLt
              ? 'Nuoma, mokesčiai, draudimas ir prenumeratos kartu'
              : 'Rent, bills, insurance and subscriptions together',
        ),
        const SizedBox(height: 12),
        _featureCard(
          Icons.savings_rounded,
          isLt ? 'Sek savo santaupas' : 'Track your savings',
          isLt ? 'Stebėk, kaip auga santaupos' : 'Watch your savings grow',
        ),
      ],
    );
  }

  Widget _statCard(String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          decoration: _cardDecoration,
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      color: VaultieColors.subtle, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _featureCard(IconData icon, String title, String desc) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: VaultieColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: VaultieColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          color: VaultieColors.subtle, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: VaultieColors.subtle),
          ],
        ),
      );

  // ── Screen 3: reminders ──────────────────────────────────────────────────

  Widget _screen3(bool isLt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(isLt
            ? 'Priminsime prieš\nkiekvieną mokėjimą.'
            : "We'll remind you before\nevery payment."),
        const SizedBox(height: 20),
        // Notification banner.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: VaultieColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Colors.white, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLt ? 'Mokėjimų priminimai' : 'Payment reminders',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLt
                          ? 'Pranešime maždaug prieš 24 val. iki kiekvieno mokėjimo.'
                          : 'We notify you about 24 hours before each payment.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                          height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _reminderCard(
          isLt
              ? 'Nuoma · €650 – mokėjimas rytoj'
              : 'Rent · €650 – due tomorrow',
          isLt ? 'dabar' : 'now',
        ),
        const SizedBox(height: 12),
        _reminderCard(
          isLt
              ? 'Auto draudimas · €45 – po 2 d.'
              : 'Car insurance · €45 – in 2 days',
          isLt ? 'prieš 5 min.' : '5 min ago',
        ),
      ],
    );
  }

  Widget _reminderCard(String body, String time) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset('assets/icon/app_icon.png',
                  width: 32, height: 32, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Vaultie',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      const Spacer(),
                      Text(time,
                          style: const TextStyle(
                              color: VaultieColors.subtle, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(body, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── Shared bits ──────────────────────────────────────────────────────────

final BoxDecoration _cardDecoration = BoxDecoration(
  color: VaultieColors.card,
  borderRadius: BorderRadius.circular(20),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: VaultieColors.ink,
        ),
      );
}

class _Subtitle extends StatelessWidget {
  const _Subtitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.4,
          color: VaultieColors.subtle,
        ),
      );
}

/// Page chrome shared by all three screens: top-left logo, scrollable content,
/// a page indicator, and the CTA. Wrapped in SafeArea so nothing sits under the
/// notch / Dynamic Island.
class _OnboardPage extends StatelessWidget {
  const _OnboardPage({
    required this.index,
    required this.content,
    required this.label,
    required this.onPressed,
  });

  final int index;
  final Widget content;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                const Text('Vaultie',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: VaultieColors.ink)),
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
                      ? VaultieColors.primary
                      : VaultieColors.primary.withValues(alpha: 0.2),
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
