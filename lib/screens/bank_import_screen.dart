import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_prefs.dart';
import '../content_theme.dart';
import '../expense_categories.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/banking_service.dart';
import '../services/notification_service.dart';
import '../widgets/subscription_avatar.dart';

/// Review screen after a bank connect: the detected recurring payments, each
/// with a checkbox, so the user confirms which to import as subscriptions.
class BankImportScreen extends StatefulWidget {
  const BankImportScreen({super.key, required this.candidates});

  final List<RecurringCandidate> candidates;

  @override
  State<BankImportScreen> createState() => _BankImportScreenState();
}

class _BankImportScreenState extends State<BankImportScreen> {
  late final List<bool> _selected =
      List<bool>.filled(widget.candidates.length, true);
  int _importedCount = 0;
  bool _done = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  int get _selectedCount => _selected.where((s) => s).length;

  Future<void> _import() async {
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final base = DateTime.now().microsecondsSinceEpoch;
    var count = 0;
    for (var i = 0; i < widget.candidates.length; i++) {
      if (!_selected[i]) continue;
      final id = '${base + i}';
      final sub = widget.candidates[i].toSubscription(id);
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
    if (widget.candidates.isEmpty) {
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            _isLt
                ? 'Radome ${widget.candidates.length} galimų pasikartojančių mokėjimų. Pažymėk, kuriuos pridėti į vaultą.'
                : 'We found ${widget.candidates.length} likely recurring payments. Choose which to add to your vault.',
            style: TextStyle(color: cSubtle, fontSize: 13, height: 1.4),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: widget.candidates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _candidateTile(i),
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  Widget _candidateTile(int i) {
    final c = widget.candidates[i];
    final l = AppLocalizations.of(context);
    final selected = _selected[i];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selected[i] = !selected),
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
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      '${categoryLabel(c.category, _isLt)} · ${billingCycleLabel(l, c.billingCycle)} · ${_isLt ? '${c.occurrences} kartai' : '${c.occurrences}×'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                c.amountVaries
                    ? '~${formatMoney(c.cost)}'
                    : formatMoney(c.cost),
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
                : (_isLt
                    ? 'Pridėti $_selectedCount'
                    : 'Add $_selectedCount'),
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
