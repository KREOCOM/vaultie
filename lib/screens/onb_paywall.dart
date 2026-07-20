import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../services/purchase_service.dart';
import 'legal_screen.dart';

/// The paywall, copied from the reference.
///
/// This screen charges for real: "Tęsti" buys the selected plan through
/// [PurchaseService] and only advances once the entitlement is granted. The
/// close button (X) always skips — onboarding must never trap the user behind
/// a purchase, least of all when the store is unreachable.
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

const _ink = Color(0xFF0B1533);
const _sub = Color(0xFF4C5B7D);
const _paper = Color(0xFFFCFCFD);
const _blue = Color(0xFF003DE1);
const _blueBright = Color(0xFF0A4DFD);
const _green = Color(0xFF12A366);
const _greenSoft = Color(0xFFEEF7F3);
const _hair = Color(0xFFE6EAF2);

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

  PlanId get _plan => _annual ? PlanId.yearly : PlanId.monthly;

  /// Live store price for [id], falling back to the constant above until the
  /// RevenueCat offering has loaded (or if it never does).
  String _priceFor(PlanId id) =>
      PurchaseService.instance.priceString(id) ??
      _eur(id == PlanId.yearly ? _yearly : _monthly);

  void _advance() => Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, __, ___) => widget.next,
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ),
      );

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
      case PurchaseStatus.cancelled:
        break;
      case PurchaseStatus.notFound:
        // Offerings never loaded: offline, or the products aren't live in App
        // Store Connect yet. Say so rather than pretending it worked.
        _toast(tr('Planai kol kas nepasiekiami. Bandyk vėliau arba praleisk.'));
      case PurchaseStatus.error:
        _toast(result.message ?? tr('Pirkimas nepavyko. Bandyk dar kartą.'));
    }
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
          const Positioned.fill(child: CustomPaint(painter: _Wave())),
          SafeArea(
            child: Column(
              children: [
                // close
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 26, color: _sub),
                    // Always a skip, never a purchase — see the class doc.
                    onPressed: _busy ? null : (widget.onClose ?? _advance),
                  ),
                ),
                // Scrolls on purpose: this is the densest screen in the app and
                // a short phone must not clip the plans or the legal text.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(15)),
                          child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 12),
                        const Text('Vaultie Premium',
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w800,
                                color: _ink, letterSpacing: -0.8)),
                        const SizedBox(height: 8),
                        Text(
                          tr('Visos funkcijos vienoje vietoje.\nDaugiau įžvalgų, kontrolės ir sutaupytų pinigų.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13.5, height: 1.45, color: _sub),
                        ),
                        const SizedBox(height: 18),
                        _features(),
                        const SizedBox(height: 18),
                        _planCard(
                          annual: false,
                          title: tr('Mėnesinis planas'),
                          price: _priceFor(PlanId.monthly),
                          period: tr('/ mėn.'),
                          chip: '${_eur(_yearOfMonthly)} ${tr('per metus')}',
                        ),
                        const SizedBox(height: 10),
                        _planCard(
                          annual: true,
                          title: tr('Metinis planas'),
                          price: _priceFor(PlanId.yearly),
                          period: tr('/ metus'),
                          chip: '${_eur(_yearlyPerMonth)} ${tr('/ mėn.')}',
                        ),
                        const SizedBox(height: 12),
                        _savingsBox(),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFF0A2260).withValues(alpha: 0.07),
                            blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Icon(f.$1, size: 22, color: _blueBright),
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
  }) {
    final on = _annual == annual;
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _annual = annual),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? _blue : _hair, width: on ? 1.8 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (annual)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(7)),
                  child: Text(tr('POPULIARUS PASIRINKIMAS'),
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: 0.4)),
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
                    border: Border.all(color: on ? _blue : const Color(0xFFC9D2E2), width: 2),
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
                              color: on ? _blue : _ink)),
                      const SizedBox(height: 2),
                      Text(tr('Visos Premium funkcijos.'),
                          style: const TextStyle(fontSize: 12.5, color: _sub)),
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

  Widget _savingsBox() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: _greenSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.sell_rounded, size: 22, color: _green),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tr('Sutaupai')} ${_eur(_saving)}',
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800, color: _green)),
                  const SizedBox(height: 1),
                  Text(tr('Pasirinkus metinį planą, lyginant su mėnesiniu.'),
                      style: const TextStyle(fontSize: 11.5, height: 1.3, color: _sub)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Button plus the disclosures Apple requires on a subscription screen.
  Widget _bottom() {
    final plan = _annual ? tr('Metinis planas') : tr('Mėnesinis planas');
    final price = _priceFor(_plan);
    final per = _annual ? tr('metams') : tr('mėnesiui');

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
                          Text(tr('Tęsti'),
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
            '$plan — $price / $per. ${tr('Atsinaujina automatiškai, kol neatšauksi App Store nustatymuose likus ne mažiau kaip 24 val. iki laikotarpio pabaigos.')}',
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
class _Wave extends CustomPainter {
  const _Wave();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final path = Path()
      ..moveTo(0, h - 54)
      ..cubicTo(size.width * 0.28, h - 84, size.width * 0.62, h - 22, size.width, h - 62)
      ..lineTo(size.width, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF003FE7).withValues(alpha: 0.10));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
