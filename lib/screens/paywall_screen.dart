import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/purchase_service.dart';
import 'dashboard_screen.dart';
import 'legal_screen.dart';

/// Accent colours specific to the paywall.
const Color _gold = Color(0xFFFFD24A);
const Color _brightGreen = Color(0xFF4CAF72);

/// UI-ONLY: shows the Bilance-style "How your free trial works" timeline.
///
/// ⚠️ Off by default: the current RevenueCat products do NOT include a trial.
/// Only flip this to `true` after a real 7-day introductory (free-trial) offer
/// is configured on the monthly subscription in App Store Connect + RevenueCat.
/// Advertising a trial that doesn't exist risks App Store rejection
/// (Guideline 3.1.2) and breaks user trust.
const bool kShowTrialTimeline = false;

/// Apple's standard End User License Agreement, required as a functional link
/// on the purchase screen when using Apple's default EULA (Guideline 3.1.2).
const String kAppleStandardEulaUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

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

  /// Opens Apple's standard EULA in the browser. Required as a functional link
  /// on the purchase screen (Guideline 3.1.2). Falls back to a snackbar if no
  /// browser can handle the URL.
  Future<void> _openEula() async {
    final isLt = _isLt;
    final ok = await launchUrl(
      Uri.parse(kAppleStandardEulaUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isLt
              ? 'Nepavyko atidaryti nuorodos.'
              : "Couldn't open the link."),
        ),
      );
    }
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

  /// The "•" separator between footer legal links.
  Widget _legalDot() {
    return Text(
      '   •   ',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    // CTA reflects the selected plan and its price.
    final price = _priceFor(_selected);
    // With the trial timeline on, the monthly plan leads with the free-trial CTA
    // (the trial only applies to the auto-renewing subscription, not Lifetime).
    final ctaLabel = kShowTrialTimeline && _selected == PlanId.monthly
        ? (isLt ? 'Pradėti 7 d. nemokamą bandymą' : 'Start my 7-day free trial')
        : _selected == PlanId.lifetime
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
                    const SizedBox(height: 22),
                    // Plans + CTA up top so the price is reachable without
                    // scrolling past the whole value section (the features and
                    // trial timeline read as supporting detail below).
                    Row(
                      children: [
                        _planPill(PlanId.lifetime, isLt),
                        const SizedBox(width: 10),
                        _planPill(PlanId.monthly, isLt),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _CtaButton(
                      label: ctaLabel,
                      busy: _busy,
                      onPressed: _busy ? null : _purchase,
                    ),
                    const SizedBox(height: 30),
                    _feature(isLt
                        ? 'Prijunkite banką — automatiškai raskite pasikartojančius mokėjimus'
                        : 'Connect your bank — auto-detect recurring payments'),
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
                        ? 'Duomenų eksportas (CSV)'
                        : 'Export your data (CSV)'),
                    _feature(isLt
                        ? 'Visos būsimos funkcijos — įtrauktos'
                        : 'Every future feature included'),
                    _feature(isLt
                        ? 'Palaikote nepriklausomą kūrėją'
                        : 'Support an indie developer'),
                    if (kShowTrialTimeline) _trialTimeline(isLt),
                    const SizedBox(height: 24),
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
                    // Functional Terms, EULA + Privacy links, required on the
                    // purchase screen itself (Guideline 3.1.2). Wrap keeps all
                    // three from overflowing on narrow screens.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _legalLink(
                          isLt ? 'Naudojimo sąlygos' : 'Terms of Use',
                          () => _openLegal(terms: true),
                        ),
                        _legalDot(),
                        _legalLink('EULA', _openEula),
                        _legalDot(),
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

  /// "How your free trial works" — a Bilance-style vertical timeline that makes
  /// the auto-renew moment transparent (Today → reminder → billing), which is
  /// what turns a card-committed trial into trust instead of a nasty surprise.
  Widget _trialTimeline(bool isLt) {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1F15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLt ? 'Kaip veikia nemokamas bandymas' : 'How your free trial works',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 18),
          _trialStep(
            icon: Icons.lock_open_rounded,
            title: isLt ? 'Šiandien' : 'Today',
            sub: isLt
                ? 'Pilna prieiga prie visų Vaultie Pro funkcijų.'
                : 'Full access to everything in Vaultie Pro.',
          ),
          _trialStep(
            icon: Icons.notifications_active_rounded,
            title: isLt ? '5 diena' : 'Day 5',
            sub: isLt
                ? 'Priminsime, kad nemokamas bandymas netrukus baigsis.'
                : 'We\'ll remind you your free trial is ending soon.',
          ),
          _trialStep(
            icon: Icons.star_rounded,
            title: isLt ? '7 diena' : 'Day 7',
            sub: isLt
                ? 'Prasideda prenumerata. Atšauk bet kada iki tol.'
                : 'Your subscription starts. Cancel anytime before.',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _trialStep({
    required IconData icon,
    required String title,
    required String sub,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _brightGreen.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: _brightGreen, width: 1.5),
                ),
                child: Icon(icon, color: _brightGreen, size: 18),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: _brightGreen.withValues(alpha: 0.30),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 6 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A compact, tappable plan card sized to sit two-up in a Row, so the price
  /// is visible high on the paywall instead of buried below the value section.
  Widget _planPill(PlanId id, bool isLt) {
    final selected = _selected == id;
    final lifetime = id == PlanId.lifetime;
    final accent = lifetime ? _gold : _brightGreen;
    final title = lifetime
        ? (isLt ? 'Visam laikui' : 'Lifetime')
        : (isLt ? 'Mėnesinis' : 'Monthly');
    final period = lifetime
        ? (isLt ? 'vienkart.' : 'one-time')
        : (isLt ? '/mėn.' : '/mo');
    final tag = lifetime
        ? (isLt ? 'Geriausia' : 'Best value')
        : (isLt ? 'Populiaru' : 'Popular');

    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _selected = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1C5E3A), Color(0xFF0E3322)],
                  )
                : null,
            color: selected ? null : const Color(0xFF0C1F15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.14),
              width: selected ? 2 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 18,
                      spreadRadius: -3,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag.toUpperCase(),
                  style: TextStyle(
                    color: lifetime ? VaultieColors.primaryDark : Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      _priceFor(id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    period,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
