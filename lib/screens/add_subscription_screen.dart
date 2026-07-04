import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app_prefs.dart';
import '../expense_categories.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/logo_service.dart';
import '../services/notification_service.dart';
import '../widgets/subscription_avatar.dart';
import '../widgets/subscription_icons.dart';

/// Form for creating — or editing — a recurring expense and saving it to Hive.
///
/// Category-first: the user picks a category (which sets a sensible default
/// cycle, colour and icon), optionally taps a name suggestion, then fills in the
/// amount and date. Advanced options (estimate flag, notes, colour) live behind
/// a collapsed "More options" section so the common path stays short.
///
/// Passing [existing] switches the form into edit mode.
class AddSubscriptionScreen extends StatefulWidget {
  const AddSubscriptionScreen({
    super.key,
    this.existing,
    this.initialBrand,
    this.initialCategory,
  });

  static const route = '/add';

  /// The expense being edited, or null when creating a new one.
  final Subscription? existing;

  /// Optional service to preselect on a fresh form (quick-add from empty state).
  final Brand? initialBrand;

  /// Optional category key to preselect on a fresh form (category quick-add).
  final String? initialCategory;

  @override
  State<AddSubscriptionScreen> createState() => _AddSubscriptionScreenState();
}

class _AddSubscriptionScreenState extends State<AddSubscriptionScreen>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  final _nameFocus = FocusNode();
  final _infoKey = GlobalKey();

  // Brief green flash on the Name field when a service/suggestion is picked.
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
  String _category = 'entertainment';
  DateTime _nextBilling = DateTime.now().add(const Duration(days: 30));
  Color _color = VaultieColors.primary;
  Brand? _brand;
  String? _logoDomain;
  bool _isEstimated = false;
  bool _showMore = false;

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
  bool get _isEntertainment => normalizeCategoryKey(_category) == 'entertainment';

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
      _isEstimated = e.isEstimated;
      _notes.text = e.notes ?? '';
      _logoDomain = e.logoDomain;
      _showMore = e.isEstimated || (e.notes?.isNotEmpty ?? false);
    }
    // Category quick-add from the empty state: preselect the category and its
    // sensible defaults on a fresh form.
    if (e == null && widget.initialCategory != null) {
      final cat = categoryFor(widget.initialCategory!);
      _category = cat.key;
      _cycle = cat.defaultCycle;
      _color = cat.color;
    }
    _name.addListener(_onNameChanged);
    // Quick-add: preselect a service passed in from the empty-state grid.
    if (e == null && widget.initialBrand != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectBrand(brandSpec(widget.initialBrand!));
      });
    }
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    _cost.dispose();
    _notes.dispose();
    _nameFocus.dispose();
    _flashController.dispose();
    super.dispose();
  }

  /// Picking a category applies its default cycle, colour and icon, and drops
  /// any brand selection (the expense is now generic unless a brand is chosen).
  void _selectCategory(ExpenseCategory cat) {
    setState(() {
      _category = cat.key;
      _brand = null;
      _logoDomain = null;
      // Only override the colour if the user hasn't hand-picked one that
      // differs from the previous category's default.
      _color = cat.color;
      if (!_isEditing) _cycle = cat.defaultCycle;
    });
  }

  /// Picking a known brand pre-fills its name, colour, logo and category.
  void _selectBrand(BrandSpec spec) {
    setState(() {
      _brand = spec.brand;
      _category = 'entertainment';
      if (spec.brand == Brand.other) {
        _name.clear();
        _color = VaultieColors.primary;
        _logoDomain = null;
      } else {
        _name.text = spec.label;
        _color = spec.background;
        _logoDomain = domainForName(spec.label);
      }
    });
    _drawAttentionToName(focus: spec.brand == Brand.other);
  }

  void _applySuggestion(String name) {
    setState(() => _name.text = name);
    _drawAttentionToName(focus: false);
  }

  /// Scrolls the details card into view and flashes the Name field.
  void _drawAttentionToName({required bool focus}) {
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
      if (focus) {
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
    final notes = _notes.text.trim();
    final sub = Subscription(
      id: id,
      name: name,
      cost: cost,
      billingCycle: _cycle,
      category: _category,
      nextBillingDate: _nextBilling,
      colorValue: _color.toARGB32(),
      isEstimated: _isEstimated,
      notes: notes.isEmpty ? null : notes,
      logoDomain: _logoDomain,
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
    final suggestions = categorySuggestions(_category, isLt);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: VaultieColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isEditing
            ? (isLt ? 'Redaguoti išlaidą' : 'Edit expense')
            : (isLt ? 'Pridėti išlaidą' : 'Add expense')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          // Dragging the form dismisses the (Done-less) numeric keyboard, so the
          // user can reach the fields and Save button below the amount.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _sectionLabel(isLt ? 'Kategorija' : 'Category'),
            const SizedBox(height: 12),
            _categoryGrid(isLt),
            const SizedBox(height: 24),
            // Suggestions: popular brands for Entertainment, name chips elsewhere.
            if (_isEntertainment) ...[
              _sectionLabel(l.popularServices),
              const SizedBox(height: 12),
              _brandGrid(isLt),
              const SizedBox(height: 24),
            ] else if (suggestions.isNotEmpty) ...[
              _sectionLabel(isLt ? 'Greitas pasirinkimas' : 'Quick pick'),
              const SizedBox(height: 12),
              _suggestionChips(suggestions),
              const SizedBox(height: 24),
            ],
            _sectionLabel(isLt ? 'Informacija' : 'Details'),
            const SizedBox(height: 8),
            _infoCard(l),
            const SizedBox(height: 24),
            _sectionLabel(l.billingCycle),
            const SizedBox(height: 12),
            _cycleGrid(l),
            const SizedBox(height: 20),
            _moreOptions(isLt),
            const SizedBox(height: 28),
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

  // ── Category grid ────────────────────────────────────────────────────────

  Widget _categoryGrid(bool isLt) {
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 8,
      childAspectRatio: 0.72,
      children: kExpenseCategories.map((cat) {
        final selected = cat.key == normalizeCategoryKey(_category);
        return GestureDetector(
          onTap: () => _selectCategory(cat),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: selected ? 1 : 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? cat.color : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Icon(
                  cat.icon,
                  color: selected ? Colors.white : cat.color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                cat.label(isLt),
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? VaultieColors.ink : VaultieColors.subtle,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Suggestion chips ─────────────────────────────────────────────────────

  Widget _suggestionChips(List<String> suggestions) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: suggestions.map((s) {
        final selected = _name.text.trim() == s;
        return GestureDetector(
          onTap: () => _applySuggestion(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? VaultieColors.primary
                  : VaultieColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: selected ? VaultieColors.primary : VaultieColors.line,
              ),
            ),
            child: Text(
              s,
              style: TextStyle(
                color: selected ? Colors.white : VaultieColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Popular services grid (Entertainment) ────────────────────────────────

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
            spec.brand == Brand.other ? (isLt ? 'Kita' : 'Other') : spec.label;
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

  // ── Details card ─────────────────────────────────────────────────────────

  Widget _infoCard(AppLocalizations l) {
    final isLt = _isLt;
    // Name placeholder is category-aware: e.g. "pvz. Nuoma" for Housing,
    // falling back to the brand-style hint for Entertainment/Other.
    final example = categoryHintExample(_category, isLt);
    final nameHint = example == null
        ? l.nameHint
        : (isLt ? 'pvz. $example' : 'e.g. $example');
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
                ? Icon(categoryFor(_category).icon,
                    color: categoryFor(_category).color, size: 24)
                : SubscriptionAvatar(
                    name: _name.text,
                    category: _category,
                    logoDomain: _logoDomain,
                    size: 30,
                  ),
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
                textInputAction: TextInputAction.done,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: nameHint,
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
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: _isEstimated ? '~ 0.00' : '0.00',
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
        ],
      ),
    );
  }

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
    const cycles = BillingCycle.values;
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
                    selected ? VaultieColors.primary : VaultieColors.line,
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

  // ── More options (estimate, notes, colour) ───────────────────────────────

  Widget _moreOptions(bool isLt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showMore = !_showMore),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(
                  (isLt ? 'Daugiau parinkčių' : 'More options').toUpperCase(),
                  style: const TextStyle(
                    color: VaultieColors.subtle,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showMore ? Icons.expand_less : Icons.expand_more,
                  color: VaultieColors.subtle,
                ),
              ],
            ),
          ),
        ),
        if (_showMore) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: VaultieColors.card,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: VaultieColors.brightGreen,
                  title: Text(isLt ? 'Kintanti suma' : 'Variable amount'),
                  subtitle: Text(
                    isLt
                        ? 'Rodyti kaip apytikslę (pvz. „~€60")'
                        : 'Show the amount as an estimate ("~€60")',
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: _isEstimated,
                  onChanged: (v) => setState(() => _isEstimated = v),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: TextField(
                    controller: _notes,
                    minLines: 1,
                    maxLines: 3,
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: isLt ? 'Pastabos (nebūtina)' : 'Notes (optional)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel(l10nColour(isLt)),
          const SizedBox(height: 12),
          _colorDots(),
        ],
      ],
    );
  }

  String l10nColour(bool isLt) => isLt ? 'Spalva' : 'Colour';

  Widget _colorDots() {
    // The current category colour first, then the fixed swatches.
    final catColor = categoryFor(_category).color;
    final swatches = <Color>[
      catColor,
      ..._swatches.where((c) => c.toARGB32() != catColor.toARGB32()),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 12,
      children: swatches.map((c) {
        final selected = c.toARGB32() == _color.toARGB32();
        return GestureDetector(
          onTap: () => setState(() => _color = c),
          child: Container(
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
