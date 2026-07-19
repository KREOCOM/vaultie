import 'package:flutter/material.dart';

/// Onboarding page 4 — locking the app and choosing how it looks.
///
/// Built from the real screens: the Privatumas / Nustatymai groups in
/// `_SettingsScreen` (dashboard_preview.dart:7179), the shared PIN pad in
/// lock_screen.dart:146, and the "Tema" sheet at :7411. Strings, row metrics
/// and the keypad's 6 % white keys are the app's own.
///
/// The lap shows three things in the order a new user would do them: switch the
/// PIN on and set it, turn on Face ID, then flip the theme — and the mock's own
/// screen goes dark with it, which is the point of ending on that step.
class OnbSecurity extends StatefulWidget {
  const OnbSecurity({super.key, required this.next});
  final Widget next;

  @override
  State<OnbSecurity> createState() => _OnbSecurityState();
}

/// Light and dark tokens, so the mock can switch mid-lap.
class _P {
  const _P(this.bg, this.card, this.ink, this.muted, this.faint, this.hair);
  final Color bg, card, ink, muted, faint, hair;

  static const light = _P(Color(0xFFEEF1F7), Color(0xFFFFFFFF), Color(0xFF14203A),
      Color(0xFF5C6A85), Color(0xFF7C879E), Color(0xFFE3E9F2));
  static const dark = _P(Color(0xFF0A0910), Color(0xFF262436), Color(0xFFEDEAF6),
      Color(0xFFBDB7CE), Color(0xFF948DAC), Color(0xFF3D3951));
}

const _accentL = Color(0xFF2F6BFF);
const _accentD = Color(0xFF4C86FF);

// ── the settings layout, named once so the finger cannot drift ───────────────
const _statusH = 54.0, _appBarH = 56.0, _labelH = 38.0, _rowH = 62.0;
const _group1Top = _statusH + _appBarH + _labelH;          // 148
const _pinCentre = _group1Top + _rowH / 2;                 // 179
const _faceCentre = _group1Top + _rowH + _rowH / 2;        // 241
const _group2Top = _group1Top + _rowH * 2 + _labelH;       // 310
const _themeCentre = _group2Top + _rowH * 2 + _rowH / 2;   // 465

class _OnbSecurityState extends State<OnbSecurity> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..forward();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
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
            child: SizedBox(width: 390, height: 844, child: _Settings(t: t)),
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
                    width: i == 4 ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == 4 ? Colors.white : Colors.white.withValues(alpha: 0.38),
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
                    Text('Toliau',
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
        const Text('Užrakink ir',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Colors.white, shadows: glow)),
        const Text('pritaikyk sau',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15,
                letterSpacing: -0.9, color: Color(0xFFBFD6FF), shadows: glow)),
        const SizedBox(height: 10),
        Text(
          'PIN, Face ID ir tamsi tema —\nviskas per kelias sekundes.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92), shadows: glow),
        ),
      ],
    );
  }
}

// ── the settings screen inside the phone ─────────────────────────────────────

class _Settings extends StatelessWidget {
  const _Settings({required this.t});
  final double t;

  // the lap, in order: PIN on → set the code → Face ID on → theme → dark
  static const _pinOn = 0.12;
  static const _padIn = 0.14, _padOut = 0.34;
  static const _digitsFrom = 0.17, _digitsTo = 0.30;
  static const _faceOn = 0.42;
  static const _sheetIn = 0.52, _darkAt = 0.64, _sheetOut = 0.70;

