// STANDALONE DEMO — 2026-08-13. Same pattern as subs_sort_demo.dart, applied
// to Sąskaitos (bills): a household's recurring, non-subscription payments
// (utilities, loan, insurance) kept as a genuinely separate screen/flow from
// Prenumeratos, per the plan agreed for this redesign.
//
// Pure UI, demo data, no backend wiring. Run standalone with:
//   flutter run -t lib/main_bills_demo.dart
//
// Delete this file + lib/main_bills_demo.dart to remove the experiment.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/design_system.dart' show CategoryIcon;

const _ink = Color(0xFF0B1533);
const _subtle = Color(0xFF5B6684);
const _faint = Color(0xFF93A0C2);
const _line = Color(0xFFE6EAF2);
const _bg = Color(0xFFF6F7FB);
const _card = Color(0xFFFFFFFF);
const _blue = Color(0xFF003DE1);
const _blueDeep = Color(0xFF0B2E9B);
const _blueSoft = Color(0xFFEAF0FF);
const _good = Color(0xFF1FA971);
const _bad = Color(0xFFD9534F);
const _amber = Color(0xFF9C6B0A);
const _amberSoft = Color(0xFFFBF1DE);

class _Candidate {
  _Candidate({
    required this.merchant,
    required this.amount,
    required this.occurrences,
    required this.cadence,
    this.ambiguous = false,
    this.hint,
    this.confidence = 1.0,
  });
  final String merchant;
  final double amount;
  final int occurrences;
  final String cadence;
  final bool ambiguous;
  final String? hint;
  final double confidence; // 0..1, drives sort order
  bool resolved = false;
  String? customName;
}

// Demo data: real household bills (utilities, loan, insurance) with stable
// amounts and cadence, mixed with noisy one-off/irregular retail spend that
// LOOKS frequent but isn't a bill — same "don't dump everything on the user"
// problem as subscriptions, different merchants.
List<_Candidate> _demoCandidates() => [
      _Candidate(merchant: 'SEB', amount: 420.00, occurrences: 5, cadence: 'kas mėnesį', confidence: 0.97),
      _Candidate(merchant: 'Ignitis', amount: 45.20, occurrences: 6, cadence: 'kas mėnesį', confidence: 0.95),
      _Candidate(merchant: 'Telia', amount: 24.99, occurrences: 6, cadence: 'kas mėnesį', confidence: 0.94),
      _Candidate(merchant: 'Vilniaus vandenys', amount: 18.40, occurrences: 4, cadence: 'kas mėnesį', confidence: 0.71),
      _Candidate(merchant: 'Lietuvos draudimas', amount: 12.50, occurrences: 3, cadence: 'kas mėnesį', confidence: 0.68),
      _Candidate(merchant: 'Depo', amount: 35.60, occurrences: 6, cadence: 'nereguliariai', confidence: 0.15),
      _Candidate(merchant: 'Apranga', amount: 24.90, occurrences: 3, cadence: 'nereguliariai', confidence: 0.10),
    ]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

