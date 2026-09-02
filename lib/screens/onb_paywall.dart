import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../app_prefs.dart';
import '../i18n.dart';
import '../logic/paywall_prices.dart';
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
/// Every price on this screen — the plan prices AND the figures derived from
/// them (per month, per year, savings, discount %) — comes from the live store
/// offering in the store's own currency, falling back to [_monthly]/[_yearly]
/// in EUR only until it loads. See [_PaywallPrices].
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
  const OnbPaywall(
      {super.key, required this.next, this.onClose, this.previewOnly = false});

  final Widget next;
  final VoidCallback? onClose;

  /// Dev-only: skips the auto-advance-if-already-premium check in initState
  /// below. Without this, the dev "preview paywall" shortcut on a simulator
  /// that ever held a real entitlement (this account's own dev grant
  /// included — the cached flag survives in local storage) instantly
  /// replaces this whole screen with `next` before it ever paints, which
  /// showed up as a plain black screen with no error. Never set outside
  /// that one dev entry point — a real paying user must still skip past
  /// this screen automatically.
  final bool previewOnly;

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

// Fallback prices, used ONLY until the store offering loads (or if it never
// does). Every derived figure below is computed from the LIVE store price when
// there is one — see _PaywallPrices.
const _monthly = 4.99;
const _yearly = 39.99;

class _OnbPaywallState extends State<OnbPaywall> with SingleTickerProviderStateMixin {
  bool _annual = true;
  bool _busy = false;
  // Guards against advancing twice: purchase()/restore() flip premium synchronously,
  // which fires the entitlement listener → _advance BEFORE the await returns, then
  // the explicit success handler calls _advance again → two pushReplacements (double
  // BankConnectScreen + a double bank-list fetch, and a possible route assertion).
  bool _advanced = false;

