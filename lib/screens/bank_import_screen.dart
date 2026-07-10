import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_prefs.dart';
import '../content_theme.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/banking_service.dart';
import '../services/notification_service.dart';
import '../services/recurring_classifier.dart';
import '../widgets/subscription_avatar.dart';

/// Amber used to flag candidates that deserve a second look.
const Color _caution = Color(0xFFE9A23B);

/// Review screen after a bank connect: detected recurring payments grouped by
/// type (Subscriptions / Bills), each with a checkbox, plus a read-only
/// "frequent spending" section (never recurring). Duplicates of payments
/// already in the vault are pre-unchecked; everything else is pre-checked.
class BankImportScreen extends StatefulWidget {
  const BankImportScreen({super.key, required this.result});

  final BankScanResult result;

  @override
  State<BankImportScreen> createState() => _BankImportScreenState();
}

/// One candidate paired with its classifier verdict, kept in original order so
/// [_selected] can stay indexed by the candidate's position.
class _Item {
  _Item(this.index, this.candidate, this.cls);
  final int index;
  final RecurringCandidate candidate;
  final RecurringClassification cls;
}

class _BankImportScreenState extends State<BankImportScreen> {
  late final List<_Item> _items;
  late final List<bool> _selected;
  int _importedCount = 0;
  bool _done = false;

  List<RecurringCandidate> get _candidates => widget.result.candidates;
  List<FrequentMerchant> get _frequent => widget.result.frequent;

  @override
  void initState() {
    super.initState();
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final existing = box.values
        .map((s) => RecurringClassifier.normalizeName(s.name))
        .toSet();
    _items = [
      for (var i = 0; i < _candidates.length; i++)
        _Item(
          i,
          _candidates[i],
          RecurringClassifier.classify(
            _candidates[i],
            existingNormalizedNames: existing,
          ),
        ),
    ];
    _selected = [for (final it in _items) it.cls.selectedByDefault];
  }

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  int get _selectedCount => _selected.where((s) => s).length;

  List<_Item> _groupItems(ImportGroup g) =>
      _items.where((it) => it.cls.group == g).toList();

  Future<void> _import() async {
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final base = DateTime.now().microsecondsSinceEpoch;
    var count = 0;
    for (final it in _items) {
      if (!_selected[it.index]) continue;
      final id = '${base + it.index}';
      final sub = it.candidate.toSubscription(id);
      await box.put(id, sub);
      await NotificationService.instance
          .scheduleForSubscription(sub, isLithuanian: _isLt);
      count++;
    }
    if (!mounted) return;
    setState(() {
      _importedCount = count;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: contentTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: cBg,
        appBar: AppBar(
          automaticallyImplyLeading: !_done,
          title: Text(_isLt ? 'Rasti mokėjimai' : 'Found payments'),
        ),
        body: SafeArea(child: _done ? _doneView() : _reviewView()),
      ),
    );
  }

