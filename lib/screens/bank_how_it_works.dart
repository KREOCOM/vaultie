import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../main.dart';

const _flowAccent = Color(0xFF8FB6FF);

/// The connect flow keeps the brand's deep navy in both themes: it is a moment
/// about trust, and the screens on either side of it (the bank's own page, the
/// onboarding that led here) are dark. Osvaldas is refining the exact shade.
const cxBg = Color(0xFF0A1533);
const cxCard = Color(0xFF14224A);
const cxInk = Color(0xFFFFFFFF);
const cxSubtle = Color(0xFFA9BCEC);
const cxLine = Color(0x332E56C8);

/// What happens when you connect a bank, shown BEFORE the bank list.
///
/// This is the moment the flow used to skip. The person has just paid, taps
/// "Prijungti banką", and is thrown out of the app onto their bank's website —
/// unwarned that reads as an error or a scam, and it is the single place someone
/// is most likely to abandon. Three steps and one sentence about who sees the
/// password costs a tap and removes that.
///
/// 2026-09-03: rebuilt per an explicit reference mockup — a glowing badge
/// above the title, each step in its own bordered card (icon circle + an
/// overlapping number, not a numbered rail connecting them), and the safety
/// explanation + connection diagram merged into one card instead of two
/// separate elements. Real Vaultie blue throughout, not the reference's own
/// generic blue.
class BankHowItWorks extends StatelessWidget {
  const BankHowItWorks({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    // Same reasoning as before this rewrite: iOS's reference height clears
    // the fold, Android's shorter/narrower common sizes (plus its default
    // text scaling reading a touch larger) don't — only the gaps shrink,
    // same content and order. A scroll is still there as a fallback for
    // whatever device this guess doesn't hold on, but nothing here should
    // need it in practice.
    final gap = Platform.isAndroid ? 15.0 : 18.0;
    // 2026-09-03: this used to be its own Scaffold+AppBar, but this widget
    // is only ever used as _Phase.intro's body INSIDE BankConnectScreen's
    // own Scaffold (which already has an AppBar titled "Prijungti banką"
    // and its own SafeArea around body) — never pushed as a standalone
    // route. A second, blank (titleless) AppBar was stacking directly under
    // the real one, silently eating ~50pt of height the layout wasn't
    // budgeted for, on a screen where every 10pt of headroom mattered ("kai
    // scrolini slepiasi tekstas" — the deficit only showed up once the
    // scroll from a too-tall bottom actually engaged). Just the content now;
    // the outer Scaffold owns the app bar and the SafeArea on every side.
    return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
          child: Column(
            children: [
              // No badge above the title anymore — per explicit request. The
              // Vaultie mark swap still clipped oddly at small sizes and read
              // as one logo too many on a screen that already opens from a
              // Vaultie-branded app bar.
              Text(
                tr('Kaip prijungsime tavo banką'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                  color: cxInk,
                ),
              ),
              SizedBox(height: gap * 0.4),
              Text(
                tr('Vos 3 žingsniai iki prijungto banko.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.3, color: cxSubtle),
              ),
              SizedBox(height: gap * 1.7),
              _Step(
                icon: Icons.account_balance_rounded,
                n: '1',
                title: tr('Pasirink savo banką'),
                body: tr('Iš daugiau nei 2 700+ Europos bankų.'),
              ),
              SizedBox(height: gap),
              _Step(
                icon: Icons.lock_outline_rounded,
                n: '2',
                title: tr('Patvirtink prieigą banke'),
                body: tr('Nukreipsim į tavo banko programėlę ar svetainę. '
                    'Prisijungi ir patvirtini prieigą taip, kaip įprastai.'),
              ),
              SizedBox(height: gap),
              _Step(
                icon: Icons.check_circle_outline_rounded,
                n: '3',
                title: tr('Grįžk į Vaultie'),
                body: tr('Kai patvirtinsi, grįši į Vaultie — tavo operacijos '
                    'susitvarkys automatiškai.'),
              ),
              SizedBox(height: gap * 1.7),
              Container(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
                decoration: BoxDecoration(
                  color: cxCard,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: cxLine),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _flowAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined,
                              size: 14, color: _flowAccent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Tavo banko duomenys saugūs'),
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: cxInk)),
                              const SizedBox(height: 3),
                              Text(
                                tr('Prisijungimas vyksta tavo banko aplinkoje. '
                                    'Vaultie nemato prisijungimo duomenų.'),
                                style: const TextStyle(
                                    fontSize: 11.5, height: 1.3, color: cxSubtle),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const _ConnectionFlow(),
                  ],
                ),
              ),
              SizedBox(height: gap * 1.2),
              // A blue link on deep navy disappeared into the background. This
              // is the answer to the question people actually have before
              // handing over bank access, so it gets a surface of its own.
              GestureDetector(
                onTap: () => showWhySafeSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cxCard,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFF2E56C8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 17, color: _flowAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tr('Kodėl tai saugu'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cxInk,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 19, color: _flowAccent),
                    ],
                  ),
                ),
              ),
              SizedBox(height: gap * 1.2),
              Text(
                tr('Jungiamės per Enable Banking — licencijuotą ES atvirosios '
                    'bankininkystės tiekėją (PSD2). Prieiga tik skaitymo. '
                    'Atšaukti gali bet kada.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10.5, height: 1.35, color: cxSubtle),
              ),
              SizedBox(height: gap * 1.2),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VaultieColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(tr('Tęsti'),
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.n,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cxCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cxLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _flowAccent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: _flowAccent),
                ),
                Positioned(
                  top: -5,
                  left: -5,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [
                        VaultieColors.brightBlue,
                        VaultieColors.primary,
                      ]),
                      border: Border.all(color: cxCard, width: 2.5),
                    ),
                    child: Text(n,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cxInk)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.35, color: cxSubtle)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full trust argument, reachable from the step screen and from Settings.
