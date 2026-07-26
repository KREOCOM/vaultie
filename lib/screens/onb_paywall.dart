import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/auth_service.dart';
import '../services/purchase_service.dart';
import '../user_session.dart';
import 'legal_screen.dart';
import 'login_screen.dart';

/// The paywall, copied from the reference.
///
/// This screen charges for real: "Tęsti" buys the selected plan through
/// [PurchaseService] and only advances once the entitlement is granted.
///
/// Vaultie is subscription-only, so this is a real gate: there is nothing
/// behind it without a plan. The close button signs the user out and returns
/// them to sign-in rather than advancing — it is a way out, not a way in.
///
/// The prices shown are the live, localized store prices when the RevenueCat
/// offering has loaded, falling back to [_monthly]/[_yearly] otherwise. The
/// derived figures (savings, discount %) are always computed from those EUR
/// constants — they are display-only and the app is EUR-first, but they will
/// read slightly off in regions Apple prices non-proportionally.
///
/// Two departures from the reference, both deliberate:
///
///  * The reference footer promises only "Saugus mokėjimas per App Store".
///    Apple requires the renewal terms, links to Terms and Privacy, and a
///    restore control on any subscription screen; without them review fails.
///    Those are added below the button.
///  * Five feature labels on a 390pt screen leave 70pt each, so the long ones
///    ("Išlaidų ir biudžetų sekimas") are shortened rather than shrunk to an
///    unreadable size.
class OnbPaywall extends StatefulWidget {
  const OnbPaywall({super.key, required this.next, this.onClose});

  final Widget next;
  final VoidCallback? onClose;

  @override
  State<OnbPaywall> createState() => _OnbPaywallState();
}

const _ink = Color(0xFFFFFFFF);
const _sub = Color(0xFF93A3C4);
const _paper = Color(0xFF00082D);
const _blue = Color(0xFF003DE1);
const _blueBright = Color(0xFF0A4DFD);
const _green = Color(0xFF25C26B);
const _greenSoft = Color(0xFF071B12);

// One source for the money: every other figure on the screen is derived.
const _monthly = 4.99;
const _yearly = 39.99;
const double _yearOfMonthly = _monthly * 12;             // 59,88
const double _saving = _yearOfMonthly - _yearly;         // 19,89
final int _discount = (_saving / _yearOfMonthly * 100).round();  // 33
const double _yearlyPerMonth = _yearly / 12;             // 3,33

String _eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

