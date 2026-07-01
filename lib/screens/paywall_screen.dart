import 'package:flutter/material.dart';

import '../main.dart';
import '../services/purchase_service.dart';

/// Accent colours specific to the paywall.
const Color _gold = Color(0xFFFFD24A);
const Color _selectedBorder = Color(0xFF2E7D4F);
const Color _brightGreen = Color(0xFF4CAF72);

/// Paywall shown when a free user hits [kFreeSubscriptionLimit].
///
/// Pops with `true` once premium has been granted, so the caller can resume the
/// action the user was blocked from (adding another subscription). Pops with
/// `false`/null if dismissed.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  static const route = '/paywall';

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  // Default to the best-value plan.
  PlanId _selected = PlanId.lifetime;
  bool _busy = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  Future<void> _purchase() async {
    setState(() => _busy = true);
    final result = await PurchaseService.instance.purchase(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else if (result.status != PurchaseStatus.cancelled) {
      _snack(_isLt
          ? 'Pirkimas nepavyko. Bandykite dar kartą.'
          : 'Purchase failed. Please try again.');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await PurchaseService.instance.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      _snack(_isLt
          ? 'Nerasta ankstesnių pirkimų.'
          : 'No previous purchase found.');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    final ctaLabel = _selected == PlanId.lifetime
        ? (isLt
            ? 'Pirkti visam laikui už ${PurchaseService.planFor(PlanId.lifetime).price}'
            : 'Get lifetime for ${PurchaseService.planFor(PlanId.lifetime).price}')
        : (isLt
            ? 'Prenumeruoti už ${PurchaseService.planFor(PlanId.monthly).price}/mėn.'
            : 'Subscribe for ${PurchaseService.planFor(PlanId.monthly).price}/mo');

    return Scaffold(
      backgroundColor: VaultieColors.primary,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Premium badge — gold diamond inside a gold-tinted circle.
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.diamond_rounded,
                        color: _gold,
                        size: 50,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    isLt
                        ? 'Atrakinkite Vaultie Premium'
                        : 'Unlock Vaultie Premium',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isLt
                        ? 'Pasiekėte nemokamą $kFreeSubscriptionLimit prenumeratų limitą. Atnaujinkite, kad pridėtumėte daugiau.'
                        : "You've reached the free limit of $kFreeSubscriptionLimit subscriptions. Upgrade to add more.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 17,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _feature(isLt
                      ? 'Neribotas prenumeratų skaičius'
                      : 'Unlimited subscriptions'),
                  _feature(isLt
                      ? 'Visos būsimos funkcijos'
                      : 'Every future feature'),
                  _feature(isLt
                      ? 'Palaikote kūrimą'
                      : 'Support ongoing development'),
                  const SizedBox(height: 32),
                  _planCard(PlanId.lifetime, isLt),
                  const SizedBox(height: 14),
                  _planCard(PlanId.monthly, isLt),
                  const SizedBox(height: 32),
                  _CtaButton(
                    label: ctaLabel,
                    busy: _busy,
                    onPressed: _busy ? null : _purchase,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _busy ? null : _restore,
                    child: Text(
                      isLt ? 'Atkurti pirkimą' : 'Restore purchase',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLt
                        ? 'Bandomasis režimas — tikri mokėjimai dar neįjungti.'
                        : 'Demo mode — no real payment is charged yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Dismiss.
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _brightGreen, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(PlanId id, bool isLt) {
    final plan = PurchaseService.planFor(id);
    final selected = _selected == id;
    final lifetime = id == PlanId.lifetime;
    final title = lifetime
        ? (isLt ? 'Visam laikui' : 'Lifetime')
        : (isLt ? 'Mėnesinis' : 'Monthly');
    final period = lifetime
        ? (isLt ? 'vienkartinis mokėjimas' : 'one-time payment')
        : (isLt ? 'per mėnesį' : 'per month');

    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _selected = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          // Cards are darker than the background; the border signals selection.
          color: VaultieColors.primaryDark,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? _selectedBorder : Colors.white,
            width: selected ? 2.5 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? _brightGreen : Colors.white54,
              size: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      lifetime
                          ? _badge(
                              isLt ? 'Geriausia vertė' : 'Best Value',
                              background: _gold,
                              foreground: VaultieColors.primaryDark,
                            )
                          : _badge(
                              isLt ? 'Populiariausias' : 'Most Popular',
                              background: _brightGreen,
                              foreground: Colors.white,
                            ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    period,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              plan.price,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text,
      {required Color background, required Color foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Full-width call-to-action styled to pop against the dark-green background.
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.busy, this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _brightGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _brightGreen.withValues(alpha: 0.6),
        minimumSize: const Size.fromHeight(58),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}