/// Shared rename prompt — scoped to this ONE candidate (already separated by
/// price band), never to every transaction sharing the raw merchant string.
Future<void> _renameCandidate(
    BuildContext context, _Candidate c, VoidCallback onChanged) async {
  final ctl = TextEditingController(text: c.customName ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kaip pavadinti?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '„${c.merchant}" (${c.amount.toStringAsFixed(2)} €) — įvesk tikrąjį pavadinimą. '
              'Pervadinimas paveiks tik šitos kainos mokėjimus, kitos „${c.merchant}" sąskaitos nepasikeis.',
              style: const TextStyle(fontSize: 13, color: _subtle, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'pvz. Būsto paskola'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Atšaukti')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text('Patvirtinti'),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) {
    c.customName = name;
    onChanged();
  }
}

class BillsDemoScreen extends StatefulWidget {
  const BillsDemoScreen({super.key});
  @override
  State<BillsDemoScreen> createState() => _BillsDemoScreenState();
}

class _BillsDemoScreenState extends State<BillsDemoScreen>
    with SingleTickerProviderStateMixin {
  final List<_Candidate> _confirmed = [];
  late final List<_Candidate> _pool = _demoCandidates();
  late final AnimationController _waveCtl =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();

  int get _pendingCount => _pool.where((c) => !c.resolved).length;
  double get _monthlyTotal => _confirmed.fold(0.0, (s, c) => s + c.amount);
  double get _yearlyTotal => _monthlyTotal * 12;

  @override
  void dispose() {
    _waveCtl.dispose();
    super.dispose();
  }

  Future<void> _openSort() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BillsSortScreen(
        pool: _pool,
        onConfirm: (c) => setState(() => _confirmed.add(c)),
      ),
    ));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text('Sąskaitos',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          if (_confirmed.isEmpty)
            _findHero()
          else ...[
            _totalCard(),
            const SizedBox(height: 14),
            for (final c in _confirmed) ...[
              _confirmedTile(c),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            _addMoreRow(),
          ],
        ],
      ),
    );
  }

  Widget _findHero() => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_blueDeep, _blue],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: _blue.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _waveCtl,
                builder: (_, __) =>
                    CustomPaint(painter: _WavePainter(_waveCtl.value)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: const Icon(Icons.receipt_long_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 18),
                  const Text('Rask savo sąskaitas',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                      'Vaultie rado pasikartojančių mokėjimų tavo banko istorijoje. '
                      'Padėk mums atpažinti, kurios iš jų yra tavo sąskaitos.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.94),
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openSort,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _blueDeep,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('Peržiūrėti mokėjimus',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                  if (_pendingCount > 0) ...[
                    const SizedBox(height: 12),
                    Text('$_pendingCount galimi mokėjimai',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _totalCard() => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_blueDeep, _blue],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _blue.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        color: Colors.white, size: 15),
                    const SizedBox(width: 8),
                    Text(
                        '${_confirmed.length} ${_confirmed.length == 1 ? 'aktyvi sąskaita' : 'aktyvios sąskaitos'}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: _statText('Per mėnesį', _monthlyTotal)),
                Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withValues(alpha: 0.22)),
                const SizedBox(width: 18),
                Expanded(child: _statText('Per metus', _yearlyTotal)),
              ],
            ),
          ],
        ),
      );

  Widget _statText(String label, double value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('${value.toStringAsFixed(2)} €',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
        ],
      );

  Widget _addMoreRow() => InkWell(
        onTap: _openSort,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded, color: _blue, size: 20),
              const SizedBox(width: 10),
              const Text('Rasti naują sąskaitą',
                  style: TextStyle(
                      color: _blue, fontWeight: FontWeight.w700, fontSize: 14.5)),
              if (_pendingCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: _blueSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text('$_pendingCount',
                      style: const TextStyle(
                          color: _blue, fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
        ),
      );

  void _removeConfirmed(_Candidate c) {
    setState(() => _confirmed.remove(c));
  }

  Widget _confirmedTile(_Candidate c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _line),
        ),
        child: Row(children: [
          CategoryIcon(
              icon: Icons.receipt_long_rounded,
              color: _blue,
              size: 40,
              merchant: c.customName ?? c.merchant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.customName ?? c.merchant,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                Text(c.cadence, style: const TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${c.amount.toStringAsFixed(2)} €',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () =>
                        _renameCandidate(context, c, () => setState(() {})),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined, size: 16, color: _blue),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _removeConfirmed(c),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 16, color: _bad),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ]),
      );
}

/// Two slow, translucent sine bands drifting across the hero's top edge —
/// plain Path fills, no ImageFilter/blur, so it avoids the block-shaped
/// clipping artifact that killed the earlier glow experiments on-device.
class _WavePainter extends CustomPainter {
  _WavePainter(this.t);
  final double t; // 0..1, looping

