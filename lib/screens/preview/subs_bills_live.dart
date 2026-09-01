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

import '../../app_prefs.dart';
import '../../i18n.dart';
import '../../services/dashboard_store.dart';
import '../../services/notification_service.dart' show predictedDueDate;
import '../../ui/design_system.dart' show CategoryIcon;

// 2026-08-16: this whole screen used to be FIXED light colors regardless of
// the app's own dark-mode setting — reached via Navigator.push from the live
// dashboard (dashboard_preview.dart:4830's LiveRecurringScreen, not just the
// standalone main_subs_live.dart demo entry), so a user in dark mode tapped
// Sąskaitos/Prenumeratos from the (now violet, since today's hero fix) Home
// hero and landed on a jarring bright-white screen. Colors are now getters
// keyed off AppPrefs.darkMode (the same app-wide notifier dashboard_preview.
// dart's own theme toggle writes to) — a plain top-level bool can't be
// shared across files the way dashboard_preview.dart's own `_darkMode` is
// (underscore = library-private to that file), so this reads the public
// notifier directly instead. Dark values match dashboard_preview.dart's own
// dark palette (_ink/_card/_bg/_hair) and its violet accent (_purple/
// _purpleDeep's dark-mode values) for visual consistency with the rest of
// the app, rather than inventing a second dark palette.
Color get _ink => AppPrefs.darkMode.value ? const Color(0xFFEDEAF6) : const Color(0xFF0B1533);
Color get _subtle => AppPrefs.darkMode.value ? const Color(0xFFBDB7CE) : const Color(0xFF5B6684);
Color get _faint => AppPrefs.darkMode.value ? const Color(0xFF948DAC) : const Color(0xFF93A0C2);
Color get _line => AppPrefs.darkMode.value ? const Color(0xFF2C2740) : const Color(0xFFE6EAF2);
Color get _bg => AppPrefs.darkMode.value ? const Color(0xFF0A0910) : const Color(0xFFF6F7FB);
Color get _card => AppPrefs.darkMode.value ? const Color(0xFF16131F) : const Color(0xFFFFFFFF);
Color get _blue => AppPrefs.darkMode.value ? const Color(0xFF8B5CF6) : const Color(0xFF003DE1);
Color get _blueDeep => AppPrefs.darkMode.value ? const Color(0xFF6D3EE0) : const Color(0xFF0B2E9B);
Color get _blueSoft => AppPrefs.darkMode.value ? const Color(0xFF241C3B) : const Color(0xFFEAF0FF);
Color get _good => AppPrefs.darkMode.value ? const Color(0xFF34D399) : const Color(0xFF1FA971);
Color get _bad => AppPrefs.darkMode.value ? const Color(0xFFF87171) : const Color(0xFFD9534F);

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

// 2026-08-16: a generic payment-rail name (Apple Pay, Google Pay — some
// banks never surface the underlying merchant for these) breaks the
// assumption every OTHER key in this screen relies on, that the same name
// means the same real-world subscription. "Apple Pay" covering a 9 €
// Netflix and a 13 € Canva used to: (1) get search-grouped into one
// blended "average ~11 €" suggestion neither price actually was, (2) once
// either was added, silently hide the OTHER from ever showing up in search
// again (name-only exclusion), and (3) if added anyway, overwrite the
// first in storage (name-only manual sid — same sid, DashboardStore
// replaces on add). Rounding the amount into the key fixes all three at
// once: two genuinely different subscriptions that happen to share a
// payment-rail name stay distinct as long as their prices round to
// different whole euros; the same subscription's own FX/rounding noise
// (8.99 vs 9.01) still collapses into one, which is what should happen.
String _nameAmountKey(String name, double amount) =>
    '${name.trim().toLowerCase()}|${amount.abs().round()}';

