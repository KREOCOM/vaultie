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
import '../../services/notification_service.dart' show predictedDueDate;
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

// 2026-08-16: layered rings — one ring per subscription, radius ranked by
// size (biggest = outermost), sweep proportional to its share of the
// monthly total. First pass (see the HTML mockup this was picked from) used
// a faint 10%-alpha track and thin strokes that all but disappeared against
// the blue card on a real screen — "tik rysius padaryk kad matytųsi
// vaizdas". Track brightened to 26% and every ring gets a floor on its
// sweep angle so even a small subscription (SEB at 2 €) still draws a
// visible arc instead of a barely-there sliver.
class _RingsPainter extends CustomPainter {
  _RingsPainter(this.entries, this.total, {this.progress = 1});
  final List<MapEntry<String, double>> entries; // name -> monthly, sorted desc
  final double total;
  final double progress;

  static const palette = [
    Color(0xFF7DD3FC),
    Color(0xFFC4B5FD),
    Color(0xFF86EFAC),
    Color(0xFFFCD34D),
    Color(0xFFFDA4AF),
    Color(0xFFFDBA74),
  ];

  static const double _strokeW = 13;
  static const double _minR = 32;
  static const double _minSweep = 0.30; // radians, ~17° — never fully disappears

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.isEmpty || total <= 0) return;
    final center = size.center(Offset.zero);
    final maxR = size.width / 2 - _strokeW / 2;
    final n = entries.length;
    final step = n > 1 ? (maxR - _minR) / (n - 1) : 0.0;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeW;
    for (var i = 0; i < n; i++) {
      final r = maxR - step * i;
      canvas.drawCircle(center, r, track);
    }
    for (var i = 0; i < n; i++) {
      final r = maxR - step * i;
      final share = entries[i].value / total;
      final sweep = math.max(share * 2 * math.pi, _minSweep) * progress;
      final arc = Paint()
        ..color = palette[i % palette.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeW
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: r), -math.pi / 2, sweep, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.entries != entries || old.total != total || old.progress != progress;
}

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
  String get cycleRaw => (raw['cycle'] as String?) ?? 'monthly';
  String? get lastChargeIso => raw['lastCharge'] as String?;

  /// Predicted next due date — last real charge + one cycle, or the user's
  /// own day-of-month correction if they've set one. Same function
  /// notification_service.dart's reminder scheduler uses, so the calendar
  /// chart and the actual reminder can never show two different dates.
  DateTime? get dueDate =>
      predictedDueDate(sid, lastChargeIso: lastChargeIso, cycle: cycleRaw);

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
      {super.key,
      required this.wantType,
      required this.title,
      this.itemsOverride,
      this.allTransactions});
  final String wantType; // 'subscription' | 'bill'
  final String title; // 'Prenumeratos' | 'Sąskaitos'
  // When the caller already has the recurring items in memory (e.g. the
  // dashboard's own `_d`, which can be fresher than — or, in the design
  // preview, entirely separate from — DashboardStore's disk snapshot), pass
  // them here instead of re-reading DashboardStore.load(). Standalone runs
  // (main_subs_live.dart on a real signed-in device) leave this null and read
  // the real synced snapshot.
  final List<Map>? itemsOverride;

  // The FULL transaction list (dashboard_preview.dart's `_d['all']`) — only
  // used for the manual "search my own transactions" fallback in
  // _LiveSortScreen, for a merchant the backend never flagged as a
  // recurring candidate at all (so it can't be in itemsOverride either).
  // Null on the standalone entry point, same as itemsOverride.
  final List<Map>? allTransactions;

  @override
  State<LiveRecurringScreen> createState() => _LiveRecurringScreenState();
}

