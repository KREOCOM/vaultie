import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_prefs.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/notification_service.dart';
import '../widgets/subscription_icons.dart';

/// Form for creating — or editing — a subscription and saving it to Hive.
///
/// Passing [existing] switches the form into edit mode: fields are prefilled
/// and saving overwrites that record (same id) instead of creating a new one.
class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({super.key, this.existing});

  static const route = '/add';

  /// The subscription being edited, or null when creating a new one.
  final Subscription? existing;

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cost = TextEditingController();

  BillingCycle _cycle = BillingCycle.monthly;
  String _category = SubscriptionCategory.all.first;
  DateTime _nextBilling = DateTime.now().add(const Duration(days: 30));
  Color _color = VaultieColors.primary;
  Brand? _brand;

  /// Picking a known service pre-fills its name, colour and category.
  /// "Other" just clears the form back to a blank custom entry.
  void _selectBrand(BrandSpec spec) {
    setState(() {
      _brand = spec.brand;
      if (spec.brand == Brand.other) {
        _name.clear();
        _color = VaultieColors.primary;
        _category = SubscriptionCategory.all.first;
      } else {
        _name.text = spec.label;
        _color = spec.background;
        _category = spec.category;
      }
    });
    FocusScope.of(context).unfocus();
  }

  static const _swatches = [
    Color(0xFF174E35),
    Color(0xFF2E6B4D),
    Color(0xFFD9534F),
    Color(0xFFE9A23B),
    Color(0xFF4A6FA5),
    Color(0xFF8E5BA6),
  ];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Prefill every field from the record being edited.
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _cost.text = e.cost.toString();
      _cycle = e.billingCycle;
      _category = e.category;
      _nextBilling = e.nextBillingDate;
      _color = Color(e.colorValue);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextBilling,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _nextBilling = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    // Reuse the id when editing (overwrites in place); otherwise mint a new,
    // unique-enough one without pulling in a uuid dependency.
    final id =
        widget.existing?.id ?? '${DateTime.now().microsecondsSinceEpoch}';
    final sub = Subscription(
      id: id,
      name: _name.text.trim(),
      cost: double.parse(_cost.text.trim()),
      billingCycle: _cycle,
      category: _category,
      nextBillingDate: _nextBilling,
      colorValue: _color.toARGB32(),
    );
    box.put(id, sub);
    // Schedule the 3/2/1-day renewal reminders in the device language.
    final isLithuanian = Localizations.localeOf(context).languageCode == 'lt';
    NotificationService.instance
        .scheduleForSubscription(sub, isLithuanian: isLithuanian);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLithuanian = Localizations.localeOf(context).languageCode == 'lt';
    final dateLabel =
        '${_nextBilling.year}-${_nextBilling.month.toString().padLeft(2, '0')}-${_nextBilling.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? (isLithuanian ? 'Redaguoti prenumeratą' : 'Edit subscription')
            : l.addSubscriptionTitle),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _Label(l.popularServices),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 8,
                childAspectRatio: 0.74,
                children: kPopularGrid.map((brand) {
                  final spec = brandSpec(brand);
                  final selected = brand == _brand;
                  // Brand names stay in English; only the generic "Other"
                  // tile is localized.
                  final label = spec.brand == Brand.other
                      ? (isLithuanian ? 'Kitos' : 'Other')
                      : spec.label;
                  return GestureDetector(
                    onTap: () => _selectBrand(spec),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? VaultieColors.primary
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: BrandLogo(brand: brand, size: 54),
                        ),
                        const SizedBox(height: 6),
                        // Constrained to the icon width so long names ellipsize
                        // instead of overflowing the cell.
                        SizedBox(
                          width: 60,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? VaultieColors.primary
                                  : VaultieColors.subtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l.name,
                  hintText: l.nameHint,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l.nameError : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: l.cost,
                  prefixText: '${AppPrefs.currency.value} ',
                ),
                validator: (v) {
                  final parsed = double.tryParse(v?.trim() ?? '');
                  if (parsed == null || parsed <= 0) return l.costError;
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _Label(l.billingCycle),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: BillingCycle.values.map((c) {
                  final selected = c == _cycle;
                  return ChoiceChip(
                    label: Text(billingCycleLabel(l, c)),
                    selected: selected,
                    onSelected: (_) => setState(() => _cycle = c),
                    selectedColor: VaultieColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : VaultieColors.ink,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              _Label(l.category),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: SubscriptionCategory.all
                    .map((c) => DropdownMenuItem(
                        value: c, child: Text(categoryLabel(l, c))))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 20),
              _Label(l.nextBillingDate),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(16),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(dateLabel),
                ),
              ),
              const SizedBox(height: 20),
              _Label(l.colour),
              const SizedBox(height: 8),
              Row(
                children: _swatches.map((c) {
                  final selected = c.toARGB32() == _color.toARGB32();
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              selected ? VaultieColors.ink : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _save,
                child: Text(_isEditing
                    ? (isLithuanian ? 'Išsaugoti pakeitimus' : 'Save changes')
                    : l.saveToVault),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        color: VaultieColors.ink,
      ),
    );
  }
}
