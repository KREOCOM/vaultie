import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../main.dart';
import '../services/dashboard_store.dart';
import '../services/purchase_service.dart';
import 'bank_connect_screen.dart';
import 'onb_paywall.dart';
import 'preview/dashboard_preview.dart';

/// Green accent for onboarding CTAs, matching the paywall/splash.
const Color _brightGreen = Color(0xFF4CAF72);
const Color _gold = Color(0xFFFFD24A);

/// Where a user lands after signing in: the paywall without an active plan,
/// otherwise the saved dashboard (persisted from the last bank scan) if there
/// is one, else the bank flow to connect.
///
/// No first-run choice screen any more: it was the last screen still wearing
/// the old green identity, and the intro chain's own "Prijungti banką" screen
/// already makes the same pitch in the current one.
Widget landingAfterAuth() {
  // Vaultie is subscription-only, so the entitlement — not the presence of
  // local data — decides who gets in. This used to key off the saved dashboard
  // alone, which meant connecting a bank once bought permanent free access:
  // the paywall was skipped for anyone who had data, including after their
  // subscription lapsed.
  if (!PurchaseService.instance.isPremium) {
    return const OnbPaywall(next: BankConnectScreen());
  }
  final saved = DashboardStore.load();
  // Straight to the bank list. BankInfoScreen said four things: three are now
  // on the blue "Prijungti banką" screen, and the remaining two facts moved to
  // the bank list's own footer. It was also the last screen still wearing the
  // old green identity. The file stays on disk, just off this path.
  return saved != null
      ? DashboardPreview(data: saved)
      : const BankConnectScreen();
}

/// First-run screen shown right after login: connect a bank (recommended) or
/// start manually. Shown once — either choice marks onboarding complete.
class OnboardingChoiceScreen extends StatelessWidget {
  const OnboardingChoiceScreen({super.key});

  static const route = '/onboarding-choice';

  Future<void> _choose(BuildContext context, {required bool bank}) async {
    await AppPrefs.setOnboardingComplete(true);
    if (!context.mounted) return;
    // Both paths land on the bank flow for now — the green DashboardScreen is
    // temporarily hidden (kept in code; `bank` retained for the later decision).
    // Goes to the bank list directly, same as landingAfterAuth: the explainer
    // in between was the last green screen and its content now lives on the
    // "Prijungti banką" screen and in the list's own footer.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const OnbPaywall(next: BankConnectScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Scaffold(
      backgroundColor: const Color(0xFF050F08),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.6),
                    radius: 1.1,
                    colors: [Color(0x662E6B4D), Color(0x00050F08)],
                    stops: [0.0, 0.7],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isLt ? 'Kaip norite pradėti?' : 'How would you like to start?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isLt
                        ? 'Pasirinkite, kaip užpildyti savo vaultą.'
                        : 'Choose how to fill your vault.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _choiceCard(
                    icon: Icons.account_balance_rounded,
                    accent: _brightGreen,
                    recommended: isLt ? 'Rekomenduojama' : 'Recommended',
                    title: isLt ? 'Prijungti banką' : 'Connect your bank',
                    body: isLt
                        ? 'Automatiškai rasime jūsų pasikartojančius mokėjimus iš banko istorijos. Jokių duomenų nesaugome serveryje — viskas tik jūsų telefone.'
                        : 'We\'ll automatically find your recurring payments from your bank history. Nothing is stored on our servers — it all stays on your phone.',
                    onTap: () => _choose(context, bank: true),
                  ),
                  const SizedBox(height: 16),
                  _choiceCard(
                    icon: Icons.edit_note_rounded,
                    accent: Colors.white.withValues(alpha: 0.6),
                    recommended: null,
                    title: isLt ? 'Pradėti rankiniu būdu' : 'Start manually',
                    body: isLt
                        ? 'Patys įvesite prenumeratas ir mokėjimus. Banką galėsite prijungti bet kada vėliau nustatymuose.'
                        : 'Add your subscriptions and payments yourself. You can connect a bank anytime later in Settings.',
                    onTap: () => _choose(context, bank: false),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    isLt
                        ? 'Savo pasirinkimą galėsite pakeisti bet kada.'
                        : 'You can change your choice anytime.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceCard({
    required IconData icon,
    required Color accent,
    required String? recommended,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1F15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: recommended != null
                  ? accent
                  : Colors.white.withValues(alpha: 0.12),
              width: recommended != null ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (recommended != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        recommended.toUpperCase(),
                        style: const TextStyle(
                          color: VaultieColors.primaryDark,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.arrow_forward_rounded,
                      color: accent, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