  // Loops the annual card's outer glow — per explicit request ("kaip nors
  // švytinčiai") — a slow breathe between dim and bright rather than a
  // fixed shadow, so it reads as worth noticing rather than a static outline.
  late final AnimationController _glowCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

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
    if (premium.value && !widget.previewOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
      return;
    }
    if (!widget.previewOnly) premium.addListener(_onPremiumChanged);
  }

  void _onPremiumChanged() {
    if (mounted && PurchaseService.instance.isPremiumListenable.value) {
      _advance();
    }
  }

  @override
  void dispose() {
    PurchaseService.instance.isPremiumListenable.removeListener(_onPremiumChanged);
    _glowCtl.dispose();
    super.dispose();
  }

  /// Rebuilt on demand: the RevenueCat offering can land AFTER this screen is
  /// first built, and a cached price object would keep showing the EUR fallback.
  PaywallPrices get _p {
    final svc = PurchaseService.instance;
    return PaywallPrices.from(
      monthly: svc.priceAmount(PlanId.monthly),
      yearly: svc.priceAmount(PlanId.yearly),
      currency: svc.priceCurrency(PlanId.yearly) ??
          svc.priceCurrency(PlanId.monthly),
      fallback: const PaywallPrices(
          monthly: _monthly, yearly: _yearly, currency: 'EUR'),
    );
  }

  String _fmt(double v) => _p.format(v, effectiveLocale().toString());

  PlanId get _plan => _annual ? PlanId.yearly : PlanId.monthly;

  /// Live store price for [id], falling back to the constant above until the
  /// RevenueCat offering has loaded (or if it never does).
  String _priceFor(PlanId id) =>
      PurchaseService.instance.priceString(id) ??
      _fmt(id == PlanId.yearly ? _p.yearly : _p.monthly);

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
    // Hard guard, not just the greyed-out button.
    //
    // `onTap: _busy ? null : _buy` only stops the SECOND frame: two taps inside
    // one frame — or a tap landing while `setState` is still in flight — both
    // reached here and opened two StoreKit purchase sheets for the same plan.
    if (_busy) return;
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
          // 2026-09-03: full-bleed background per explicit request — the
          // photo used to sit only behind the top portion, with the plan
          // cards on the plain page colour below it. Now it fills the
          // whole screen (BoxFit.cover; this asset's own aspect is close
          // enough to the device's that cover barely crops anything) and
          // every Flutter block — headline, cards, buy button, disclosures
          // — sits on top of it, same as OnbConnect/OnbInvest's own
          // full-bleed pages.
          const Positioned.fill(
            child: Image(
              image: AssetImage('assets/onboarding/paywall_hero.png'),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
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
                // 2026-09-02 v2: a fixed-fraction SizedBox here first guessed
                // too little photo, then (overcorrecting) too much, pushing
                // the plans into a scroll that didn't used to exist ("neturi
                // būti scrolinimo"). Tried an Expanded spacer sized to
                // "whatever the content below doesn't need" next — but that
                // makes this spacer and the content below it TWO flexible
                // siblings sharing the leftover space by their flex factor
                // (roughly 50/50), not "content gets what it needs, spacer
                // gets the rest" — so the content's own viewport ended up
                // squeezed to half the screen and its bottom (the Apple-
                // required restore/terms text) silently scrolled out of
                // reach, with nothing left to scroll to it. A fixed height
                // — same approach OnbConnect/OnbInvest already use for their
                // own full-bleed photos — plus a SINGLE Expanded around the
                // content (the only flex child now) is what actually gives
                // the content first claim on the remaining space, with
                // scrolling kept only as a fallback for a shorter device.
                // 406 and 320 both still left the bottom of the content
                // (disclosures, sometimes the monthly card) taller than the
                // space actually left after this gap — with scrolling now
                // off, that overflow doesn't scroll into view at all, it
                // just clips silently, which read as the annual plan card
                // being cut off / hidden under the photo. 240 leaves a
                // solid margin above the content's own worst-case height
                // instead of a guess tuned to exactly one device.
                const SizedBox(height: 240),
                Expanded(
                  child: SingleChildScrollView(
                    // No drag — per explicit request, this screen must never
                    // scroll at all, not even as a fallback. The fixed
                    // height above is sized so everything (cards, button,
                    // disclosures) already fits; a scrollable safety net
                    // just meant dragging could reveal a seam where the
                    // full-bleed photo behind it ends.
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Per explicit request: the gap above read as too
                        // empty without SOME headline, even once it shrank
                        // to a sane size — the render's own "V PREMIUM"
                        // wordmark sits far enough up/left that it doesn't
                        // double as a title for what follows. Now that the
                        // photo runs full-bleed behind this too, it gets
                        // the same drop shadow OnbConnect/OnbInvest give
                        // their own headlines over a photo.
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: '${tr('Vaultie')} '),
                            TextSpan(
                                text: 'Premium',
                                style: const TextStyle(color: _blueBright)),
                          ]),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.6,
                              shadows: [
                                Shadow(
                                    color: Color(0xB3000000),
                                    blurRadius: 14,
                                    offset: Offset(0, 3)),
                                Shadow(color: Color(0x66000000), blurRadius: 30),
                              ]),
                        ),
                        // Plans first: the price is the decision, and on a short
                        // phone it used to sit below three feature cards where
                        // it had to be scrolled to.
                        const SizedBox(height: 14),
                        _planCard(
                          annual: true,
                          title: tr('Metinis planas'),
                          price: _priceFor(PlanId.yearly),
                          period: tr('/ metus'),
                          trialDays: _trialFor(PlanId.yearly),
                          chip: '${_fmt(_p.yearlyPerMonth)} ${tr('/ mėn.')}',
                        ),
                        // The trial line follows whichever card is actually
                        // selected, not a fixed slot after both — pinning it after
                        // the monthly card unconditionally left it looking
                        // detached from the choice whenever the yearly plan was
                        // the one selected.
                        if (_annual) _trialLine(),
                        const SizedBox(height: 10),
                        _planCard(
                          annual: false,
                          title: tr('Mėnesinis planas'),
                          price: _priceFor(PlanId.monthly),
                          period: tr('/ mėn.'),
                          chip: '${_fmt(_p.yearOfMonthly)} ${tr('per metus')}',
                          trialDays: _trialFor(PlanId.monthly),
                        ),
                        if (!_annual) _trialLine(),
                        const SizedBox(height: 10),
                        // The buy button sits right after the plans, not below
                        // the feature icons — it is the decision that follows
                        // picking a plan, not something to scroll past first.
                        _bottom(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard({
    required bool annual,
    required String title,
    required String price,
    required String period,
    required String chip,
    int? trialDays,
  }) {
    final on = _annual == annual;
    // The annual card's glow now breathes with _glowCtl instead of sitting at
    // a fixed shadow — per explicit request ("kaip nors švytinčiai"). The
    // monthly card gets the opposite treatment when it isn't the one picked:
    // a slight dimming on top of its already-flatter fill, so the two read
    // as clearly unequal rather than two same-weight boxes with different
    // colours — the other half of "labiau išskirk metinį ir mėnesinį".
    return AnimatedBuilder(
      animation: _glowCtl,
      builder: (context, _) {
        final glow = _glowCtl.value;
        return GestureDetector(
          onTap: _busy ? null : () => setState(() => _annual = annual),
          child: Opacity(
            opacity: (!annual && !on) ? 0.8 : 1,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                // Both fills sit clearly ABOVE the page (#00082D). They used to be
                // within a few points of it, so the cards dissolved into the
                // background and there was nothing to choose between.
                //
                // 2026-09-02: the annual card additionally gets a gradient fill +
                // an outer glow (below) instead of the plain flat colour the
                // monthly card keeps — per explicit request to make it read as
                // the obviously-worth-it choice, without touching any of its
                // copy.
                gradient: annual
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: on
                            ? const [Color(0xFF1B3E93), Color(0xFF0A1F52)]
                            : const [Color(0xFF14275C), Color(0xFF0B1740)],
                      )
                    : null,
                color: annual ? null : (on ? const Color(0xFF122A63) : const Color(0xFF0B1740)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: on ? _blueBright : const Color(0xFF1E2F66),
                    width: on ? 1.8 : 1),
                boxShadow: annual
                    ? [
                        BoxShadow(
                            color: _blueBright.withValues(
                                alpha: (on ? 0.38 : 0.20) + glow * (on ? 0.32 : 0.14)),
                            blurRadius: 22 + glow * 18,
                            spreadRadius: 0.5 + glow * 1.5,
                            offset: const Offset(0, 8)),
                      ]
                    : null,
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
                          '${tr('Sutaupai')} ${_fmt(_p.saving)}',
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
                      // Always white. Tinting the SELECTED title blue made the
                      // plan you had just chosen the dimmer of the two.
                      Text(title,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _ink)),
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
                      // "Sutaupyk 33 %" used to sit here as well — the same
                      // saving was then stated THREE times in one card
                      // ("Sutaupai 19,89 €", "−33 %", "Sutaupyk 33 %"), each in
                      // green. Saying it once in money and once as a percentage
                      // is the argument; the third was just noise.
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
                        child: Text('−${_p.discount} %',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // The price is the single most important number here,
                        // and selecting a plan used to turn it #003DE1 on a
                        // dark blue card — blue on blue, the least legible it
                        // could be at the moment it mattered most. Selection is
                        // already carried by the radio, the border and the
                        // fill; the number just stays readable.
                        Text(price,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                                letterSpacing: -0.5)),
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
                        // The monthly chip was #EDF1FD — a near-white slab, the
                        // only light block anywhere on a near-black screen, and
                        // it pulled the eye to the plan we are NOT recommending.
                        // It carries a neutral fact (what a year costs monthly),
                        // so it is now neutral.
                        color: annual ? _greenSoft : const Color(0xFF16234E),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(chip,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: annual ? _green : const Color(0xFFB9C6E4))),
                    ),
                  ],
                ),
              ],
            ),
          ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// A plain "cancel anytime" reassurance under the plans — true regardless of
  /// trial eligibility, so it no longer branches on it. It used to also spell
  /// out "Išbandyk N d. nemokamai" in green when the store confirmed a trial,
  /// but the buy button right below says the exact same thing now that it
  /// moved up next to the plans, so that half became a repeat and was dropped.
  Widget _trialLine() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: Text(tr('Atšaukti gali bet kada.'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _sub)),
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
                          // The button names the plan it will buy, and changes
                          // the moment another plan is tapped.
                          //
                          // Without this the screen read as "there is a free
                          // trial button, and some cards above it": nothing
                          // connected the choice to the action, so a person
                          // could press it never having understood that a plan
                          // had to be picked — or which one they had just
                          // agreed to pay for. The second line is the same
                          // commitment Apple already requires us to state, put
                          // where the decision is made instead of in grey type
                          // underneath it.
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                    trial != null
                                        ? '${tr('Išbandyti')} ${_trialLabel(trial)}'
                                        : tr('Tęsti'),
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                                const SizedBox(height: 1),
                                Text(
                                    trial != null
                                        ? '$plan · ${tr('tada')} $price / $per'
                                        : '$plan · $price / $per',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xCCFFFFFF))),
                              ],
                            ),
                          ),
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