  Widget _reviewView() {
    if (_items.isEmpty && _frequent.isEmpty) {
      return _emptyState();
    }

    final groups = kImportGroupOrder
        .where((g) => _groupItems(g).isNotEmpty)
        .toList(growable: false);

    return Column(
      children: [
        if (_items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              _isLt
                  ? 'Radome ${_items.length} pasikartojančių mokėjimų. Pažymėk, kuriuos pridėti į vaultą.'
                  : 'We found ${_items.length} recurring payments. Choose which to add to your vault.',
              style: TextStyle(color: cSubtle, fontSize: 13, height: 1.4),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              for (final g in groups) ..._section(g),
              if (_frequent.isNotEmpty) ..._frequentSection(),
            ],
          ),
        ),
        if (_items.isNotEmpty) _bottomBar(),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: cSubtle, size: 40),
            const SizedBox(height: 16),
            Text(
              _isLt
                  ? 'Neradome aiškių pasikartojančių mokėjimų šioje sąskaitoje.'
                  : 'We didn\'t find any clear recurring payments in this account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cInk, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_isLt ? 'Grįžti' : 'Back'),
            ),
          ],
        ),
      ),
    );
  }

  /// A group header (with a select-all toggle) followed by its candidate tiles.
  List<Widget> _section(ImportGroup g) {
    final items = _groupItems(g);
    final selectedInGroup = items.where((it) => _selected[it.index]).length;
    final allSelected = selectedInGroup == items.length;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    importGroupLabel(g, _isLt),
                    style: TextStyle(
                        color: cInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                  const SizedBox(width: 8),
                  Text('$selectedInGroup/${items.length}',
                      style: TextStyle(color: cSubtle, fontSize: 13)),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                final target = !allSelected;
                for (final it in items) {
                  _selected[it.index] = target;
                }
              }),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                allSelected
                    ? (_isLt ? 'Nė vieno' : 'None')
                    : (_isLt ? 'Visus' : 'All'),
                style: TextStyle(
                    color: cAccent, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
      for (final it in items) ...[
        _candidateTile(it),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
    ];
  }

  Widget _candidateTile(_Item it) {
    final c = it.candidate;
    final cls = it.cls;
    final l = AppLocalizations.of(context);
    final selected = _selected[it.index];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selected[it.index] = !selected),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? cAccent : cLine),
          ),
          child: Row(
            children: [
              SubscriptionAvatar(
                name: c.name,
                category: c.category,
                logoDomain: c.logoDomain,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cInk,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ),
                        if (cls.isDuplicate) ...[
                          const SizedBox(width: 8),
                          _pill(_isLt ? 'Jau seki' : 'Already tracked', cSubtle),
                        ] else if (cls.needsReview) ...[
                          const SizedBox(width: 8),
                          _pill(_isLt ? 'Patikrink' : 'Check', _caution),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${billingCycleLabel(l, c.billingCycle)} · ${_isLt ? 'matyta ${c.occurrences}×' : 'seen ${c.occurrences}×'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                c.amountVaries ? '~${formatMoney(c.cost)}' : formatMoney(c.cost),
                style: TextStyle(
                    color: cInk, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(width: 10),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color: selected ? cAccent : cSubtle,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Read-only "frequent spending" section — merchants we see often but never
  /// treat as recurring (fast food, groceries…).
  List<Widget> _frequentSection() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
        child: Text(
          _isLt ? 'Dažni pirkimai' : 'Frequent spending',
          style:
              TextStyle(color: cInk, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
        child: Text(
          _isLt
              ? 'Šie nesekami kaip pasikartojantys — tik informacijai.'
              : 'These aren\'t tracked as recurring — shown for context only.',
          style: TextStyle(color: cSubtle, fontSize: 12, height: 1.4),
        ),
      ),
      for (final f in _frequent) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
          ),
          child: Row(
            children: [
              SubscriptionAvatar(
                  name: f.name,
                  category: f.category,
                  logoDomain: f.logoDomain,
                  size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: cInk,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              Text(
                _isLt
                    ? '${f.occurrences}× · ${formatMoney(f.totalSpent)}'
                    : '${f.occurrences}× · ${formatMoney(f.totalSpent)}',
                style: TextStyle(color: cSubtle, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  /// A small rounded status label (e.g. "Already tracked", "Check").
  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 10)),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: cCard,
        border: Border(top: BorderSide(color: cLine)),
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton(
          onPressed: _selectedCount == 0 ? null : _import,
          child: Text(
            _selectedCount == 0
                ? (_isLt ? 'Pažymėk bent vieną' : 'Select at least one')
                : (_isLt ? 'Pridėti $_selectedCount' : 'Add $_selectedCount'),
          ),
        ),
      ),
    );
  }

  Widget _doneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: cAccent, size: 56),
            const SizedBox(height: 20),
            Text(
              _isLt
                  ? 'Pridėta $_importedCount ${_importedCount == 1 ? 'mokėjimas' : 'mokėjimų'}!'
                  : 'Added $_importedCount ${_importedCount == 1 ? 'payment' : 'payments'}!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: cInk, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _isLt
                  ? 'Juos rasi savo vaulte kartu su priminimais.'
                  : 'They\'re in your vault now, with reminders set.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cSubtle, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_isLt ? 'Baigta' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }
}
