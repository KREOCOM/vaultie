// STANDALONE DEMO — 2026-08-13. Same visual language as subs_sort_demo.dart /
// bills_sort_demo.dart, but reading REAL data: the last synced dashboard
// payload already cached on this device (DashboardStore.load()), and writing
// real decisions back through the SAME mechanisms the live app already uses
// (setRecurringType, markRecurringReviewed, setRecurringOverride,
// setSubscriptionAlias) — all keyed by the backend's own `sid`.
//
// Client-only: no backend change, no new persistence. The backend currently
// only ever sends CONFIDENT recurring candidates (functions/dashboard.py
// filters on `confident and occurrences>=2`), so there is no low-confidence
// "show all merchants" tier here yet — that needs a small backend addition
// first. This screen only sorts what the app already received.
//
// Does not touch the real app's navigation — reachable only via its own
// entry point. Run standalone (real device, real signed-in account) with:
//   flutter run --profile -t lib/main_subs_live.dart
//
// Delete this file + lib/main_subs_live.dart to remove the experiment.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/dashboard_store.dart';
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

String _cadenceLabel(String? cycle) {
  switch (cycle) {
    case 'weekly':
      return 'kas savaitę';
    case 'yearly':
      return 'kas metus';
    case 'quarterly':
      return 'kas ketvirtį';
    default:
      return 'kas mėnesį';
  }
}

/// One real recurring stream, as the backend sent it — `subs['items']` shape
/// documented in dashboard_preview.dart's `_recItems`:
/// {name, monthly, cost, cycle, status, active, type, occ, sid, lastCharge}.
class _LiveItem {
  _LiveItem(this.raw);
  final Map raw;

  /// The backend's series id, or — for a payload old enough to carry none
  /// (also true of the design-preview's canned demo items, which are plain
  /// name/amount pairs with no backend id at all) — the same name|amount
  /// fallback dashboard_preview.dart's `_recKey` uses, so every DashboardStore
  /// call below stays keyed the same way the rest of the app already keys it.
  String get sid {
    final backendSid = (raw['sid'] as String?) ?? '';
    if (backendSid.isNotEmpty) return backendSid;
    final name = merchant.trim().toLowerCase();
    if (name.isEmpty) return '';
    return '$name|${monthly.toStringAsFixed(2)}';
  }
  String get merchant => (raw['name'] as String?) ?? '—';
  double get monthly => ((raw['monthly'] ?? raw['cost'] ?? 0) as num).toDouble();
  int get occ => (raw['occ'] as num?)?.toInt() ?? 0;
  String get cadence => _cadenceLabel(raw['cycle'] as String?);

  /// Backend's own guess, overridden by the user's past reclassification —
  /// the exact same lookup dashboard_preview.dart's `_recType` does.
  String get type {
    final o = sid.isEmpty ? null : DashboardStore.recurringTypes()[sid];
    return o ?? (raw['type'] as String?) ?? 'subscription';
  }

  String get displayName {
    final a = sid.isEmpty ? null : DashboardStore.subscriptionAliases()[sid];
    return (a != null && a.isNotEmpty) ? a : merchant;
  }

  bool get reviewed =>
      sid.isNotEmpty && DashboardStore.recurringReviewed().contains(sid);
  bool get excluded =>
      sid.isNotEmpty && DashboardStore.recurringExcluded().contains(sid);
}

List<_LiveItem> _loadLiveItems([List<Map>? rawOverride]) {
  final List rawItems;
  if (rawOverride != null) {
    rawItems = rawOverride;
  } else {
    final dash = DashboardStore.load();
    final subs = dash?['subs'];
    rawItems = (subs is Map) ? (subs['items'] as List? ?? const []) : const [];
  }
  return rawItems
      .whereType<Map>()
      .map((e) => _LiveItem(e))
      .where((it) => it.sid.isNotEmpty)
      .toList();
}

Future<void> _renameLive(BuildContext context, _LiveItem it, VoidCallback onChanged) async {
  final ctl = TextEditingController(text: it.displayName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Kaip pavadinti?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '„${it.merchant}" (${it.monthly.toStringAsFixed(2)} €) — įvesk tikrąjį pavadinimą. '
              'Pervadinimas paveiks tik šitos kainos mokėjimus.',
              style: const TextStyle(fontSize: 13, color: _subtle, height: 1.4)),
          const SizedBox(height: 12),
          TextField(controller: ctl, autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Atšaukti')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text('Patvirtinti'),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) {
    await DashboardStore.setSubscriptionAlias(it.sid, name);
    onChanged();
  }
}