  void _band(Canvas canvas, Size size, double phase, double baseY, double amp,
      double wavelengths, Color color) {
    final path = Path()..moveTo(0, 0);
    path.lineTo(0, baseY);
    for (double x = 0; x <= size.width; x += 6) {
      final y = baseY +
          amp * math.sin((x / size.width * wavelengths * 2 * math.pi) + phase);
      path.lineTo(x, y);
    }
    path.lineTo(size.width, 0);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t * 2 * math.pi;
    _band(canvas, size, phase, size.height * 0.16, 16, 1.4,
        Colors.white.withValues(alpha: 0.09));
    _band(canvas, size, -phase * 1.3 + math.pi / 3, size.height * 0.11, 12, 1.8,
        Colors.white.withValues(alpha: 0.07));
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}

class BillsSortScreen extends StatefulWidget {
  const BillsSortScreen({super.key, required this.pool, required this.onConfirm});
  final List<_Candidate> pool;
  final void Function(_Candidate) onConfirm;

  @override
  State<BillsSortScreen> createState() => _BillsSortScreenState();
}

class _BillsSortScreenState extends State<BillsSortScreen> {
  String _query = '';
  bool _showAll = false;

  static const _lowConfidenceCutoff = 0.5;

  List<_Candidate> get _visible {
    var list = widget.pool.where((c) => !c.resolved);
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((c) =>
          c.merchant.toLowerCase().contains(q) ||
          (c.customName?.toLowerCase().contains(q) ?? false));
    } else if (!_showAll) {
      list = list.where((c) => c.confidence >= _lowConfidenceCutoff);
    }
    return list.toList();
  }

  int get _hiddenLowConfidenceCount => widget.pool
      .where((c) => !c.resolved && c.confidence < _lowConfidenceCutoff)
      .length;

  Future<void> _confirm(_Candidate c) async {
    if (c.ambiguous && c.customName == null) {
      await _renameCandidate(context, c, () {});
      if (c.customName == null) return; // user cancelled the prompt
    }
    setState(() => c.resolved = true);
    widget.onConfirm(c);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('„${c.customName ?? c.merchant}" pridėta prie sąskaitų'),
            duration: const Duration(seconds: 2)));
    }
  }

  void _dismiss(_Candidate c) {
    setState(() => c.resolved = true);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _ink,
        title: const Text('Peržiūrėk mokėjimus',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Ieškoti pagal pavadinimą…',
                prefixIcon: const Icon(Icons.search_rounded, color: _faint),
                filled: true,
                fillColor: _card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _line)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _line)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              children: [
                for (final c in visible) ...[
                  _row(c),
                  const SizedBox(height: 10),
                ],
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('Nieko nerasta.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _subtle)),
                  ),
                if (!_showAll && _query.isEmpty && _hiddenLowConfidenceCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      onPressed: () => setState(() => _showAll = true),
                      child: Text(
                          'Rodyti visus pardavėjus ($_hiddenLowConfidenceCount daugiau)'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(_Candidate c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryIcon(
              icon: Icons.receipt_long_rounded,
              color: _blue,
              size: 40,
              merchant: c.customName ?? c.merchant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(c.customName ?? c.merchant,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                  ),
                  if (c.ambiguous) ...[
                    const SizedBox(width: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () =>
                          _renameCandidate(context, c, () => setState(() {})),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined, size: 15, color: _blue),
                      ),
                    ),
                  ],
                ]),
                Text('matyta ${c.occurrences}x · ${c.cadence}',
                    style: const TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          Text('${c.amount.toStringAsFixed(2)} €',
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
        ]),
        if (c.hint != null && c.customName == null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
                color: _amberSoft, borderRadius: BorderRadius.circular(8)),
            child: Text(c.hint!,
                style: const TextStyle(fontSize: 11.5, color: _amber, height: 1.3)),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _dismiss(c),
              icon: const Icon(Icons.close_rounded, size: 16, color: _bad),
              label: const Text('Ne', style: TextStyle(color: _bad, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                  backgroundColor: _bad.withValues(alpha: 0.06),
                  side: const BorderSide(color: _bad, width: 1.3),
                  padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirm(c),
              icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              label: const Text('Taip, sąskaita'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _good,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ),
        ]),
      ]),
    );
  }
}
