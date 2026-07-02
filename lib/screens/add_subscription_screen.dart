import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_prefs.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/notification_service.dart';
import '../widgets/subscription_avatar.dart';
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

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _nameFocus = FocusNode();
  final _infoKey = GlobalKey();

  // Brief green flash on the Name field when a service is picked (0→1→0).
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _flash = TweenSequence<double>([
    TweenSequenceItem(
      tween:
          Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween:
          Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 75,
    ),
  ]).animate(_flashController);

  BillingCycle _cycle = BillingCycle.monthly;
  String _category = SubscriptionCategory.all.first;
  DateTime _nextBilling = DateTime.now().add(const Duration(days: 30));
  Color _color = VaultieColors.primary;
  Brand? _brand;

  static const _swatches = [
    Color(0xFF174E35),
    Color(0xFF2E6B4D),
    Color(0xFFD9534F),
    Color(0xFFE9A23B),
    Color(0xFF4A6FA5),
    Color(0xFF8E5BA6),
  ];

  bool get _isEditing => widget.existing != null;
  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _cost.text = e.cost.toString();
      _cycle = e.billingCycle;
      _category = e.category;
      _nextBilling = e.nextBillingDate;
      _color = Color(e.colorValue);
    }
    // Live logo preview: rebuild as the name changes so the avatar updates.
    _name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _cost.dispose();
    _nameFocus.dispose();
    _flashController.dispose();
    super.dispose();
  }

  /// Picking a known service pre-fills its name, colour and category.
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

    // Draw attention to the Information section: scroll it into view and flash
    // the Name field. "Other" also focuses the field so the keyboard opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _infoKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
      _flashController.forward(from: 0);
      if (spec.brand == Brand.other) {
        _nameFocus.requestFocus();
      } else {
        FocusScope.of(context).unfocus();
      }
    });
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextBilling,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _nextBilling = picked);
  }

  Future<void> _pickCategory() async {
    FocusScope.of(context).unfocus();
    final l = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in SubscriptionCategory.all)
              ListTile(
                title: Text(categoryLabel(l, c)),
                trailing: c == _category
                    ? const Icon(Icons.check, color: VaultieColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(c),
              ),
          ],
        ),
      ),
    );
    if (choice != null) setState(() => _category = choice);
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final name = _name.text.trim();
    final cost = double.tryParse(_cost.text.trim().replaceAll(',', '.'));
    if (name.isEmpty) {
      _snack(l.nameError);
      return;
    }
    if (cost == null || cost <= 0) {
      _snack(l.costError);
      return;
    }

    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final id =
        widget.existing?.id ?? '${DateTime.now().microsecondsSinceEpoch}';
    final sub = Subscription(
      id: id,
      name: name,
      cost: cost,
      billingCycle: _cycle,
      category: _category,
      nextBillingDate: _nextBilling,
      colorValue: _color.toARGB32(),
    );
    box.put(id, sub);
    NotificationService.instance
        .scheduleForSubscription(sub, isLithuanian: _isLt);
    Navigator.of(context).pop();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = _isLt;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: VaultieColors.primary, // #174E35
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isEditing
            ? (isLt ? 'Redaguoti prenumeratą' : 'Edit subscription')
            : l.addSubscriptionTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel(l.popularServices),
            const SizedBox(height: 12),
            _brandGrid(isLt),
            const SizedBox(height: 24),
            _sectionLabel(isLt ? 'Informacija' : 'Information'),
            const SizedBox(height: 8),
            _infoCard(l),
            const SizedBox(height: 24),
            _sectionLabel(l.billingCycle),
            const SizedBox(height: 12),
            _cycleGrid(l),
            const SizedBox(height: 24),
            _sectionLabel(l.colour),
            const SizedBox(height: 12),
            _colorDots(),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _save,
              child: Text(_isEditing
                  ? (isLt ? 'Išsaugoti pakeitimus' : 'Save changes')
                  : l.saveToVault),
            ),
          ],
        ),
      ),
    );
  }

  // ── Popular services grid ────────────────────────────────────────────────

  Widget _brandGrid(bool isLt) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 10,
      childAspectRatio: 0.78,
      children: kPopularGrid.map((brand) {
        final spec = brandSpec(brand);
        final selected = brand == _brand;
        final label =
            spec.brand == Brand.other ? (isLt ? 'Kitos' : 'Other') : spec.label;
        return GestureDetector(
          onTap: () => _selectBrand(spec),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        selected ? VaultieColors.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: BrandLogo(brand: brand, size: 52),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        selected ? VaultieColors.primary : VaultieColors.subtle,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Information card ─────────────────────────────────────────────────────

  Widget _infoCard(AppLocalizations l) {
    final dateLabel = '${_nextBilling.year}-'
        '${_nextBilling.month.toString().padLeft(2, '0')}-'
        '${_nextBilling.day.toString().padLeft(2, '0')}';
    return Container(
      key: _infoKey,
      decoration: BoxDecoration(
        color: VaultieColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _fieldRow(
            emoji: '📝',
            label: l.name,
            leading: _name.text.trim().isEmpty
                ? const Text('📝', style: TextStyle(fontSize: 20))
                : SubscriptionAvatar(name: _name.text, size: 30),
            child: AnimatedBuilder(
              animation: _flash,
              builder: (context, child) {
                final v = _flash.value.clamp(0.0, 1.0).toDouble();
                return Container(
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: VaultieColors.primary.withValues(alpha: v),
                      width: 2,
                    ),
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: VaultieColors.primary.withValues(alpha: v * 0.10),
                  ),
                  child: child,
                );
              },
              child: TextField(
                controller: _name,
                focusNode: _nameFocus,
                textAlign: TextAlign.right,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: l.nameHint,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          _fieldRow(
            emoji: '💶',
            label: l.cost,
            child: TextField(
              controller: _cost,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '0.00',
                prefixText: '${AppPrefs.currency.value} ',
              ),
            ),
          ),
          const Divider(height: 1),
          _tapRow(
            emoji: '📅',
            label: l.nextBillingDate,
            value: dateLabel,
            onTap: _pickDate,
          ),
          const Divider(height: 1),
          _tapRow(
            emoji: '🗂️',
            label: l.category,
            value: categoryLabel(l, _category),
            onTap: _pickCategory,
          ),
        ],
      ),
    );
  }

  /// A row with an editable [child] (text field).
  Widget _fieldRow({
    required String emoji,
    required String label,
    required Widget child,
    Widget? leading,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          leading ?? Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 14),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: VaultieColors.ink)),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// A tappable row showing a static [value] and a chevron.
  Widget _tapRow({
    required String emoji,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: VaultieColors.ink)),
            const Spacer(),
            Text(value, style: const TextStyle(color: VaultieColors.subtle)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: VaultieColors.subtle),
          ],
        ),
      ),
    );
  }

  // ── Billing cycle 2×2 grid ───────────────────────────────────────────────

  Widget _cycleGrid(AppLocalizations l) {
    const cycles = BillingCycle.values; // weekly, monthly, quarterly, yearly
    Widget button(BillingCycle c) {
      final selected = c == _cycle;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _cycle = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? VaultieColors.primary : VaultieColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    selected ? VaultieColors.primary : const Color(0xFFE1E8E3),
              ),
            ),
            child: Text(
              billingCycleLabel(l, c),
              style: TextStyle(
                color: selected ? Colors.white : VaultieColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [
          button(cycles[0]),
          const SizedBox(width: 12),
          button(cycles[1]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          button(cycles[2]),
          const SizedBox(width: 12),
          button(cycles[3]),
        ]),
      ],
    );
  }

  // ── Colour dots ──────────────────────────────────────────────────────────

  Widget _colorDots() {
    return Row(
      children: _swatches.map((c) {
        final selected = c.toARGB32() == _color.toARGB32();
        return GestureDetector(
          onTap: () => setState(() => _color = c),
          child: Container(
            margin: const EdgeInsets.only(right: 14),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? VaultieColors.ink : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: VaultieColors.subtle,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      );
}