// 2026-08-16: this screen used a naive `count == 1 ? singular : plural`
// ternary for every "N aktyvios prenumeratos"-style line — wrong for 10-20
// (and any count ending in 1 other than literal "1", e.g. 21, 31), which
// Lithuanian declines differently: 1 aktyvi prenumerata / 2-9 aktyvios
// prenumeratos / 0,10-20 aktyvių prenumeratų. `n=11` used to render "11
// aktyvios sąskaitos" (should be "11 aktyvių sąskaitų").
String _ltCount(int n, {required String one, required String few, required String many}) {
  final t = n % 100;
  if (t >= 11 && t <= 19) return many;
  switch (n % 10) {
    case 1:
      return one;
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
    case 7:
    case 8:
    case 9:
      return few;
    default:
      return many;
  }
}

bool get _isEnglishUi => effectiveLocale().languageCode == 'en';

String _activeCountLabel(int n, bool isSubs) {
  if (_isEnglishUi) {
    final noun = isSubs ? 'subscription' : 'bill';
    return '$n active $noun${n == 1 ? '' : 's'}';
  }
  final adj = _ltCount(n, one: 'aktyvi', few: 'aktyvios', many: 'aktyvių');
  final noun = isSubs
      ? _ltCount(n, one: 'prenumerata', few: 'prenumeratos', many: 'prenumeratų')
      : _ltCount(n, one: 'sąskaita', few: 'sąskaitos', many: 'sąskaitų');
  return '$n $adj $noun';
}

String _pendingCountLabel(int n) {
  if (_isEnglishUi) return '$n possible payment${n == 1 ? '' : 's'}';
  final adj = _ltCount(n, one: 'galimas', few: 'galimi', many: 'galimų');
  final noun = _ltCount(n, one: 'mokėjimas', few: 'mokėjimai', many: 'mokėjimų');
  return '$n $adj $noun';
}

String _cadenceLabel(String? cycle) {
  switch (cycle) {
    case 'weekly':
      return tr('kas savaitę');
    case 'biweekly':
      return tr('kas 2 savaites');
    case 'yearly':
      return tr('kas metus');
    case 'semiannual':
      return tr('kas pusmetį');
    case 'quarterly':
      return tr('kas ketvirtį');
    default:
      return tr('kas mėnesį');
  }
}

