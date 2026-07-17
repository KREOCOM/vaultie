import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../theme/vaultie_theme.dart';

/// The two subscription plans shown on the paywall. No "lifetime" — the updated
/// monetization is yearly + monthly, both with a 7-day free trial.
enum PaywallPlan { annual, monthly }

/// Onboarding paywall — shown when the user takes the bank path ("Prijungti
/// banką") or hits the free limit (adding a 6th subscription).
///
/// UI is decoupled from billing: prices come in as strings (RevenueCat Offering
/// at integration time, placeholders until then) and the purchase itself runs
/// through the injected [onPurchase]. When [onPurchase] is null the CTA runs a
/// mock purchase so the flow is testable without RevenueCat configured.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.onSubscribed,
    required this.onClose,
    this.onPurchase,
    this.annualPrice = '€29,99',
    this.annualPerMonth = '€2,50/mėn',
    this.annualBadge = 'SUTAUPAI 37%',
    this.monthlyPrice = '€3,99',
  });

  /// Called after a successful purchase (or mock) with the chosen plan — the
  /// host continues into the bank-connect flow (or back to the app for the
  /// 6th-subscription case).
  final ValueChanged<PaywallPlan> onSubscribed;

  /// ✕ — dismiss without buying. Bank path → back to "Two paths"; limit case →
  /// back to the app on the free tier.
  final VoidCallback onClose;

  /// Real purchase hook, injected at integration:
  ///   onPurchase: (plan) async =>
  ///       (await PurchaseService.instance.purchase(mapToPlanId(plan))).isSuccess
  /// When null, the CTA performs a mock purchase (always succeeds).
  final Future<bool> Function(PaywallPlan plan)? onPurchase;

  final String annualPrice;
  final String annualPerMonth;
  final String annualBadge;
  final String monthlyPrice;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PaywallPlan _plan = PaywallPlan.annual; // annual selected by default
  bool _busy = false;

  static const _benefits = [
    'Automatiškai suranda prenumeratas',
    'Įspėja prieš artėjančius mokėjimus',
    'Parodo, kur iš tikrųjų išleidi pinigus',
    'Viskas vienoje vietoje – be rankinio darbo',
  ];

  static const _finePrint =
      '7 dienos nemokamai. Atšaukus iki bandomojo laikotarpio pabaigos, '
      'mokestis nebus nuskaičiuotas. Vėliau taikomas pasirinkto plano mokestis, '
      'kol atsisakysi App Store nustatymuose.';

  Future<void> _startTrial() async {
    if (_busy) return;
    setState(() => _busy = true);
    bool ok;
    if (widget.onPurchase != null) {
      ok = await widget.onPurchase!(_plan);
    } else {
      // Mock purchase — no RevenueCat configured (preview/testing).
      await Future<void>.delayed(const Duration(milliseconds: 900));
      ok = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onSubscribed(_plan);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Pirkimas nepavyko. Bandyk dar kartą.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: VT.canvasGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Close (top-right), nothing on the left.
                        Align(
                          alignment: Alignment.centerRight,
                          child: _CloseButton(onTap: widget.onClose),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr('Leisk Vaultie pasirūpinti tavo prenumeratomis.'),
                          style: const TextStyle(
                            color: VT.ink,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            height: 1.18,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const Spacer(flex: 3),
                        for (var i = 0; i < _benefits.length; i++) ...[
                          _BenefitRow(text: tr(_benefits[i])),
                          if (i != _benefits.length - 1)
                            const SizedBox(height: 20),
                        ],
                        const Spacer(flex: 3),
                        _PlanCard(
                          title: tr('Metinis'),
                          trialSub: tr('7 dienos nemokamai'),
                          price: widget.annualPrice,
                          priceSub: widget.annualPerMonth,
                          badge: widget.annualBadge,
                          selected: _plan == PaywallPlan.annual,
                          onTap: () =>
                              setState(() => _plan = PaywallPlan.annual),
                        ),
                        const SizedBox(height: 12),
                        _PlanCard(
                          title: tr('Mėnesinis'),
                          trialSub: tr('7 dienos nemokamai'),
                          price: widget.monthlyPrice,
                          priceSub: '/mėn',
                          selected: _plan == PaywallPlan.monthly,
                          onTap: () =>
                              setState(() => _plan = PaywallPlan.monthly),
                        ),
                        const Spacer(flex: 2),
                        _CtaButton(
                          label: tr('Pradėti 7 dienų bandymą'),
                          busy: _busy,
                          onTap: _startTrial,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          tr(_finePrint),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: VT.subtle.withValues(alpha: 0.85),
                            fontSize: 11,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE7ECE6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.close_rounded, size: 19, color: VT.subtle),
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.check_rounded, size: 20, color: VT.accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: VT.ink,
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.trialSub,
    required this.price,
    required this.priceSub,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String trialSub;
  final String price;
  final String priceSub;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  static const _selectedBg = Color(0xFFEAF6EE);

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: selected ? _selectedBg : VT.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? _selectedBg : VT.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? VT.brand : VT.line,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: VT.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(trialSub,
                          style: const TextStyle(
                              color: VT.subtle,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(price,
                        style: const TextStyle(
                            color: VT.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(tr(priceSub),
                        style: const TextStyle(
                            color: VT.subtle,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(width: 14),
                _Radio(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );

    if (badge == null) return card;
    // Badge overlaps the top edge of the card, on the right.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(top: 9), child: card),
        Positioned(
          top: -1,
          right: 48,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: VT.brand,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(tr(badge!),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3)),
          ),
        ),
      ],
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? VT.brand : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? VT.brand : const Color(0xFFCBD5CC),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.busy, required this.onTap});
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: VT.heroGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: VT.buttonShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: busy ? null : onTap,
            child: SizedBox(
              height: 48,
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
