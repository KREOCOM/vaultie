import 'package:flutter/material.dart';

/// Onboarding page 5 — the AI chat, mid-conversation.
///
/// Built from `_AiChatTab` in lib/screens/preview/dashboard_preview.dart:8021:
/// the header with its tinted tile, the four starter cards, the bubble shapes
/// (18 all round except a 5pt tail on the near side), the three static typing
/// dots, and the composer with its 46pt circular send button.
///
/// The question is one of the app's own starters. The reply is plain prose with
/// no Markdown, because functions/finance_chat.py:34 forbids it outright — a
/// mock with bold text or bullet points would be showing something the product
/// never produces.
///
/// Every figure quoted continues July: the categories from page 2, and the
/// saving suggested here is a fifth of the two smallest ones.
class OnbChat extends StatefulWidget {
  const OnbChat({super.key, required this.next});
  final Widget next;

  @override
  State<OnbChat> createState() => _OnbChatState();
}

const _bg = Color(0xFFEEF1F7);
const _card = Color(0xFFFFFFFF);
const _hair = Color(0xFFE3E9F2);
const _psoft = Color(0xFFE4EDFD);
const _ink = Color(0xFF14203A);
const _muted = Color(0xFF5C6A85);
const _purple = Color(0xFF2F6BFF);

/// Both questions are the app's own starters, from dashboard_preview.dart:8041.
const _q1 = 'Kur galėčiau sutaupyti?';
const _q2 = 'Kokia mano brangiausia prenumerata?';

const _starters = [
  'Kiek išleidau šį mėnesį?',
  'Kokia mano brangiausia prenumerata?',
  'Kur galėčiau sutaupyti?',
  'Į ką daugiausiai išleidžiu?',
];

// July, carried over from the other pages.
const _bustas = 742.50, _maistas = 389.20, _transportas = 214.80, _pramogos = 168.40;
const double _trimmable = _transportas + _pramogos;
final int _saving = (_trimmable / 5).round();          // a fifth → 77 €

String _eur(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

/// The five subscriptions behind page 1's card. Their sum is the 84,26 €/mėn
/// shown there, and the three chips on that card round from these exact values
/// (24,99 → 25 €, 12,99 → 13 €, 9,99 → 10 €). Summed here rather than restated,
/// so the two screens cannot drift apart.
const _subs = <(String, double)>[
  ('sporto klubą', 32.30),
  ('Telia', 24.99),
  ('Netflix', 12.99),
  ('Spotify', 9.99),
  ('iCloud+', 3.99),
];
final double _subsMonthly = _subs.fold(0.0, (a, b) => a + b.$2);   // 84,26
final double _subsYearly = _subsMonthly * 12;                      // 1 011,12

final String _reply2 =
    'Daugiausia moki už ${_subs[0].$1} — ${_eur(_subs[0].$2)} per mėnesį. '
    'Po jo eina ${_subs[1].$1} (${_eur(_subs[1].$2)}) ir ${_subs[2].$1} (${_eur(_subs[2].$2)}). '
    'Iš viso penkios prenumeratos sudaro ${_eur(_subsMonthly)} per mėnesį, '
    'arba ${_eur(_subsYearly)} per metus.';

final String _reply1 =
    'Liepą daugiausia nusinešė būstas ir sąskaitos — ${_eur(_bustas)}. '
    'Maistui išleidai ${_eur(_maistas)}, tai 62 € mažiau nei birželį. '
    'Realiausia sutaupyti ties transportu (${_eur(_transportas)}) ir pramogomis '
    '(${_eur(_pramogos)}) — sumažinus juos penktadaliu, per mėnesį liktų apie $_saving € daugiau.';

class _OnbChatState extends State<OnbChat> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 13))..repeat();
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    _float.dispose();
    super.dispose();
  }

  void _start(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => widget.next,
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxHeight / 844;

          return Stack(
            children: [
              const Positioned.fill(child: CustomPaint(painter: _ArcGround())),
              Positioned(
                top: 26 * s,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_enter, _loop, _float]),
                  builder: (context, _) {
                    final e = Curves.easeOutCubic.transform(_enter.value);
                    final drift = (_float.value - 0.5) * 10;
                    return Opacity(
                      opacity: e,
                      child: Transform.translate(
                        offset: Offset(0, ((1 - e) * 40 + drift) * s),
                        child: Center(child: _device(268 * s, 580 * s, _loop.value)),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 26 * s,
                child: AnimatedBuilder(
                  animation: _enter,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(((_enter.value - 0.35) / 0.65).clamp(0.0, 1.0));
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
                    );
                  },
                  child: _foot(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _device(double w, double h, double t) => Container(
        width: w,
        height: h,
        padding: EdgeInsets.all(w * 0.024),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.135),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF161619), Color(0xFF0B0B0D), Color(0xFF000000), Color(0xFF0E0E11), Color(0xFF1A1A1E)],
            stops: [0.0, 0.30, 0.55, 0.85, 1.0],
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFF060C1E).withValues(alpha: 0.42),
                blurRadius: w * 0.16, offset: Offset(0, w * 0.06)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * 0.116),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(width: 390, height: 844, child: _Chat(t: t)),
          ),
        ),
      );

  Widget _foot(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == 5 ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 5 ? Colors.white : Colors.white.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _copy(),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _start(context),
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF0A2260).withValues(alpha: 0.28),
                        blurRadius: 18, offset: const Offset(0, 8)),
                  ],
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Pradėti',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1440B4))),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 19, color: Color(0xFF1440B4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _copy() {
    const glow = [Shadow(color: Color(0x730A1E4B), blurRadius: 14, offset: Offset(0, 2))];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Agentas, kuris mato',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Colors.white, shadows: glow)),
        const Text('tavo skaičius',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Color(0xFFBFD6FF), shadows: glow)),
        const SizedBox(height: 10),
        Text(
          'Paklausk, kur nueina pinigai —\natsakys iš karto ir konkrečiai.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92), shadows: glow),
        ),
      ],
    );
  }
}

