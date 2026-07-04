import 'package:flutter/material.dart';

import '../main.dart';
import '../services/purchase_service.dart';
import 'dashboard_screen.dart';
import 'legal_screen.dart';

/// Accent colours specific to the paywall.
const Color _gold = Color(0xFFFFD24A);
const Color _brightGreen = Color(0xFF4CAF72);

/// Paywall shown when a free user hits [kFreeSubscriptionLimit].
///
/// Pops with `true` once premium has been granted, so the caller can resume the
/// action the user was blocked from (adding another subscription). Pops with
/// `false`/null if dismissed.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.reachedFreeLimit = false});

  static const route = '/paywall';

  /// True when opened because the user hit the free subscription limit — shows
  /// the "you've reached the limit" copy. False for a voluntary upgrade (e.g.
  /// from Settings), which shows a neutral value pitch instead.
  final bool reachedFreeLimit;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  // Default to the best-value plan.
  PlanId _selected = PlanId.lifetime;
  bool _busy = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  /// Dismisses the paywall. Normally this pops back to whatever pushed it (the
  /// dashboard). If the paywall happens to be the only route on the stack,
  /// popping would leave an empty navigator (black screen), so we fall back to
  /// showing the dashboard instead.
  void _dismiss() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(false);
    } else {
      nav.pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  /// Buys the selected plan. On success, pops with `true` so the caller can
  /// resume the blocked action. Cancellations are silent; other failures show
  /// a message.
  Future<void> _purchase() async {
    final isLt = _isLt;
    setState(() => _busy = true);
    final result = await PurchaseService.instance.purchase(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else if (result.status != PurchaseStatus.cancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ??
              (isLt ? 'Pirkimas nepavyko.' : 'Purchase failed.')),
          backgroundColor: VaultieColors.danger,
        ),
      );
    }
  }

  /// Restores a previous purchase. Pops with `true` if one is found.
  Future<void> _restore() async {
    final isLt = _isLt;
    setState(() => _busy = true);
    final result = await PurchaseService.instance.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isLt ? 'Pirkimas atkurtas.' : 'Purchase restored.'),
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              isLt ? 'Nerasta pirkimų atkurti.' : 'No purchases to restore.'),
        ),
      );
    }
  }

  /// Live store price for [id], falling back to the static plan price until
  /// RevenueCat offerings have loaded.
  String _priceFor(PlanId id) =>
      PurchaseService.instance.priceString(id) ??
      PurchaseService.planFor(id).price;

  /// Opens the in-app Terms of Use or Privacy Policy document.
  void _openLegal({required bool terms}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            terms ? LegalScreen.terms(_isLt) : LegalScreen.privacy(_isLt),
      ),
    );
  }

  /// An underlined, tappable legal link used in the paywall footer.
  Widget _legalLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    // CTA reflects the selected plan and its price.
    final price = _priceFor(_selected);
    final ctaLabel = _selected == PlanId.lifetime
        ? (isLt ? 'Pirkti — $price' : 'Unlock — $price')
        : (isLt ? 'Prenumeruoti — $price/mėn.' : 'Subscribe — $price/mo');

    return PopScope(
      // Intercept the system back button/gesture so it routes through _dismiss
      // (which falls back to the dashboard) rather than popping to a black
      // screen when the paywall is the only route.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050F08),
        body: SafeArea(
          child: Stack(
            children: [
              // Deep-green radial spotlight up top, matching splash/auth —
              // richer and more premium than the old flat green.
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
                padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Premium badge — the app logo with a soft gold halo.
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: _gold.withValues(alpha: 0.30),
                              blurRadius: 34,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/icon/app_icon.png',
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
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
                      widget.reachedFreeLimit
                          ? (isLt
                              ? 'Pasiekėte nemokamą $kFreeSubscriptionLimit prenumeratų limitą. Atnaujinkite, kad pridėtumėte daugiau.'
                              : "You've reached the free limit of $kFreeSubscriptionLimit subscriptions. Upgrade to add more.")
                          : (isLt
                              ? 'Atrakinkite visas Vaultie galimybes ir valdykite savo išlaidas be jokių ribų.'
                              : 'Unlock everything Vaultie offers and manage your spending without limits.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 17,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _feature(isLt
                        ? 'Neribotas prenumeratų ir sąskaitų skaičius'
                        : 'Unlimited subscriptions & bills'),
                    _feature(isLt
                        ? 'Išsami išlaidų analitika ir grafikai'
                        : 'Full spending analytics & charts'),
                    _feature(isLt
                        ? 'Mokėjimų priminimai kiekvienai prenumeratai'
                        : 'Payment reminders for every subscription'),
                    _feature(isLt
                        ? 'Biudžeto sekimas ir mėnesio apžvalga'
                        : 'Budget tracking & monthly recap'),
                    _feature(isLt
                        ? 'Visos būsimos funkcijos — įtrauktos'
                        : 'Every future feature included'),
                    _feature(isLt
                        ? 'Palaikote nepriklausomą kūrėją'
                        : 'Support an indie developer'),
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
                    const SizedBox(height: 6),
                    // Restore purchases — required for App Store approval so
                    // users can re-entitle on a new device.
                    TextButton(
                      onPressed: _busy ? null : _restore,
                      child: Text(
                        isLt ? 'Atkurti pirkimus' : 'Restore purchases',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Auto-renewable subscription disclosure required by App
                    // Store Guideline 3.1.2. Prices reflect the live store
                    // price (falling back to the static plan price).
                    Text(
                      isLt
                          ? 'Vaultie Pro Mėnesinė (${_priceFor(PlanId.monthly)}/mėn.) '
                              'yra automatiškai atsinaujinanti prenumerata: ji '
                              'atsinaujina ta pačia kaina kiekvieną laikotarpį, '
                              'nebent atšaukiama likus ne mažiau kaip 24 val. iki '
                              'laikotarpio pabaigos. „Visam laikui" '
                              '(${_priceFor(PlanId.lifetime)}) — vienkartinis '
                              'pirkimas. Mokėjimas nuskaičiuojamas iš „Apple ID" '
                              'ir valdomas „App Store" nustatymuose.'
                          : 'Vaultie Pro Monthly (${_priceFor(PlanId.monthly)}/month) '
                              'is an auto-renewable subscription that renews at '
                              'the same price each period unless cancelled at '
                              'least 24 hours before the period ends. Lifetime '
                              '(${_priceFor(PlanId.lifetime)}) is a one-time '
                              'purchase. Payment is charged to your Apple ID and '
                              'can be managed in your App Store settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Functional Terms + Privacy links, required on the purchase
                    // screen itself (Guideline 3.1.2).
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _legalLink(
                          isLt ? 'Naudojimo sąlygos' : 'Terms of Use',
                          () => _openLegal(terms: true),
                        ),
                        Text(
                          '   •   ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                        _legalLink(
                          isLt ? 'Privatumo politika' : 'Privacy Policy',
                          () => _openLegal(terms: false),
                        ),
                      ],
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
                  onPressed: _busy ? null : _dismiss,
                ),
              ),
            ],
          ),
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
    final selected = _selected == id;
    final lifetime = id == PlanId.lifetime;
    final title = lifetime
        ? (isLt ? 'Visam laikui' : 'Lifetime')
        : (isLt ? 'Mėnesinis' : 'Monthly');
    final period = lifetime
        ? (isLt ? 'vienkartinis mokėjimas' : 'one-time payment')
        : (isLt ? 'per mėnesį' : 'per month');
    final price = _priceFor(id);

    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _selected = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          // The selected plan pops: a green→dark gradient, an accent border and
          // a coloured glow. Unselected plans stay muted so the eye is drawn to
          // the recommended choice.
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1C5E3A), Color(0xFF0E3322)],
                )
              : null,
          color: selected ? null : const Color(0xFF0C1F15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? (lifetime ? _gold : _brightGreen)
                : Colors.white.withValues(alpha: 0.14),
            width: selected ? 2.5 : 1.5,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: (lifetime ? _gold : _brightGreen)
                        .withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: -2,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color:
                  selected ? (lifetime ? _gold : _brightGreen) : Colors.white38,
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
            const SizedBox(width: 12),
            Text(
              price,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
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
        elevation: 12,
        shadowColor: _brightGreen,
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