///
/// Every claim here is one the app can actually keep. Two that an earlier draft
/// made and the code does not support were dropped rather than softened:
/// transactions are NOT encrypted at rest (Hive opens without a cipher), and
/// "never shared with third parties" is untrue while the AI features post a
/// summary to a provider. Saying either would be a false promise in a finance
/// app — the kind a user only discovers at the worst possible moment.
Future<void> showWhySafeSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cxCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: cxSubtle, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Kodėl tai saugu'),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: cxInk)),
              const SizedBox(height: 16),
              _Point(
                title: tr('Licencijuotas tarpininkas'),
                body: tr('Jungiamės per Enable Banking — ES reguliuojamą '
                    'atvirosios bankininkystės tiekėją, veikiantį pagal PSD2 '
                    'direktyvą.'),
              ),
              _Point(
                title: tr('Niekada nematome tavo slaptažodžio'),
                body: tr('Prisijungi tik savo banke. Vaultie gauna leidimą '
                    'skaityti operacijas — ne tavo prisijungimo duomenis.'),
              ),
              _Point(
                title: tr('Tik skaitymas'),
                body: tr('Vaultie negali atlikti mokėjimų, pervesti ar keisti '
                    'nieko tavo sąskaitoje.'),
              ),
              _Point(
                title: tr('Duomenys lieka tavo telefone'),
                body: tr('Operacijos saugomos tavo telefone, o ne mūsų '
                    'serveriuose, ir niekada neparduodamos.'),
              ),
              _Point(
                title: tr('AI — tik tavo sutikimu'),
                body: tr('Jei įjungi AI funkcijas, mūsų tiekėjui siunčiame tik '
                    'apibendrintus skaičius: likučius, išlaidas pagal '
                    'kategoriją ir pasikartojančių mokėjimų pavadinimus. Ne '
                    'atskirus sandorius, ne IBAN‑us.'),
              ),
              _Point(
                title: tr('Tu valdai prieigą'),
                body: tr('Bet kada gali ją atšaukti — Vaultie nustatymuose arba '
                    'savo banke.'),
                last: true,
              ),
              const SizedBox(height: 6),
              Text(
                tr('Sutikimas galioja ribotą laiką ir yra atnaujinamas pagal '
                    'PSD2. Atšaukti gali bet kada.'),
                style: const TextStyle(fontSize: 11.5, height: 1.45, color: cxSubtle),
              ),
            ],
          ),
        ),
      ),
    );

class _Point extends StatelessWidget {
  const _Point({required this.title, required this.body, this.last = false});

  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: last ? 10 : 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle_rounded,
                  size: 17, color: Color(0xFF2FA34E)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cxInk)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: const TextStyle(
                          fontSize: 13, height: 1.45, color: cxSubtle)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// The connection diagram, now living inside the safety card instead of a
/// bare gap of its own. Two endpoints (the Vaultie mark, a bank) with a
/// dashed line each way between them: one line's arrow travels left→right
/// (step 2, going TO the bank), the other right→left (step 3, coming back)
/// — both animate continuously and simultaneously, rather than in sequence,
/// since access flows out and confirmation flows back at once, not as two
/// separate phases.
class _ConnectionFlow extends StatefulWidget {
  const _ConnectionFlow();

  @override
  State<_ConnectionFlow> createState() => _ConnectionFlowState();
}

class _ConnectionFlowState extends State<_ConnectionFlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const height = 46.0;
    const lineGap = 7.0;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            _endpoint(const Icon(Icons.shield_rounded, size: 15, color: Colors.white)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _flowLine(reverse: false),
                    const SizedBox(height: lineGap),
                    _flowLine(reverse: true),
                  ],
                ),
              ),
            ),
            _endpoint(const Icon(Icons.account_balance_rounded,
                size: 15, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _endpoint(Widget child) => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cxBg,
          shape: BoxShape.circle,
          border: Border.all(color: _flowAccent.withValues(alpha: 0.4)),
        ),
        child: child,
      );

  Widget _flowLine({required bool reverse}) => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: 14,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = reverse ? 1 - _c.value : _c.value;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: Size(constraints.maxWidth, 14),
                    painter: _DashedLinePainter(
                        color: cxSubtle.withValues(alpha: 0.35)),
                  ),
                  Align(
                    alignment: Alignment(2 * t - 1, 0),
                    child: Icon(
                      reverse
                          ? Icons.arrow_back_rounded
                          : Icons.arrow_forward_rounded,
                      size: 13,
                      color: _flowAccent,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6;
    const dash = 4.0, gap = 4.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(
          Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