class LiveRecurringScreen extends StatefulWidget {
  const LiveRecurringScreen(
      {super.key, required this.wantType, required this.title, this.itemsOverride});
  final String wantType; // 'subscription' | 'bill'
  final String title; // 'Prenumeratos' | 'Sąskaitos'
  // When the caller already has the recurring items in memory (e.g. the
  // dashboard's own `_d`, which can be fresher than — or, in the design
  // preview, entirely separate from — DashboardStore's disk snapshot), pass
  // them here instead of re-reading DashboardStore.load(). Standalone runs
  // (main_subs_live.dart on a real signed-in device) leave this null and read
  // the real synced snapshot.
  final List<Map>? itemsOverride;

  @override
  State<LiveRecurringScreen> createState() => _LiveRecurringScreenState();
}

class _LiveRecurringScreenState extends State<LiveRecurringScreen>
    with SingleTickerProviderStateMixin {
  late List<_LiveItem> _all = _loadLiveItems(widget.itemsOverride);
  late final AnimationController _waveCtl =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  bool get _isSubs => widget.wantType == 'subscription';

  List<_LiveItem> get _confirmed => _all
      .where((it) => it.type == widget.wantType && it.reviewed && !it.excluded)
      .toList();
  List<_LiveItem> get _pending =>
      _all.where((it) => it.type == widget.wantType && !it.reviewed).toList();

  double get _monthlyTotal => _confirmed.fold(0.0, (s, it) => s + it.monthly);
  double get _yearlyTotal => _monthlyTotal * 12;

  @override
  void dispose() {
    _waveCtl.dispose();
    super.dispose();
  }

  Future<void> _openSort() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LiveSortScreen(
        items: _pending,
        wantType: widget.wantType,
        onChanged: () => setState(() {}),
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
        title: Text(widget.title,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
      ),
      body: (widget.itemsOverride == null && !DashboardStore.hasData)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Nerasta sinchronizuotų banko duomenų šiame įrenginyje.\n'
                    'Atidaryk tikrąją Vaultie ir susisiek su banku bent kartą.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _subtle)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                if (_confirmed.isEmpty) _hero() else ...[
                  _totalCard(),
                  const SizedBox(height: 14),
                  for (final it in _confirmed) ...[
                    _tile(it),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  _addMoreRow(),
                ],
              ],
            ),
    );
  }

  Widget _hero() => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_blueDeep, _blue]),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: _blue.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 12)),
          ],
        ),
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _waveCtl,
              builder: (_, __) => CustomPaint(painter: _WavePainter(_waveCtl.value)),
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
                      color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: Icon(_isSubs ? Icons.auto_awesome_rounded : Icons.receipt_long_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(height: 18),
                Text(_isSubs ? 'Rask savo prenumeratas' : 'Rask savo sąskaitas',
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                    'Vaultie rado pasikartojančių mokėjimų tavo banko istorijoje. '
                    'Padėk mums atpažinti, kuriuos iš jų nori sekti.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.94),
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _pending.isEmpty ? null : _openSort,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _blueDeep,
                      // Nothing left to review is a real, calm state (every
                      // stream already sorted) — not an error, so the button
                      // stays a dim white pill, never the default Material
                      // grey-on-dark that read as a broken black button on
                      // this blue hero.
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
                      disabledForegroundColor: _blueDeep.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Peržiūrėti mokėjimus',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                    _pending.isEmpty
                        ? 'Nieko naujo nerasta'
                        : '${_pending.length} galimi mokėjimai',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ]),
      );

  Widget _totalCard() => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_blueDeep, _blue]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: _blue.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration:
                  BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_isSubs ? Icons.autorenew_rounded : Icons.receipt_long_rounded,
                    color: Colors.white, size: 15),
                const SizedBox(width: 8),
                Text(
                    '${_confirmed.length} ${_confirmed.length == 1 ? (_isSubs ? "aktyvi prenumerata" : "aktyvi sąskaita") : (_isSubs ? "aktyvios prenumeratos" : "aktyvios sąskaitos")}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _statText('Per mėnesį', _monthlyTotal)),
            Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.22)),
            const SizedBox(width: 18),
            Expanded(child: _statText('Per metus', _yearlyTotal)),
          ]),
        ]),
      );

  Widget _statText(String label, double value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text('${value.toStringAsFixed(2)} €',
              style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ],
      );

  Widget _addMoreRow() => InkWell(
        onTap: _pending.isEmpty ? null : _openSort,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(Icons.add_circle_outline_rounded, color: _pending.isEmpty ? _faint : _blue, size: 20),
            const SizedBox(width: 10),
            Text(_isSubs ? 'Rasti naują prenumeratą' : 'Rasti naują sąskaitą',
                style: TextStyle(
                    color: _pending.isEmpty ? _faint : _blue, fontWeight: FontWeight.w700, fontSize: 14.5)),
            if (_pending.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: _blueSoft, borderRadius: BorderRadius.circular(20)),
                child: Text('${_pending.length}',
                    style: const TextStyle(color: _blue, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
        ),
      );

  Future<void> _removeConfirmed(_LiveItem it) async {
    await DashboardStore.setRecurringOverride(it.sid, false);
    setState(() {});
  }

  Widget _tile(_LiveItem it) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
        child: Row(children: [
          CategoryIcon(
              icon: _isSubs ? Icons.autorenew_rounded : Icons.receipt_long_rounded,
              color: _blue,
              size: 40,
              merchant: it.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                Text(it.cadence, style: const TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${it.monthly.toStringAsFixed(2)} €',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _renameLive(context, it, () => setState(() {})),
                  child: const Padding(
                      padding: EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 16, color: _blue)),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _removeConfirmed(it),
                  child: const Padding(
                      padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 16, color: _bad)),
                ),
              ]),
            ],
          ),
        ]),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.t);
  final double t;

  void _band(Canvas canvas, Size size, double phase, double baseY, double amp, double wavelengths, Color color) {
    final path = Path()..moveTo(0, 0);
    path.lineTo(0, baseY);
    for (double x = 0; x <= size.width; x += 6) {
      final y = baseY + amp * math.sin((x / size.width * wavelengths * 2 * math.pi) + phase);
      path.lineTo(x, y);
    }
    path.lineTo(size.width, 0);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final phase = t * 2 * math.pi;
    _band(canvas, size, phase, size.height * 0.16, 16, 1.4, Colors.white.withValues(alpha: 0.09));
    _band(canvas, size, -phase * 1.3 + math.pi / 3, size.height * 0.11, 12, 1.8, Colors.white.withValues(alpha: 0.07));
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.t != t;
}

