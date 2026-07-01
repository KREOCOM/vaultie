import 'package:flutter/material.dart';

import '../main.dart';
import '../services/purchase_service.dart';

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
                  // Premium badge.
                  Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: VaultieColors.accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: VaultieColors.accent,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isLt
                        ? 'Atrakinkite Vaultie Premium'
                        : 'Unlock Vaultie Premium',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isLt
                        ? 'Pasiekėte nemokamą $kFreeSubscriptionLimit prenumeratų limitą. Atnaujinkite, kad pridėtumėte daugiau.'
                        : "You've reached the free limit of $kFreeSubscriptionLimit subscriptions. Upgrade to add more.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _feature(isLt
                      ? 'Neribotas prenumeratų skaičius'
                      : 'Unlimited subscriptions'),
                  _feature(isLt
                      ? 'Visos būsimos funkcijos'
                      : 'Every future feature'),
                  _feature(isLt
                      ? 'Palaikote kūrimą'
                      : 'Support ongoing development'),
                  const SizedBox(height: 28),
                  _planCard(PlanId.lifetime, isLt),
                  const SizedBox(height: 12),
                  _planCard(PlanId.monthly, isLt),
                  const SizedBox(height: 28),
                  _CtaButton(
                    label: ctaLabel,
                    busy: _busy,
                    onPressed: _busy ? null : _purchase,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _restore,
                    child: Text(
                      isLt ? 'Atkurti pirkimą' : 'Restore purchase',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: VaultieColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(PlanId id, bool isLt) {
    final plan = PurchaseService.planFor(id);
    final selected = _selected == id;
    final title = id == PlanId.lifetime
        ? (isLt ? 'Visam laikui' : 'Lifetime')
        : (isLt ? 'Mėnesinis' : 'Monthly');
    final period = id == PlanId.lifetime
        ? (isLt ? 'vienkartinis mokėjimas' : 'one-time payment')
        : (isLt ? 'per mėnesį' : 'per month');

    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _selected = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? VaultieColors.accent : Colors.white24,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? VaultieColors.primary : Colors.white54,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected ? VaultieColors.ink : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (id == PlanId.lifetime) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: VaultieColors.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isLt ? 'GERIAUSIA' : 'BEST VALUE',
                            style: const TextStyle(
                              color: VaultieColors.primaryDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    period,
                    style: TextStyle(
                      color: selected
                          ? VaultieColors.subtle
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              plan.price,
              style: TextStyle(
                color: selected ? VaultieColors.primary : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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
        backgroundColor: VaultieColors.accent,
        foregroundColor: VaultieColors.primaryDark,
        disabledBackgroundColor: VaultieColors.accent.withValues(alpha: 0.6),
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: VaultieColors.primaryDark,
              ),
            )
          : Text(label),
    );
  }
}