// 2026-09-01: added per explicit request — a confirmed item's tile showed
// its cadence ("kas mėnesį") but never the actual next DUE DATE, even
// though .dueDate (predictedDueDate) was already computed for every item
// regardless of type — Sąskaitos got a separate aggregate calendar showing
// it, Prenumeratos got nothing at all, so a subscription's next charge date
// was invisible anywhere in the app. Self-contained month-name list rather
// than reusing dashboard_preview.dart's private _monGen (different file) or
// intl's DateFormat with a 'lt' locale (needs explicit locale-data init
// this app doesn't currently do — a real crash risk to introduce casually).
const _dueMonGenLt = [
  'sausio', 'vasario', 'kovo', 'balandžio', 'gegužės', 'birželio', 'liepos',
  'rugpjūčio', 'rugsėjo', 'spalio', 'lapkričio', 'gruodžio',
];
const _dueMonEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDueDate(DateTime d) => _isEnglishUi
    ? '${_dueMonEn[d.month - 1]} ${d.day}'
    : '${d.day} ${_dueMonGenLt[d.month - 1]}';

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
      title: Text(tr('Kaip pavadinti?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '„${it.merchant}" (${it.monthly.toStringAsFixed(2)} €) — '
              '${tr('įvesk tikrąjį pavadinimą. Pervadinimas paveiks tik šitos kainos mokėjimus.')}',
              style: TextStyle(fontSize: 13, color: _subtle, height: 1.4)),
          const SizedBox(height: 12),
          TextField(controller: ctl, autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Atšaukti'))),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: Text(tr('Patvirtinti')),
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
      this.allTransactions,
      this.demo = false,
      this.onDueDateChanged});
  final String wantType; // 'subscription' | 'bill'
  final String title; // 'Prenumeratos' | 'Sąskaitos'
  // Onboarding only: auto-opens "Rasti naują prenumeratą" a moment after
  // landing here, holds it, then closes it again — so a viewer who never
  // taps anything still sees that finding new subscriptions is a thing this
  // screen does. Subscriptions only (wantType == 'subscription'); bills get
  // no auto-behaviour here.
  final bool demo;
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

  // 2026-08-21: this screen's own _editDueDay sheet writes a due-day
  // override straight to DashboardStore, but this file has no access to
  // the caller's excluded/included/consentExpiry/budget context that
  // NotificationService.scheduleFromRecurring() needs to rebuild the
  // reminder schedule — that context lives in dashboard_preview.dart's
  // `_d`/DashboardStore-derived state. Without this callback, correcting a
  // due date here only reached the calendar/list display; the actual local
  // reminder kept firing off the OLD predicted date until the next
  // auto-sync happened to run _rescheduleReminders on its own (which could
  // be hours away, or never, if the account is stale). The caller wires
  // this to its own _rescheduleReminders(_d) — see `openManager` in
  // dashboard_preview.dart's `_subsCard`. Null on the standalone entry
  // point, same as the other caller-supplied fields above.
  final VoidCallback? onDueDateChanged;

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
  void initState() {
    super.initState();
    if (widget.demo && _isSubs) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted && _canOpenSort) {
          await _openSort(autoCloseAfter: const Duration(milliseconds: 1800));
        }
      });
    }
  }

  @override
  void dispose() {
    _waveCtl.dispose();
    _ringsCtl.dispose();
    super.dispose();
  }

  Future<void> _openSort({Duration? autoCloseAfter}) async {
    final future = Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LiveSortScreen(
        items: _pending,
        wantType: widget.wantType,
        onChanged: () => setState(() {}),
        allTransactions: widget.allTransactions,
        // Every (name, ~amount) already tracked in EITHER pool (any type,
        // confirmed or still pending) — never offer "add manually" for a
        // stream that already has a verdict somewhere, subscription or
        // bill. Amount included in the key — see _nameAmountKey — so
        // adding one payment routed through a generic payment-rail name
        // (Apple Pay, Google Pay) doesn't hide every OTHER amount under
        // that same name.
        existingNames: _all.map((it) => _nameAmountKey(it.merchant, it.monthly)).toSet(),
        // Appends straight into `_all` — see _LiveSortScreen.onManualAdded's
        // own doc for why onChanged() alone wasn't enough.
        onManualAdded: (raw) => setState(() => _all.add(_LiveItem(raw))),
      ),
    ));
    // Onboarding only (see widget.demo) — closes the sort screen itself
    // after a beat, so the OUTER demo tour's own timer (which closes THIS
    // screen in turn) only ever has one route to pop, same as every other
    // step it drives.
    if (autoCloseAfter != null) {
      Future.delayed(autoCloseAfter, () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    await future;
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
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
      ),
      body: (widget.itemsOverride == null && !DashboardStore.hasData)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    tr('Nerasta sinchronizuotų banko duomenų šiame įrenginyje.\n'
                        'Atidaryk tikrąją Vaultie ir susisiek su banku bent kartą.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _subtle)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                if (_confirmed.isEmpty) _hero() else ...[
                  _totalCard(),
                  const SizedBox(height: 16),
                  // 2026-08-21 per request: nothing below the hero explained
                  // WHY this list already has entries the very first time a
                  // bank connects — read as if the app just made them up.
                  // One line sets the expectation before the cards do.
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Row(children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: _subtle),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            tr('Radome automatiškai iš tavo banko duomenų — pašalink, jei kas netinka'),
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600, color: _subtle)),
                      ),
                    ]),
                  ),
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
          // 2026-08-17: same off-center RadialGradient logic as Home's hero
          // and the Finansų Agentas banner (see dashboard_preview.dart's
          // _topBanner) — a bright spot near one corner fading toward a
          // deeper (but still clearly blue, not near-black) tone, instead of
          // a flat corner-to-corner LinearGradient.
          // 2026-08-20: dark mode's stops used to be _blue/_blueDeep lerped
          // toward near-black at a flat 0.4 — a middling purple that read as
          // faded next to the richer, genuinely-near-black deep stop the
          // light-mode blue gets. Matches Home hero's own dark-mode fix now —
          // same two hardcoded stops, no lerp.
          // 2026-08-29: dark mode's purple RadialGradient replaced with a
          // flat fill in the page's own dark background colour — same "try
          // black instead of purple" request as Home's hero, applied here
          // too since this card uses the identical gradient recipe. Light
          // mode keeps its original blue RadialGradient untouched.
          color: AppPrefs.darkMode.value ? _bg : null,
          gradient: AppPrefs.darkMode.value
              ? null
              : RadialGradient(
                  center: const Alignment(-0.7, -0.6),
                  radius: 1.5,
                  colors: [_blue, Color.lerp(_blueDeep, const Color(0xFF05050A), 0.4)!],
                  stops: const [0.0, 0.75],
                ),
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
                Text(_isSubs ? tr('Rask savo prenumeratas') : tr('Rask savo sąskaitas'),
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                    tr('Vaultie rado pasikartojančių mokėjimų tavo banko istorijoje. '
                        'Padėk mums atpažinti, kuriuos iš jų nori sekti.'),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(tr('Peržiūrėti mokėjimus'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                    _pending.isNotEmpty
                        ? _pendingCountLabel(_pending.length)
                        : (_canOpenSort ? tr('Ieškok pats savo tranzakcijose') : tr('Nieko naujo nerasta')),
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
          // 2026-08-17: same off-center RadialGradient logic as Home's hero
          // and the Finansų Agentas banner (see dashboard_preview.dart's
          // _topBanner) — a bright spot near one corner fading toward a
          // deeper (but still clearly blue, not near-black) tone, instead of
          // a flat corner-to-corner LinearGradient.
          // 2026-08-20: dark mode's stops used to be _blue/_blueDeep lerped
          // toward near-black at a flat 0.4 — a middling purple that read as
          // faded next to the richer, genuinely-near-black deep stop the
          // light-mode blue gets. Matches Home hero's own dark-mode fix now —
          // same two hardcoded stops, no lerp.
          // 2026-08-29: same flat-black-in-dark-mode swap as _hero() above.
          color: AppPrefs.darkMode.value ? _bg : null,
          gradient: AppPrefs.darkMode.value
              ? null
              : RadialGradient(
                  center: const Alignment(-0.7, -0.6),
                  radius: 1.5,
                  colors: [_blue, Color.lerp(_blueDeep, const Color(0xFF05050A), 0.4)!],
                  stops: const [0.0, 0.75],
                ),
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
                Text(_activeCountLabel(_confirmed.length, _isSubs),
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
            Expanded(child: _statText(tr('Per mėnesį'), _monthlyTotal)),
            Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.22)),
            const SizedBox(width: 18),
            Expanded(child: _statText(tr('Per metus'), _yearlyTotal)),
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
    // 2026-08-16 fix: tapping a day used to only highlight it — saving still
    // needed a separate "Išsaugoti" tap below, which read as "nothing
    // happened" ("paspaudžiu ant kitos dienos, niekas nepasikeičia"). A day
    // now saves and closes the sheet immediately, one tap, like every other
    // day-picker.
    final saved = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20, left: 20, right: 20, top: 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('„${it.displayName}" — ${tr('kada nusiskaito?')}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 4),
            Text(
                tr('Appsas numato dieną iš paskutinio tikro mokėjimo — jeigu bankas '
                    'nuskaito kitą dieną, pasirink tikrąją. Tai nekeičia, kaip appsas '
                    'atpažįsta pačią sąskaitą, tik parodomą/priminimo dieną.'),
                style: TextStyle(fontSize: 12.5, color: _subtle, height: 1.4)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= daysInMonth; d++)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, d),
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: today.day == d ? _blue : _bg,
                        border: Border.all(color: today.day == d ? _blue : _line),
                      ),
                      child: Text('$d',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: today.day == d ? Colors.white : _ink)),
                    ),
                  ),
              ],
            ),
            if (DashboardStore.recurringDueDayOverrides().containsKey(it.sid)) ...[
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, -1), // sentinel: clear override
                  child: Text(tr('Atstatyti numatytą dieną'), style: TextStyle(color: _subtle)),
                ),
              ),
            ],
          ]),
        );
      },
    );
    if (saved == null || !mounted) return;
    await DashboardStore.setRecurringDueDay(it.sid, saved == -1 ? null : saved);
    setState(() {});
    // See widget.onDueDateChanged's own doc comment — the reminder
    // notification has to be rebuilt now, not left to whenever the next
    // auto-sync happens to run. Never in the onboarding demo — same rule as
    // every other write in this app: the demo tour is decoration and must
    // not touch a real signed-in user's actual notification schedule.
    if (!widget.demo) widget.onDueDateChanged?.call();
  }

  Widget _dueDateCalendar() {
    // 2026-08-16 perf fix: `.dueDate` re-decodes DashboardStore's overrides
    // JSON from Hive on EVERY call (predictedDueDate → recurringDueDayOverrides).
    // The old version called it inside a 31-cell grid's per-cell color lookup,
    // each scanning every bill — up to 31×N fresh Hive reads on one build, a
    // real contributor to the app feeling laggy on this screen. Computed once
    // here instead, reused everywhere below.
    final withDates = <_LiveItem>[];
    final dates = <DateTime>[];
    for (final it in _confirmed) {
      final d = it.dueDate;
      if (d != null) {
        withDates.add(it);
        dates.add(d);
      }
    }
    if (withDates.isEmpty) return const SizedBox.shrink();
    final order = List<int>.generate(withDates.length, (i) => i)
      ..sort((a, b) => dates[a].compareTo(dates[b]));
    final sortedItems = [for (final i in order) withDates[i]];
    final sortedDates = [for (final i in order) dates[i]];
    final ref = sortedDates.first;
    final daysInMonth = DateTime(ref.year, ref.month + 1, 0).day;
    // A bill's predicted day can land in a DIFFERENT month than the first
    // one shown (e.g. a bill due the 2nd next to one due the 28th, viewed
    // near month-end) — only dots landing in `ref`'s month are drawn; the
    // legend row below always shows every bill regardless.
    List<Color> colorsFor(int day) => [
          for (var i = 0; i < sortedDates.length; i++)
            if (sortedDates[i].year == ref.year &&
                sortedDates[i].month == ref.month &&
                sortedDates[i].day == day)
              _calPalette[i % _calPalette.length],
        ];

    return Column(children: [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: daysInMonth,
        // 2026-08-16: 10 columns made the cells tiny ("kvadratukus didesnius
        // padaryti") — 7 columns (a real calendar week) gives each cell
        // ~40% more area and reads more like an actual calendar besides.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, crossAxisSpacing: 5, mainAxisSpacing: 5, childAspectRatio: 1),
        itemBuilder: (_, i) {
          final day = i + 1;
          final colors = colorsFor(day);
          // 2026-08-29: the card's background is now flat near-black in dark
          // mode (see _totalCard's own doc) instead of the old purple/blue
          // gradient — the previous BLACK tint for an empty day ("recedes
          // into the gradient") now tints black-on-black, i.e. no visible
          // cell at all, just a bare number floating on the card
          // ("skaičiai... plaukiotų juodam fone", reported). A light tint +
          // a faint border gives the cell an actual edge to read as a grid
          // square again; the old dark-tint-on-gradient look is unchanged
          // for light mode, which still has the blue gradient card.
          final onBlack = AppPrefs.darkMode.value;
          return ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Container(
              decoration: BoxDecoration(
                color: colors.isEmpty
                    ? (onBlack
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.32))
                    : (colors.length == 1 ? colors.first : null),
                border: colors.isEmpty && onBlack
                    ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                    : null,
              ),
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Two+ bills the SAME day used to just show whichever bill
                  // happened to be checked first — "MOGO laimėjo, jo spalva
                  // rodoma" even though Apple Pay was ALSO due that day.
                  // Split the cell into equal vertical bands, one per bill,
                  // so a shared day is visibly shared.
                  if (colors.length > 1)
                    Row(
                      children: [
                        for (final c in colors) Expanded(child: Container(color: c)),
                      ],
                    ),
                  Text('$day',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.isEmpty
                              ? Colors.white.withValues(alpha: 0.6)
                              : const Color(0xFF0B1533))),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      Column(
        children: [
          for (var i = 0; i < sortedItems.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: GestureDetector(
                onTap: () => _editDueDay(sortedItems[i]),
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
                    child: Text(sortedItems[i].displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  Text(_isEnglishUi ? 'Day ${sortedDates[i].day}' : '${sortedDates[i].day} d.',
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

  // 2026-08-16: was a small left-aligned text row, easy to miss — "gali
  // padaryti ant abieju [Prenumeratos ir Sąskaitos] kad būtų didesnis ir
  // per vidury". Both screens already share this one method (_isSubs just
  // swaps the label), so making it bigger/centered here covers both.
  // Full-width with its own border so it reads as a real button, not text.
  Widget _addMoreRow() => InkWell(
        onTap: _canOpenSort ? _openSort : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _canOpenSort ? _blue.withValues(alpha: 0.35) : _line, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded, color: _canOpenSort ? _blue : _faint, size: 23),
              const SizedBox(width: 10),
              Text(_isSubs ? tr('Rasti naują prenumeratą') : tr('Rasti naują sąskaitą'),
                  style: TextStyle(
                      color: _canOpenSort ? _blue : _faint, fontWeight: FontWeight.w800, fontSize: 16.5)),
              if (_pending.isNotEmpty) ...[
                const SizedBox(width: 9),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: _blueSoft, borderRadius: BorderRadius.circular(20)),
                  child: Text('${_pending.length}',
                      style: TextStyle(color: _blue, fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
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
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                Text(
                    it.dueDate != null
                        ? '${it.cadence} · ${tr('kitas mokėjimas')} ${_fmtDueDate(it.dueDate!)}'
                        : it.cadence,
                    style: TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${it.monthly.toStringAsFixed(2)} €',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _renameLive(context, it, () => setState(() {})),
                  child: Padding(
                      padding: const EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 16, color: _blue)),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _removeConfirmed(it),
                  child: Padding(
                      padding: const EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 16, color: _bad)),
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
  const _TxMatch(
      {required this.name, required this.avgAmount, required this.count, this.lastChargeIso});
  final String name;
  final double avgAmount;
  final int count;
  final String? lastChargeIso;
}

class _LiveSortScreen extends StatefulWidget {
  const _LiveSortScreen({
    required this.items,
    required this.wantType,
    required this.onChanged,
    this.allTransactions,
    this.existingNames = const {},
    this.onManualAdded,
  });
  final List<_LiveItem> items;
  final String wantType;
  final VoidCallback onChanged;
  final List<Map>? allTransactions;
  // The raw item just persisted via _confirmManual, so the parent screen
  // can append it directly instead of relying on a stale snapshot — see
  // that call site's own comment.
  final void Function(Map<String, dynamic> raw)? onManualAdded;
  // _nameAmountKey(name, amount) strings, not bare names — see that
  // function's doc for why a name alone isn't a safe key.
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

  // 2026-08-21: a bank's own description ("Apple Pay", a generic card-rail
  // label) is what _txMatches searches and groups by — exactly right for
  // FINDING the transaction, wrong as the name saved to Prenumeratos/
  // Sąskaitos (every Apple Pay purchase would show that instead of the real
  // merchant). Keyed by the ORIGINAL match identity (name+amount, never the
  // edited text) so a rename doesn't break re-matching this same search
  // result across rebuilds.
  final Map<String, String> _renamed = {};
  String _matchKey(_TxMatch m) => _nameAmountKey(m.name, m.avgAmount);
  String _displayNameFor(_TxMatch m) => _renamed[_matchKey(m)] ?? m.name;

  Future<void> _renamePrompt(_TxMatch m) async {
    final ctrl = TextEditingController(text: _displayNameFor(m));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Pervadinti'),
            style: TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: _ink),
          decoration: InputDecoration(
            hintText: m.name,
            hintStyle: TextStyle(color: _subtle),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Atšaukti'), style: TextStyle(color: _subtle))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Išsaugoti'),
                  style: TextStyle(color: _blue, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    ctrl.dispose();
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty || !mounted) return;
    setState(() => _renamed[_matchKey(m)] = trimmed);
  }

  List<_LiveItem> get _visible {
    if (_query.trim().isEmpty) return _items;
    final q = _query.trim().toLowerCase();
    return _items.where((it) => it.displayName.toLowerCase().contains(q)).toList();
  }

  /// Merchants the backend never flagged as recurring at all — found by
  /// grouping the user's own transaction history by name AND amount (see
  /// _nameAmountKey). Only searched (not browsed) — a full merchant list
  /// would be mostly one-off shopping, not worth wading through for the
  /// rare subscription/bill the detector missed.
  List<_TxMatch> get _txMatches {
    final all = widget.allTransactions;
    final q = _query.trim().toLowerCase();
    if (all == null || q.isEmpty) return const [];
    final excluded = {...widget.existingNames, ..._manuallyAdded};
    final amounts = <String, List<double>>{};
    final display = <String, String>{};
    // 2026-08-16: manually-added entries used to carry no charge date at
    // all (nothing here ever set one), so predictedDueDate() had nothing
    // to work from — a manually added bill silently never showed up in
    // the due-date calendar or got a payment reminder. The latest matching
    // transaction's own date now travels with the match into
    // _confirmManual's 'lastCharge'.
    final lastDate = <String, String>{};
    for (final t in all) {
      final nm = (t['nm'] as String?)?.trim();
      if (nm == null || nm.isEmpty) continue;
      if (!nm.toLowerCase().contains(q)) continue;
      final amt = (t['a'] as num?)?.toDouble() ?? 0;
      if (amt >= 0) continue; // money OUT only — subs/bills are never income
      final key = _nameAmountKey(nm, amt);
      if (excluded.contains(key)) continue;
      amounts.putIfAbsent(key, () => []).add(amt.abs());
      display.putIfAbsent(key, () => nm);
      final d = (t['d'] as String?) ?? '';
      if (d.isNotEmpty && d.compareTo(lastDate[key] ?? '') > 0) lastDate[key] = d;
    }
    final out = amounts.entries.map((e) {
      final vals = e.value;
      return _TxMatch(
        name: display[e.key]!,
        avgAmount: vals.reduce((a, b) => a + b) / vals.length,
        count: vals.length,
        lastChargeIso: lastDate[e.key],
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
            content: Text('„${it.displayName}" ${tr('pridėta')}'),
            duration: const Duration(seconds: 2)));
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
    // Amount folded into the sid too — a name-only sid meant a second
    // manual entry sharing a payment-rail name (Apple Pay) had the SAME
    // sid as the first, and DashboardStore.addManualRecurring replaces on
    // add, so the second one silently overwrote the first instead of
    // becoming its own tracked stream.
    final sid = 'manual:${_nameAmountKey(m.name, m.avgAmount)}';
    final displayName = _displayNameFor(m);
    final raw = <String, dynamic>{
      'sid': sid,
      'name': displayName,
      'monthly': m.avgAmount,
      'cost': m.avgAmount,
      'cycle': 'monthly',
      'status': 'active',
      'active': true,
      'type': widget.wantType,
      'occ': m.count,
      'manual': true,
      // Without this, predictedDueDate() has nothing to work from — the
      // item silently never appeared in the due-date calendar or got a
      // reminder scheduled (see _txMatches' own lastDate tracking).
      'lastCharge': m.lastChargeIso,
    };
    await DashboardStore.addManualRecurring(raw);
    await DashboardStore.setRecurringType(sid, widget.wantType);
    await DashboardStore.markRecurringReviewed(sid);
    setState(() => _manuallyAdded.add(_nameAmountKey(m.name, m.avgAmount)));
    // 2026-08-16 fix: onChanged() alone just re-rendered the PARENT screen
    // with its ORIGINAL, one-time-loaded `_all` list — a manual add never
    // existed in that snapshot, so the new bill was invisible until the
    // whole screen was reopened from scratch (which rebuilds `_all` fresh).
    // onManualAdded hands the parent the exact item to append directly.
    widget.onManualAdded?.call(raw);
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text('„$displayName" ${tr('pridėta')}'),
                duration: const Duration(seconds: 2)));
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
        title: Text(tr('Peržiūrėk mokėjimus'),
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: tr('Ieškoti pagal pavadinimą…'),
              prefixIcon: Icon(Icons.search_rounded, color: _faint),
              filled: true,
              fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _line)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _line)),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              for (final it in visible) ...[_row(it), const SizedBox(height: 10)],
              if (visible.isEmpty && txMatches.isEmpty && _query.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(tr('Nieko nerasta.'), textAlign: TextAlign.center, style: TextStyle(color: _subtle)),
                ),
              if (visible.isEmpty && txMatches.isEmpty && _query.trim().isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Text(tr('Viskas peržiūrėta.'), textAlign: TextAlign.center, style: TextStyle(color: _subtle)),
                ),
              // Merchants the backend never flagged at all — found by
              // searching the user's own transaction history instead of the
              // (possibly incomplete) auto-detected candidate list.
              if (txMatches.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(tr('Neradai automatiškai? Iš tavo tranzakcijų:'),
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
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                  ),
                  const SizedBox(width: 2),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _renameLive(context, it, () => setState(() {})),
                    child: Padding(
                        padding: const EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 15, color: _blue)),
                  ),
                ]),
                Text('${tr('matyta')} ${it.occ}x · ${it.cadence}',
                    style: TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          Text('${it.monthly.toStringAsFixed(2)} €',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: _ink)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _dismiss(it),
              icon: Icon(Icons.close_rounded, size: 16, color: _bad),
              label: Text(tr('Ne'), style: TextStyle(color: _bad, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                  backgroundColor: _bad.withValues(alpha: 0.06),
                  side: BorderSide(color: _bad, width: 1.3),
                  padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirm(it),
              icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              label: Text(widget.wantType == 'subscription'
                  ? tr('Taip, prenumerata')
                  : tr('Taip, sąskaita')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _good, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _manualRow(_TxMatch m) {
    final displayName = _displayNameFor(m);
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
              merchant: displayName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: _ink)),
                Text('${tr('matyta')} ${m.count}x · ${tr('vidurkis')} ${m.avgAmount.toStringAsFixed(2)} €',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: _subtle)),
              ],
            ),
          ),
          // A bank's own description ("Apple Pay", "Grzn*Anthropic Pbc") is
          // what got matched — rename here to the merchant it's ACTUALLY
          // for before saving, so Prenumeratos shows "Claude", not the
          // payment rail. Edits _renamed, not `m` itself (const, and the
          // raw description stays what re-matching future syncs keys on).
          IconButton(
              onPressed: () => _renamePrompt(m),
              icon: Icon(Icons.edit_outlined, size: 19, color: _subtle),
              tooltip: tr('Pervadinti'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34)),
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
            label: Text(widget.wantType == 'subscription'
                ? tr('Pridėti prie prenumeratų')
                : tr('Pridėti prie sąskaitų')),
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
