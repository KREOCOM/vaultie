import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  // ── Screen 1: subscription list ──────────────────────────────────────────

  Widget _screen1(bool isLt) {
    const subs = <_SubRow>[
      _SubRow('Netflix', Color(0xFFE50914), 5, '€15.99'),
      _SubRow('Spotify', Color(0xFF1DB954), 8, '€9.99'),
      _SubRow('YouTube Premium', Color(0xFFFF0000), 12, '€11.99'),
      _SubRow('Amazon Prime', Color(0xFF00A8E1), 15, '€4.99'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Title(isLt
            ? 'Išleisk protingiau.\nTaupyk daugiau.'
            : 'Spend smarter.\nSave more.'),
        const SizedBox(height: 12),
        _Subtitle(isLt
            ? 'Atsisakyk nenaudojamų prenumeratų, išvenk netikėtų mokesčių ir kas mėnesį sutaupyk daugiau.'
            : 'Cancel unused subscriptions, avoid unexpected charges, and keep more money every month.'),
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
              const Text('€127.36',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              for (var i = 0; i < subs.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _subRow(subs[i], isLt),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final b in ['Apple TV', 'Disney+', 'iCloud', 'ChatGPT Plus'])
              _chip(b),
          ],
        ),
      ],
    );
  }

  Widget _subRow(_SubRow s, bool isLt) {
    final renews = s.days == 1
        ? (isLt ? 'Atsinaujina rytoj' : 'Renews tomorrow')
        : (isLt ? 'Atsinaujina po ${s.days} d.' : 'Renews in ${s.days} days');
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(renews,
                  style: const TextStyle(
                      color: VaultieColors.subtle, fontSize: 12)),
            ],
          ),
        ),
        Text(s.price,
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
          Icons.travel_explore_rounded,
          isLt ? 'Rask paslėptas išlaidas' : 'Find hidden costs',
          isLt
              ? 'Aptik pamirštas prenumeratas'
              : 'Spot forgotten subscriptions',
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
            ? 'Mes seksime kiekvieną\nprenumeratą už tave.'
            : "We'll track every\nsubscription for you."),
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
                      isLt
                          ? 'Priminimai apie atsinaujinimą'
                          : 'Renewal reminders',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLt
                          ? 'Pranešime prieš 3, 2 ir 1 dieną iki kiekvieno mokėjimo.'
                          : 'We notify you 3, 2 and 1 days before every renewal.',
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
              ? 'Netflix atsinaujina rytoj · €15.99'
              : 'Netflix renews tomorrow · €15.99',
          isLt ? 'dabar' : 'now',
        ),
        const SizedBox(height: 12),
        _reminderCard(
          isLt
              ? 'Spotify atsinaujina po 2 d. · €9.99'
              : 'Spotify renews in 2 days · €9.99',
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

class _SubRow {
  const _SubRow(this.name, this.color, this.days, this.price);
  final String name;
  final Color color;
  final int days;
  final String price;
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
