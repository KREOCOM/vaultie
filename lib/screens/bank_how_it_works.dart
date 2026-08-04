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

/// What happens when you connect a bank, shown BEFORE the bank list.
///
/// This is the moment the flow used to skip. The person has just paid, taps
/// "Prijungti banką", and is thrown out of the app onto their bank's website —
/// unwarned that reads as an error or a scam, and it is the single place someone
/// is most likely to abandon. Three steps and one sentence about who sees the
/// password costs a tap and removes that.
class BankHowItWorks extends StatelessWidget {
  const BankHowItWorks({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cxBg,
      appBar: AppBar(
        backgroundColor: cxBg,
        elevation: 0,
        foregroundColor: cxInk,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Kaip prijungsime tavo banką'),
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.7,
                  color: cxInk,
                ),
              ),
              const SizedBox(height: 24),
              _Step(
                n: '1',
                title: tr('Pasirink savo banką'),
                body: tr('Iš 2 500+ Europos bankų sąrašo.'),
              ),
              _Step(
                n: '2',
                title: tr('Patvirtink savo banke'),
                body: tr('Nukreipsim į tavo banko programėlę ar svetainę. '
                    'Prisijungi ir patvirtini prieigą — taip pat, kaip '
                    'prisijungdamas prie savo banko. Vaultie tavo prisijungimo '
                    'duomenų nemato.'),
              ),
              _Step(
                n: '3',
                title: tr('Grįžk į Vaultie'),
                body: tr('Kai patvirtinsi, automatiškai grįši atgal, o tavo '
                    'operacijos susitvarkys pačios.'),
                last: true,
              ),
              const SizedBox(height: 26),
              const _ConnectionFlow(),
              const SizedBox(height: 26),
              // A blue link on deep navy disappeared into the background. This
              // is the answer to the question people actually have before
              // handing over bank access, so it gets a surface of its own.
              GestureDetector(
                onTap: () => showWhySafeSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cxCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2E56C8)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 19, color: Color(0xFF8FB6FF)),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          tr('Kodėl tai saugu'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cxInk,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 20, color: Color(0xFF8FB6FF)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr('Jungiamės per Enable Banking — licencijuotą ES atvirosios '
                    'bankininkystės tiekėją (PSD2). Prieiga tik skaitymo. '
                    'Atšaukti gali bet kada.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, height: 1.45, color: cxSubtle),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 54,
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
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(
      {required this.n,
      required this.title,
      required this.body,
      this.last = false});

  final String n;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: VaultieColors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(n,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: VaultieColors.primary)),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: VaultieColors.primary.withValues(alpha: 0.16),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 20, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cxInk)),
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.45, color: cxSubtle)),
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
                  style: TextStyle(
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
                style: TextStyle(fontSize: 11.5, height: 1.45, color: cxSubtle),
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
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle_rounded,
                  size: 17, color: VaultieColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cxInk)),
                  const SizedBox(height: 3),
                  Text(body,
                      style: TextStyle(
                          fontSize: 13, height: 1.45, color: cxSubtle)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Fills what used to be a bare `Spacer()` — a plain dead gap between the
/// three steps and the "Kodėl tai saugu" link. Two endpoints (the Vaultie
/// mark, a bank) with a dashed line each way between them: one line's arrow
/// travels left→right (step 2, going TO the bank), the other right→left
/// (step 3, coming back) — both animate continuously and simultaneously,
/// rather than in sequence, since access flows out and confirmation flows
/// back at once, not as two separate phases.
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
    return SizedBox(
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft glow behind the endpoints, tying this gap to the same brand
          // blue as the rest of the screen instead of leaving it flat cxBg.
          Container(
            width: 240,
            height: 96,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  _flowAccent.withValues(alpha: 0.16),
                  _flowAccent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Row(
            children: [
              _endpoint(const Icon(Icons.shield_rounded,
                  size: 24, color: Colors.white)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _flowLine(reverse: false),
                      const SizedBox(height: 16),
                      _flowLine(reverse: true),
                    ],
                  ),
                ),
              ),
              _endpoint(const Icon(Icons.account_balance_rounded,
                  size: 24, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _endpoint(Widget child) => Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cxCard,
          shape: BoxShape.circle,
          border: Border.all(color: _flowAccent.withValues(alpha: 0.4)),
        ),
        child: child,
      );

  Widget _flowLine({required bool reverse}) => LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: 16,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = reverse ? 1 - _c.value : _c.value;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: Size(constraints.maxWidth, 16),
                    painter: _DashedLinePainter(
                        color: cxSubtle.withValues(alpha: 0.35)),
                  ),
                  Align(
                    alignment: Alignment(2 * t - 1, 0),
                    child: Icon(
                      reverse
                          ? Icons.arrow_back_rounded
                          : Icons.arrow_forward_rounded,
                      size: 14,
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