class _LiveSortScreen extends StatefulWidget {
  const _LiveSortScreen({required this.items, required this.wantType, required this.onChanged});
  final List<_LiveItem> items;
  final String wantType;
  final VoidCallback onChanged;

  @override
  State<_LiveSortScreen> createState() => _LiveSortScreenState();
}

class _LiveSortScreenState extends State<_LiveSortScreen> {
  String _query = '';
  late List<_LiveItem> _items = widget.items;

  List<_LiveItem> get _visible {
    if (_query.trim().isEmpty) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((it) => it.displayName.toLowerCase().contains(q)).toList();
  }

  Future<void> _confirm(_LiveItem it) async {
    await DashboardStore.setRecurringType(it.sid, widget.wantType);
    await DashboardStore.markRecurringReviewed(it.sid);
    setState(() => _items.remove(it));
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('„${it.displayName}" pridėta'), duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _dismiss(_LiveItem it) async {
    await DashboardStore.setRecurringOverride(it.sid, false);
    await DashboardStore.markRecurringReviewed(it.sid);
    setState(() => _items.remove(it));
    widget.onChanged();
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
      body: Column(children: [
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _line)),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              for (final it in visible) ...[_row(it), const SizedBox(height: 10)],
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text('Nieko nerasta.', textAlign: TextAlign.center, style: TextStyle(color: _subtle)),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _row(_LiveItem it) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryIcon(
              icon: widget.wantType == 'subscription' ? Icons.autorenew_rounded : Icons.receipt_long_rounded,
              color: _blue,
              size: 40,
              merchant: it.displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(it.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                  ),
                  const SizedBox(width: 2),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _renameLive(context, it, () => setState(() {})),
                    child: const Padding(
                        padding: EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 15, color: _blue)),
                  ),
                ]),
                Text('matyta ${it.occ}x · ${it.cadence}', style: const TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          Text('${it.monthly.toStringAsFixed(2)} €',
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _dismiss(it),
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
              onPressed: () => _confirm(it),
              icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              label: Text(widget.wantType == 'subscription' ? 'Taip, prenumerata' : 'Taip, sąskaita'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _good, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ),
        ]),
      ]),
    );
  }
}