class _LiveRecurringScreenState extends State<LiveRecurringScreen>
    with TickerProviderStateMixin {
  late List<_LiveItem> _all = _loadLiveItems(widget.itemsOverride);
  late final AnimationController _waveCtl =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
  // 2026-08-16: the layered-rings chart's own one-shot draw-in — separate
  // controller from _waveCtl (a continuous 8s loop), so SingleTicker becomes
  // TickerProviderStateMixin to allow both at once.
  late final AnimationController _ringsCtl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 750))..forward();

  bool get _isSubs => widget.wantType == 'subscription';

  List<_LiveItem> get _confirmed => _all
      .where((it) => it.type == widget.wantType && it.reviewed && !it.excluded)
      .toList();
  List<_LiveItem> get _pending =>
      _all.where((it) => it.type == widget.wantType && !it.reviewed).toList();

  // The sort screen is worth opening whenever there's EITHER a backend
  // candidate left to review OR real transactions to manually search — not
  // just the former. A user with nothing auto-detected is exactly the one
  // who needs the manual search most; disabling the only door to it there
  // locked them out of the feature entirely.
  bool get _canOpenSort => _pending.isNotEmpty || (widget.allTransactions?.isNotEmpty ?? false);

  double get _monthlyTotal => _confirmed.fold(0.0, (s, it) => s + it.monthly);
  double get _yearlyTotal => _monthlyTotal * 12;

  @override
  void dispose() {
    _waveCtl.dispose();
    _ringsCtl.dispose();
    super.dispose();
  }

  Future<void> _openSort() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LiveSortScreen(
        items: _pending,
        wantType: widget.wantType,
        onChanged: () => setState(() {}),
        allTransactions: widget.allTransactions,
        // Every name already tracked in EITHER pool (any type, confirmed or
        // still pending) — never offer "add manually" for a merchant that
        // already has a verdict somewhere, subscription or bill.
        existingNames: _all.map((it) => it.merchant.trim().toLowerCase()).toSet(),
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
                    onPressed: _canOpenSort ? _openSort : null,
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
                    _pending.isNotEmpty
                        ? '${_pending.length} galimi mokėjimai'
                        : (_canOpenSort ? 'Ieškok pats savo tranzakcijose' : 'Nieko naujo nerasta'),
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
          // 2026-08-16: layered rings ("sluoksniuoti žiedai") tried first —
          // rejected on a real device as too abstract/cold. Replaced with
          // "sąrašas su juostelėmis" (dot + name + proportional mini-bar +
          // amount), picked from the second HTML comparison round.
          // _ringsChart/_RingsPainter left defined, unused, in case rings
          // are worth revisiting differently later. Prenumeratos only for
          // now (_isSubs) — Sąskaitos usually has just 1-2 entries.
          if (_isSubs && _confirmed.isNotEmpty) ...[
            const SizedBox(height: 16),
            _rankedBarsList(),
          ],
          // 2026-08-16: "stulpelių eilutė" (bar-skyline) tried first for
          // Sąskaitos, replaced per request with the due-date calendar
          // (variant D, second HTML round) — WHEN each bill is due, not
          // just how much. The predicted day can drift by a day if a bank
          // processes a charge early/late (see predictedDueDate's own doc);
          // tapping a bill lets the user correct it, stored via
          // DashboardStore.setRecurringDueDay and read back everywhere
          // that date matters, including the actual payment reminder.
          // _barSkyline left defined, unused.
          if (!_isSubs && _confirmed.isNotEmpty) ...[
            const SizedBox(height: 16),
            _dueDateCalendar(),
          ],
          const SizedBox(height: 22),
          Row(children: [
            Expanded(child: _statText('Per mėnesį', _monthlyTotal)),
            Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.22)),
            const SizedBox(width: 18),
            Expanded(child: _statText('Per metus', _yearlyTotal)),
          ]),
        ]),
      );

  static const List<Color> _rankPalette = [
    Color(0xFF7DD3FC),
    Color(0xFFC4B5FD),
    Color(0xFF86EFAC),
    Color(0xFFFCD34D),
    Color(0xFFFDA4AF),
  ];

  Widget _rankedBarsList() {
    final sorted = [..._confirmed]..sort((a, b) => b.monthly.compareTo(a.monthly));
    final maxV = sorted.first.monthly;
    return Column(
      children: [
        for (var i = 0; i < sorted.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _rankPalette[i % _rankPalette.length]),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 82,
                child: Text(sorted[i].displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Stack(children: [
                      Container(color: Colors.white.withValues(alpha: 0.16)),
                      FractionallySizedBox(
                        widthFactor: (sorted[i].monthly / maxV).clamp(0.04, 1.0),
                        child: Container(color: _rankPalette[i % _rankPalette.length]),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text('${sorted[i].monthly.toStringAsFixed(2)} €',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
      ],
    );
  }

  static const List<Color> _calPalette = [
    Color(0xFF7DD3FC),
    Color(0xFFFCD34D),
    Color(0xFF86EFAC),
    Color(0xFFC4B5FD),
    Color(0xFFFDA4AF),
  ];

  Future<void> _editDueDay(_LiveItem it) async {
    final today = it.dueDate ?? DateTime.now();
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    var picked = today.day;
    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('„${it.displayName}" — kada nusiskaito?',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 4),
            Text(
                'Appsas numato dieną iš paskutinio tikro mokėjimo — jeigu bankas '
                'nuskaito kitą dieną, pataisyk čia. Tai nekeičia, kaip appsas '
                'atpažįsta pačią sąskaitą, tik parodomą/priminimo dieną.',
                style: TextStyle(fontSize: 12.5, color: _subtle, height: 1.4)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= daysInMonth; d++)
                  GestureDetector(
                    onTap: () => setSheetState(() => picked = d),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: picked == d ? _blue : _bg,
                        border: Border.all(color: picked == d ? _blue : _line),
                      ),
                      child: Text('$d',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: picked == d ? Colors.white : _ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Row(children: [
              if (DashboardStore.recurringDueDayOverrides().containsKey(it.sid))
                TextButton(
                  onPressed: () => Navigator.pop(ctx, -1), // sentinel: clear override
                  child: const Text('Atstatyti numatytą', style: TextStyle(color: _subtle)),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, picked),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Išsaugoti', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ]),
          ]),
        );
      }),
    );
    if (saved == null || !mounted) return;
    await DashboardStore.setRecurringDueDay(it.sid, saved == -1 ? null : saved);
    setState(() {});
  }

  Widget _dueDateCalendar() {
    final sorted = [..._confirmed]..sort((a, b) => (a.dueDate ?? DateTime(9999)).compareTo(b.dueDate ?? DateTime(9999)));
    final withDates = sorted.where((it) => it.dueDate != null).toList();
    if (withDates.isEmpty) return const SizedBox.shrink();
    final ref = withDates.first.dueDate!;
    final daysInMonth = DateTime(ref.year, ref.month + 1, 0).day;
    // A bill's predicted day can land in a DIFFERENT month than the first
    // one shown (e.g. a bill due the 2nd next to one due the 28th, viewed
    // near month-end) — only dots landing in `ref`'s month are drawn; the
    // legend row below always shows every bill regardless.
    Color? colorFor(int day) {
      for (var i = 0; i < withDates.length; i++) {
        final d = withDates[i].dueDate!;
        if (d.year == ref.year && d.month == ref.month && d.day == day) {
          return _calPalette[i % _calPalette.length];
        }
      }
      return null;
    }

    return Column(children: [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: daysInMonth,
        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 10, crossAxisSpacing: 4, mainAxisSpacing: 4),
        itemBuilder: (_, i) {
          final day = i + 1;
          final c = colorFor(day);
          return Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c ?? Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('$day',
                style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: c != null ? const Color(0xFF0B1533) : Colors.white.withValues(alpha: 0.4))),
          );
        },
      ),
      const SizedBox(height: 12),
      Column(
        children: [
          for (var i = 0; i < withDates.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: GestureDetector(
                onTap: () => _editDueDay(withDates[i]),
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _calPalette[i % _calPalette.length]),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(withDates[i].displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  Text('${withDates[i].dueDate!.day} d.',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_rounded, size: 13, color: Colors.white.withValues(alpha: 0.5)),
                ]),
              ),
            ),
        ],
      ),
    ]);
  }

  Widget _barSkyline() {
    final sorted = [..._confirmed]..sort((a, b) => b.monthly.compareTo(a.monthly));
    final maxV = sorted.first.monthly;
    return SizedBox(
      height: 118,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < sorted.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: sorted.length > 4 ? 3 : 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('${sorted[i].monthly.toStringAsFixed(0)} €',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Container(
                      height: 14 + (sorted[i].monthly / maxV) * 66,
                      decoration: BoxDecoration(
                        color: _rankPalette[i % _rankPalette.length],
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(sorted[i].displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ringsChart() {
    final sorted = [..._confirmed]..sort((a, b) => b.monthly.compareTo(a.monthly));
    final entries = [for (final it in sorted) MapEntry(it.displayName, it.monthly)];
    return Column(children: [
      SizedBox(
        width: 176,
        height: 176,
        child: AnimatedBuilder(
          animation: _ringsCtl,
          builder: (_, __) => CustomPaint(
            painter: _RingsPainter(entries, _monthlyTotal, progress: _ringsCtl.value),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 6,
        children: [
          for (var i = 0; i < entries.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _RingsPainter.palette[i % _RingsPainter.palette.length]),
              ),
              const SizedBox(width: 6),
              Text(entries[i].key,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
            ]),
        ],
      ),
    ]);
  }

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
        onTap: _canOpenSort ? _openSort : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(Icons.add_circle_outline_rounded, color: _canOpenSort ? _blue : _faint, size: 20),
            const SizedBox(width: 10),
            Text(_isSubs ? 'Rasti naują prenumeratą' : 'Rasti naują sąskaitą',
                style: TextStyle(
                    color: _canOpenSort ? _blue : _faint, fontWeight: FontWeight.w700, fontSize: 14.5)),
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

/// A merchant found by searching the user's OWN raw transactions — not one
/// of the backend's recurring candidates at all (`amount`/`occ` are our own
/// average/count over the matching rows, not the backend's).
class _TxMatch {
  const _TxMatch({required this.name, required this.avgAmount, required this.count});
  final String name;
  final double avgAmount;
  final int count;
}

class _LiveSortScreen extends StatefulWidget {
  const _LiveSortScreen({
    required this.items,
    required this.wantType,
    required this.onChanged,
    this.allTransactions,
    this.existingNames = const {},
  });
  final List<_LiveItem> items;
  final String wantType;
  final VoidCallback onChanged;
  final List<Map>? allTransactions;
  final Set<String> existingNames;

  @override
  State<_LiveSortScreen> createState() => _LiveSortScreenState();
}

class _LiveSortScreenState extends State<_LiveSortScreen> {
  String _query = '';
  late List<_LiveItem> _items = widget.items;
  // Manually added THIS session, so a just-added merchant stops showing up
  // as a "not tracked yet" search result immediately, without needing
  // widget.existingNames (fixed at screen-open time) to somehow know about it.
  final Set<String> _manuallyAdded = {};

  List<_LiveItem> get _visible {
    if (_query.trim().isEmpty) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((it) => it.displayName.toLowerCase().contains(q)).toList();
  }

  /// Merchants the backend never flagged as recurring at all — found by
  /// grouping the user's own transaction history by name. Only searched (not
  /// browsed) — a full merchant list would be mostly one-off shopping, not
  /// worth wading through for the rare subscription/bill the detector missed.
  List<_TxMatch> get _txMatches {
    final all = widget.allTransactions;
    final q = _query.trim().toLowerCase();
    if (all == null || q.isEmpty) return const [];
    final excluded = {...widget.existingNames, ..._manuallyAdded};
    final amounts = <String, List<double>>{};
    final display = <String, String>{};
    for (final t in all) {
      final nm = (t['nm'] as String?)?.trim();
      if (nm == null || nm.isEmpty) continue;
      final key = nm.toLowerCase();
      if (excluded.contains(key) || !key.contains(q)) continue;
      final amt = (t['a'] as num?)?.toDouble() ?? 0;
      if (amt >= 0) continue; // money OUT only — subs/bills are never income
      amounts.putIfAbsent(key, () => []).add(amt.abs());
      display.putIfAbsent(key, () => nm);
    }
    final out = amounts.entries.map((e) {
      final vals = e.value;
      return _TxMatch(
        name: display[e.key]!,
        avgAmount: vals.reduce((a, b) => a + b) / vals.length,
        count: vals.length,
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return out.take(8).toList();
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

  /// The user's own pick, from a transaction search — not a backend
  /// candidate at all. Same DashboardStore calls _addToRecurring (the
  /// existing transaction-detail flow) already uses, so it's tracked exactly
  /// the same way whichever door it came in through, and merges cleanly if
  /// the backend later starts detecting this merchant on its own
  /// (_recItemsFull matches manual entries onto real ones by folded name).
  Future<void> _confirmManual(_TxMatch m) async {
    final sid = 'manual:${m.name.trim().toLowerCase()}';
    await DashboardStore.addManualRecurring({
      'sid': sid,
      'name': m.name,
      'monthly': m.avgAmount,
      'cost': m.avgAmount,
      'cycle': 'monthly',
      'status': 'active',
      'active': true,
      'type': widget.wantType,
      'occ': m.count,
      'manual': true,
    });
    await DashboardStore.setRecurringType(sid, widget.wantType);
    await DashboardStore.markRecurringReviewed(sid);
    setState(() => _manuallyAdded.add(m.name.trim().toLowerCase()));
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text('„${m.name}" pridėta'), duration: const Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final txMatches = _txMatches;
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
              if (visible.isEmpty && txMatches.isEmpty && _query.trim().isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text('Nieko nerasta.', textAlign: TextAlign.center, style: TextStyle(color: _subtle)),
                ),
              if (visible.isEmpty && txMatches.isEmpty && _query.trim().isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Text('Viskas peržiūrėta.', textAlign: TextAlign.center, style: TextStyle(color: _subtle)),
                ),
              // Merchants the backend never flagged at all — found by
              // searching the user's own transaction history instead of the
              // (possibly incomplete) auto-detected candidate list.
              if (txMatches.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text('Neradai automatiškai? Iš tavo tranzakcijų:',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _subtle)),
                ),
                for (final m in txMatches) ...[_manualRow(m), const SizedBox(height: 10)],
              ],
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

  Widget _manualRow(_TxMatch m) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CategoryIcon(
              icon: widget.wantType == 'subscription' ? Icons.autorenew_rounded : Icons.receipt_long_rounded,
              color: _blue,
              size: 40,
              merchant: m.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                Text('matyta ${m.count}x · vidurkis ${m.avgAmount.toStringAsFixed(2)} €',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // The "Pridėti" button gets its OWN full-width row below, not
        // squeezed inline next to the name — that's what produced the
        // broken layout (Expanded collapsing to near-zero width, wrapping
        // the cadence text one character per line). Same pattern _row()
        // already uses successfully for its Ne/Taip buttons.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _confirmManual(m),
            icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            label: Text(widget.wantType == 'subscription' ? 'Pridėti prie prenumeratų' : 'Pridėti prie sąskaitų'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8)),
          ),
        ),
      ]),
    );
  }
}