class _OnbPaywallState extends State<OnbPaywall> {
  bool _annual = true;
  bool _busy = false;
  // Guards against advancing twice: purchase()/restore() flip premium synchronously,
  // which fires the entitlement listener → _advance BEFORE the await returns, then
  // the explicit success handler calls _advance again → two pushReplacements (double
  // BankConnectScreen + a double bank-list fetch, and a possible route assertion).
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    // If the entitlement is already there, or arrives while this screen is up,
    // don't sit on a paywall a paying user has no reason to see. It can arrive
    // late — an offline launch seeded from the cached flag, then confirmed by
    // the network; a renewal pushed from another device — and nothing here
    // listened, so a subscriber could be stranded on it until they tapped
    // Restore.
    final premium = PurchaseService.instance.isPremiumListenable;
    if (premium.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
      return;
    }
    premium.addListener(_onPremiumChanged);
  }

  void _onPremiumChanged() {
    if (mounted && PurchaseService.instance.isPremiumListenable.value) {
      _advance();
    }
  }

  @override
  void dispose() {
    PurchaseService.instance.isPremiumListenable.removeListener(_onPremiumChanged);
    super.dispose();
  }

  PlanId get _plan => _annual ? PlanId.yearly : PlanId.monthly;

  /// Live store price for [id], falling back to the constant above until the
  /// RevenueCat offering has loaded (or if it never does).
  String _priceFor(PlanId id) =>
      PurchaseService.instance.priceString(id) ??
      _eur(id == PlanId.yearly ? _yearly : _monthly);

  /// Free-trial length for [id], straight from the store product. Null until
  /// the offer actually exists in App Store Connect — every bit of trial copy
  /// on this screen is gated on it, so the paywall cannot promise a trial the
  /// store won't honour.
  int? _trialFor(PlanId id) => PurchaseService.instance.freeTrialDays(id);

  /// "7 dienos nemokamai" / "7 days free".
  String _trialLabel(int days) => '$days ${tr('d. nemokamai')}';

  void _advance() {
    if (_advanced || !mounted) return;
    _advanced = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

  /// Buys the selected plan, advancing only once premium is actually granted.
  ///
  /// A cancelled purchase is silent — the user is still on the paywall and can
  /// pick again or skip. Everything else explains itself and stays put: a
  /// paywall that advances on failure is indistinguishable from one that works,
  /// which is exactly the trap the old unwired paywall fell into.
  Future<void> _buy() async {
    setState(() => _busy = true);
    final result = await PurchaseService.instance.purchase(_plan);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result.status) {
      case PurchaseStatus.success:
        _advance();
      case PurchaseStatus.pending:
        // Deferred/Ask-to-Buy/SCA, or the entitlement hasn't landed yet. The
        // listener auto-advances when it does — say "processing", not "failed",
        // so the user doesn't try to buy again.
        _toast(tr('Pirkimas apdorojamas — palauk akimirką.'));
      case PurchaseStatus.cancelled:
        break;
      case PurchaseStatus.notFound:
        // Offerings never loaded: offline, or the products aren't live in App
        // Store Connect yet. There is no "skip" here — say to retry when online.
        _toast(tr('Planai kol kas nepasiekiami. Bandyk vėliau.'));
      case PurchaseStatus.error:
        _toast(result.message ?? tr('Pirkimas nepavyko. Bandyk dar kartą.'));
    }
  }

  /// Closing the paywall signs the user out and returns them to the start.
  ///
  /// Vaultie is subscription-only: there is nothing behind this screen without
  /// a plan. Dismissing used to advance to the next screen, which handed out
  /// the whole app for free to anyone who tapped the X. Closing must therefore
  /// cost the session rather than grant access — the user is not trapped, but
  /// they do not get in either.
  Future<void> _exit() async {
    setState(() => _busy = true);
    try {
      await AuthService().signOut();
      await onSignedOut();
    } catch (_) {
      // Sign-out is best-effort; leaving the paywall must still work.
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (r) => false,
    );
  }

  /// Restores a previous purchase — required on any subscription screen, and
  /// the path back to premium for anyone reinstalling or on a new device.
  Future<void> _restore() async {
    setState(() => _busy = true);
    final result = await PurchaseService.instance.restore();
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.isSuccess) {
      _toast(tr('Pirkimas atkurtas.'));
      _advance();
    } else {
      _toast(tr('Nerasta pirkimų atkurti.'));
    }
  }

  void _openLegal({required bool terms}) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => terms ? LegalScreen.terms(isLt) : LegalScreen.privacy(isLt),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: Stack(
        children: [
          // The render's mark, card and chart sit in its top quarter; the rest
          // is empty, which is where the plans go.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset('assets/onboarding/paywall_hero.png',
                fit: BoxFit.fitWidth),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x0000082D),
                      Color(0x0000082D),
                      Color(0xCC00082D),
                      _paper,
                    ],
                    stops: [0, 0.13, 0.19, 0.25],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // close
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 26, color: _sub),
                    // Signs out and returns to the start — never a free pass.
                    onPressed: _busy ? null : (widget.onClose ?? _exit),
                  ),
                ),
                // Scrolls on purpose: this is the densest screen in the app and
                // a short phone must not clip the plans or the legal text.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      children: [
                        // Clears the render's artwork above.
                        SizedBox(
                            height: MediaQuery.of(context).size.width *
                                1844 /
                                853 *
                                0.135),
                        // "Premium" carries the brand blue — it is the word the
                        // screen is selling.
                        const Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'Vaultie '),
                            TextSpan(
                                text: 'Premium',
                                style: TextStyle(color: _blueBright)),
                          ]),
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.8),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tr('Visos funkcijos vienoje vietoje.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13.5, height: 1.45, color: _sub),
                        ),
                        // Plans first: the price is the decision, and on a short
                        // phone it used to sit below three feature cards where
                        // it had to be scrolled to.
                        const SizedBox(height: 16),
                        _planCard(
                          annual: true,
                          title: tr('Metinis planas'),
                          price: _priceFor(PlanId.yearly),
                          period: tr('/ metus'),
                          trialDays: _trialFor(PlanId.yearly),
                          chip: '${_eur(_yearlyPerMonth)} ${tr('/ mėn.')}',
                        ),
                        const SizedBox(height: 10),
                        _planCard(
                          annual: false,
                          title: tr('Mėnesinis planas'),
                          price: _priceFor(PlanId.monthly),
                          period: tr('/ mėn.'),
                          chip: '${_eur(_yearOfMonthly)} ${tr('per metus')}',
                          trialDays: _trialFor(PlanId.monthly),
                        ),
                        _trialLine(),
                        const SizedBox(height: 14),
                        _features(),
                      ],
                    ),
                  ),
                ),
                _bottom(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _features() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in [
            (Icons.bar_chart_rounded, tr('AI finansų\nanalizė')),
            (Icons.pie_chart_rounded, tr('Išlaidų\nsekimas')),
            (Icons.account_balance_wallet_rounded, tr('Prenumeratų\nsekimas')),
            (Icons.lightbulb_rounded, tr('Išmanios\nįžvalgos')),
            (Icons.shield_rounded, tr('Neriboti\nbankai')),
          ])
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF07231A),
                      borderRadius: BorderRadius.circular(13),
                      border:
                          Border.all(color: _green.withValues(alpha: 0.40)),
                    ),
                    child: Icon(f.$1, size: 22, color: _green),
                  ),
                  const SizedBox(height: 7),
                  Text(f.$2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 9.5, height: 1.3, fontWeight: FontWeight.w600, color: _ink)),
                ],
              ),
            ),
        ],
      );

  Widget _planCard({
    required bool annual,
    required String title,
    required String price,
    required String period,
    required String chip,
    int? trialDays,
  }) {
    final on = _annual == annual;
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _annual = annual),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF07184A) : const Color(0xFF041038),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: on ? _blue : const Color(0xFF17275C), width: on ? 1.8 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (annual)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: _blue, borderRadius: BorderRadius.circular(7)),
                      child: Text(tr('POPULIARUS PASIRINKIMAS'),
                          style: const TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w800,
                              color: Colors.white, letterSpacing: 0.4)),
                    ),
                    const Spacer(),
                    // The saving was a green slab of its own under both plans,
                    // which read as a third option. It belongs to this plan, so
                    // it sits in it.
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: _greenSoft,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color: _green.withValues(alpha: 0.45))),
                      child: Text(
                          '${tr('Sutaupai')} ${_eur(_saving)}',
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _green)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: on ? _blue : const Color(0xFF3A4A6B), width: 2),
                  ),
                  child: on
                      ? Container(
                          width: 11, height: 11,
                          decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w800,
                              color: on ? const Color(0xFF9FC0FF) : _ink)),
                      const SizedBox(height: 2),
                      Text(
                          trialDays != null
                              ? _trialLabel(trialDays)
                              : tr('Visos Premium funkcijos.'),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  trialDays != null ? FontWeight.w800 : null,
                              color: trialDays != null ? _green : _sub)),
                      if (annual) ...[
                        const SizedBox(height: 3),
                        Text('${tr('Sutaupyk')} $_discount %',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800, color: _green)),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (annual)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration:
                            BoxDecoration(color: _green, borderRadius: BorderRadius.circular(6)),
                        child: Text('−$_discount %',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(price,
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800,
                                color: on ? _blue : _ink, letterSpacing: -0.5)),
                        const SizedBox(width: 3),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(period, style: const TextStyle(fontSize: 11.5, color: _sub)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: annual ? _greenSoft : const Color(0xFFEDF1FD),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(chip,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: annual ? _green : _blueBright)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The trial promise, directly under the plans it applies to rather than at
  /// the foot of the screen — it is part of choosing a plan, not part of the
  /// button. The green half appears ONLY when the store confirmed this Apple ID
  /// is still eligible; everyone else gets the cancellation line, which is true
  /// either way. See PurchaseService._loadTrials for why eligibility is asked
  /// rather than assumed.
  Widget _trialLine() {
    final trial = _trialFor(_plan);
    if (trial == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(
          child: Text(tr('Atšaukti gali bet kada.'),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: _sub)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _greenSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_open_rounded, size: 17, color: _green),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${tr('Išbandyk')} $trial ${tr('d. nemokamai')} · ${tr('atšaukti gali bet kada')}',
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: _green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Button plus the disclosures Apple requires on a subscription screen.
  Widget _bottom() {
    final plan = _annual ? tr('Metinis planas') : tr('Mėnesinis planas');
    final price = _priceFor(_plan);
    final per = _annual ? tr('metams') : tr('mėnesiui');
    final trial = _trialFor(_plan);
    // Apple requires the trial length, what happens after it, and the renewal
    // terms on the purchase screen itself (Guideline 3.1.2).
    final terms = trial != null
        ? '$plan — ${tr('pirmos')} $trial ${tr('d. nemokamai, tada')} $price / $per. '
            '${tr('Atsinaujina automatiškai, kol neatšauksi App Store nustatymuose likus ne mažiau kaip 24 val. iki laikotarpio pabaigos.')}'
        : '$plan — $price / $per. '
            '${tr('Atsinaujina automatiškai, kol neatšauksi App Store nustatymuose likus ne mažiau kaip 24 val. iki laikotarpio pabaigos.')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Column(
        children: [
          GestureDetector(
            onTap: _busy ? null : _buy,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _busy ? 0.75 : 1,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(color: _blue.withValues(alpha: 0.32),
                        blurRadius: 18, offset: const Offset(0, 8)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _busy
                      ? const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          ),
                        ]
                      : [
                          Text(
                              trial != null
                                  ? '${tr('Išbandyti')} ${_trialLabel(trial)}'
                                  : tr('Tęsti'),
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 19, color: Colors.white),
                        ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _busy ? null : _restore,
            child: Text(tr('Atkurti pirkimus'),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: _sub)),
          ),
          const SizedBox(height: 8),
          Text(
            terms,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9.5, height: 1.35, color: Color(0xFF8A94A8)),
          ),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: tr('Naudojimo sąlygos'),
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _sub),
                  recognizer: TapGestureRecognizer()..onTap = () => _openLegal(terms: true)),
              const TextSpan(
                  text: '  ·  ', style: TextStyle(fontSize: 10, color: Color(0xFF8A94A8))),
              TextSpan(
                  text: tr('Privatumo politika'),
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _sub),
                  recognizer: TapGestureRecognizer()..onTap = () => _openLegal(terms: false)),
            ]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The blue swell along the bottom edge.