  static double _ramp(double x, double a, double b, [Curve c = Curves.easeInOutCubic]) =>
      c.transform(((x - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final dark = t >= _darkAt;
    final p = dark ? _P.dark : _P.light;
    final accent = dark ? _accentD : _accentL;

    final pinOn = t >= _pinOn;
    final faceOn = t >= _faceOn;

    // the pad covers the screen while the code is being chosen
    final pad = t < _padIn
        ? 0.0
        : t < 0.18
            ? _ramp(t, _padIn, 0.18)
            : t < _padOut
                ? 1.0
                : 1 - _ramp(t, _padOut, 0.38);

    final digits = t < _digitsFrom
        ? 0
        : t < _digitsTo
            ? (((t - _digitsFrom) / (_digitsTo - _digitsFrom)) * 4).floor().clamp(0, 4)
            : 4;

    final sheet = t < _sheetIn
        ? 0.0
        : t < 0.58
            ? _ramp(t, _sheetIn, 0.58)
            : t < _sheetOut
                ? 1.0
                : 1 - _ramp(t, _sheetOut, 0.76);

    return Container(
      color: p.bg,
      child: Stack(
        children: [
          _list(p, accent, pinOn: pinOn, faceOn: faceOn, dark: dark),
          if (sheet > 0) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: const Color(0xFF091022).withValues(alpha: 0.42 * sheet)),
              ),
            ),
            Positioned(
              left: 0, right: 0,
              bottom: -(1 - sheet) * 250,
              height: 250,
              child: _themeSheet(p, accent, dark: dark),
            ),
          ],
          if (pad > 0)
            Positioned(
              left: 0, right: 0, top: 0,
              height: 844,
              child: Opacity(
                opacity: pad,
                child: Transform.translate(
                  offset: Offset(0, (1 - pad) * 60),
                  child: _pinPad(digits),
                ),
              ),
            ),
          _finger(pad: pad, sheet: sheet),
        ],
      ),
    );
  }

  Widget _list(_P p, Color accent, {required bool pinOn, required bool faceOn, required bool dark}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: _statusH),
          SizedBox(
            height: _appBarH,
            child: Row(
              children: [
                Icon(Icons.chevron_left_rounded, size: 30, color: p.ink),
                Expanded(
                  child: Center(
                    child: Text('Nustatymai',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.ink)),
                  ),
                ),
                const SizedBox(width: 30),
              ],
            ),
          ),
          _label('Privatumas', p),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _toggleRow(p, accent, Icons.lock_outline_rounded, 'PIN kodas',
                    'Atrakink Vaultie su PIN', pinOn, true),
                _toggleRow(p, accent, Icons.face_retouching_natural_rounded, 'Face ID atrakinimas',
                    pinOn ? 'Atrakink Vaultie veidu' : 'Įjunk PIN, kad naudotum Face ID',
                    faceOn, pinOn),
              ],
            ),
          ),
          _label('Nustatymai', p),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _valueRow(p, accent, '€', 'Numatytoji valiuta', 'Euras'),
                _valueRow(p, accent, 'LT', 'Kalba', 'Lietuvių'),
                _valueRow(p, accent, null, 'Tema', dark ? 'Tamsi' : 'Šviesi',
                    icon: Icons.brightness_6_rounded),
                _toggleRow(p, accent, Icons.notifications_none_rounded, 'Pranešimai',
                    'Priminimai apie mokėjimus', true, true),
              ],
            ),
          ),
        ],
      );

  Widget _label(String s, _P p) => SizedBox(
        height: _labelH,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(s,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.muted)),
          ),
        ),
      );

  Widget _toggleRow(_P p, Color accent, IconData ic, String title, String sub, bool on, bool enabled) =>
      SizedBox(
        height: _rowH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(width: 30, child: Icon(ic, size: 23, color: enabled ? accent : p.faint)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                            color: enabled ? p.ink : p.faint)),
                    Text(sub, style: TextStyle(fontSize: 13, color: p.muted)),
                  ],
                ),
              ),
              // a plain painted switch: the real Switch animates on its own clock
              // and would drift out of step with the lap
              Container(
                width: 51,
                height: 31,
                padding: const EdgeInsets.all(3),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: on ? accent : p.faint.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _valueRow(_P p, Color accent, String? badge, String title, String value, {IconData? icon}) =>
      SizedBox(
        height: _rowH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: icon != null
                    ? Icon(icon, size: 23, color: accent)
                    : Text(badge!,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink)),
                    Text(value, style: TextStyle(fontSize: 13, color: p.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.faint),
            ],
          ),
        ),
      );

  /// The app's own pad: 6 % white keys, radius 18, four 15pt dots.
  Widget _pinPad(int filled) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0910), Color(0xFF1A1726)],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 96),
            Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _accentD.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded, color: _accentD, size: 26),
            ),
            const SizedBox(height: 20),
            const Text('Naujas PIN kodas',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFFEDEAF6))),
            const SizedBox(height: 8),
            const Text('Sugalvok 4 skaitmenų kodą',
                style: TextStyle(fontSize: 14.5, color: Color(0xFF948DAC))),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 15,
                    height: 15,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < filled ? _accentD : Colors.transparent,
                      border: Border.all(
                          color: i < filled ? _accentD : const Color(0xFF948DAC), width: 1.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 54),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                    ['face', '0', 'back'],
                  ])
                    Row(children: [for (final k in row) _key(k)]),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _key(String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AspectRatio(
            aspectRatio: 1.6,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: label == 'face'
                  ? const Icon(Icons.face_retouching_natural_rounded, color: _accentD, size: 30)
                  : label == 'back'
                      ? const Icon(Icons.backspace_outlined, color: Color(0xFFEDEAF6), size: 24)
                      : Text(label,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFFEDEAF6))),
            ),
          ),
        ),
      );

  Widget _themeSheet(_P p, Color accent, {required bool dark}) => Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: p.faint, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              child: Text('Tema',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: p.ink)),
            ),
            for (final o in const [
              ('Šviesi', Icons.light_mode_rounded),
              ('Tamsi', Icons.dark_mode_rounded),
              ('Sistemos numatytoji', Icons.brightness_auto_rounded),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                child: Row(
                  children: [
                    Icon(o.$2, size: 23, color: accent),
                    const SizedBox(width: 14),
                    Text(o.$1, style: TextStyle(fontSize: 16, color: p.ink)),
                    const Spacer(),
                    if ((dark && o.$1 == 'Tamsi') || (!dark && o.$1 == 'Šviesi'))
                      Icon(Icons.check_rounded, size: 20, color: accent),
                  ],
                ),
              ),
          ],
        ),
      );

  /// Reaches the PIN switch, then Face ID, then Tema, then "Tamsi" in the sheet.
  Widget _finger({required double pad, required double sheet}) {
    // hidden while the pad covers everything
    if (pad > 0.3) return const SizedBox.shrink();

    late final double x, y;
    double o = 0;
    var press = 1.0;

    if (t < 0.16) {
      x = 330; y = _pinCentre;
      o = t < 0.04 ? t / 0.04 : t < 0.13 ? 1.0 : 1 - (t - 0.13) / 0.03;
      if (t > 0.115 && t < 0.135) press = 0.82;
    } else if (t < 0.48) {
      x = 330; y = _faceCentre;
      o = t < 0.38 ? 0.0 : t < 0.40 ? (t - 0.38) / 0.02 : t < 0.45 ? 1.0 : 1 - (t - 0.45) / 0.03;
      if (t > 0.415 && t < 0.435) press = 0.82;
    } else if (t < 0.60) {
      x = 200; y = _themeCentre;
      o = t < 0.485 ? 0.0 : t < 0.50 ? (t - 0.485) / 0.015 : t < 0.55 ? 1.0 : 1 - (t - 0.55) / 0.03;
      if (t > 0.505 && t < 0.525) press = 0.82;
    } else {
      // "Tamsi" is the second row of the sheet, which stands 250pt tall
      x = 120; y = 844 - 250 + 96;
      o = t < 0.60 ? 0.0 : t < 0.62 ? (t - 0.60) / 0.02 : t < 0.66 ? 1.0 : 1 - (t - 0.66) / 0.03;
      if (t > 0.635 && t < 0.655) press = 0.82;
    }
    o = o.clamp(0.0, 1.0);
    if (o <= 0) return const SizedBox.shrink();

    return Positioned(
      left: x - 15,
      top: y - 15,
      child: Opacity(
        opacity: o,
        child: Transform.scale(
          scale: press,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
              gradient: const RadialGradient(
                center: Alignment(-0.32, -0.4),
                colors: [Color(0xF0FFFFFF), Color(0x52FFFFFF), Color(0x00FFFFFF)],
                stops: [0, 0.46, 0.7],
              ),
              boxShadow: [
                BoxShadow(color: const Color(0xFF0A1432).withValues(alpha: 0.34),
                    blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