// ── the chat screen ──────────────────────────────────────────────────────────

class _Chat extends StatelessWidget {
  const _Chat({required this.t});
  final double t;

  // Two exchanges in one lap. The question being typed is the part that reads
  // as a person rather than a screenshot, so it gets the most time.
  static const _t1From = 0.03, _t1To = 0.16, _send1 = 0.17, _dots1To = 0.27, _in1 = 0.31;
  static const _t2From = 0.40, _t2To = 0.53, _send2 = 0.54, _dots2To = 0.64, _in2 = 0.68;

  static int _chars(double t, String s, double from, double to) => t < from
      ? 0
      : t < to
          ? (((t - from) / (to - from)) * s.length).floor()
          : s.length;

  @override
  Widget build(BuildContext context) {
    final asked1 = t >= _send1;
    final asked2 = t >= _send2;

    // whichever question is currently being written sits in the composer
    final draft = !asked1
        ? _q1.substring(0, _chars(t, _q1, _t1From, _t1To))
        : !asked2
            ? _q2.substring(0, _chars(t, _q2, _t2From, _t2To))
            : '';

    return Container(
      color: _bg,
      child: Column(
        children: [
          const SizedBox(height: 54),
          _header(),
          Expanded(
            child: asked1
                ? _thread(
                    thinking1: t < _dots1To,
                    replied1: t >= _dots1To,
                    fade1: ((t - _dots1To) / (_in1 - _dots1To)).clamp(0.0, 1.0),
                    asked2: asked2,
                    thinking2: asked2 && t < _dots2To,
                    replied2: t >= _dots2To,
                    fade2: ((t - _dots2To) / (_in2 - _dots2To)).clamp(0.0, 1.0),
                  )
                : _empty(),
          ),
          _composer(draft, typing: draft.isNotEmpty),
        ],
      ),
    );
  }

  /// Reversed so the newest message is pinned to the bottom and older ones
  /// scroll off the top — the way a real thread behaves once it outgrows the
  /// screen, rather than overflowing.
  Widget _thread({
    required bool thinking1,
    required bool replied1,
    required double fade1,
    required bool asked2,
    required bool thinking2,
    required bool replied2,
    required double fade2,
  }) {
    final items = <Widget>[
      _bubble(_q1, user: true),
      if (thinking1) _typing(),
      if (replied1) _fadeIn(_bubble(_reply1, user: false), fade1),
      if (asked2) _bubble(_q2, user: true),
      if (thinking2) _typing(),
      if (replied2) _fadeIn(_bubble(_reply2, user: false), fade2),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      physics: const NeverScrollableScrollPhysics(),
      reverse: true,
      children: items.reversed.toList(),
    );
  }

  Widget _fadeIn(Widget child, double f) => Opacity(
        opacity: f,
        child: Transform.translate(offset: Offset(0, (1 - f) * 8), child: child),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _psoft, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.auto_awesome_rounded, color: _purple, size: 22),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tavo finansų agentas',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
                Text('Klausk apie savo pinigus', style: TextStyle(fontSize: 13, color: _muted)),
              ],
            ),
          ],
        ),
      );

  Widget _empty() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Text('Pabandyk paklausti:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _muted)),
          const SizedBox(height: 12),
          for (final s in _starters)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _hair),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _psoft, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: _purple),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
                    ),
                    const Icon(Icons.arrow_outward_rounded, size: 16, color: _purple),
                  ],
                ),
              ),
            ),
        ],
      );

  /// 18pt corners with a 5pt tail on the side the bubble sits against.
  Widget _bubble(String text, {required bool user}) => Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 390 * 0.82),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: user ? _purple : _card,
            border: user ? null : Border.all(color: _hair),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(user ? 18 : 5),
              bottomRight: Radius.circular(user ? 5 : 18),
            ),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 15, height: 1.42, color: user ? Colors.white : _ink)),
        ),
      );

  /// Three still dots — the app does not animate them, so neither does this.
  Widget _typing() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _hair),
          ),
          child: SizedBox(
            width: 34,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _muted.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _composer(String text, {required bool typing}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
        decoration: const BoxDecoration(
          color: _card,
          border: Border(top: BorderSide(color: _hair)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(24)),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        text.isEmpty ? 'Klausk apie savo finansus…' : text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: text.isEmpty ? _muted : _ink),
                      ),
                    ),
                    // the caret only exists while something is being written
                    if (typing)
                      Container(
                        width: 1.5,
                        height: 18,
                        margin: const EdgeInsets.only(left: 2),
                        color: _purple,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: text.isEmpty ? _muted.withValues(alpha: 0.3) : _purple,
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
            ),
          ],
        ),
      );
}

class _ArcGround extends CustomPainter {
  const _ArcGround();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBFDFF));
    final edge = size.height * 0.46;
    final path = Path()
      ..moveTo(0, edge)
      ..quadraticBezierTo(size.width / 2, edge - size.height * 0.09, size.width, edge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFF3E74FF), Color(0xFF2F6BFF), Color(0xFF1E4FD8)],
          stops: [0, 0.42, 1],
        ).createShader(Rect.fromLTWH(0, edge, size.width, size.height - edge)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
