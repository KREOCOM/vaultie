import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_prefs.dart';
import '../expense_categories.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';
import '../services/recap_service.dart';
import '../widgets/budget_dialog.dart';
import '../widgets/subscription_avatar.dart';
import '../widgets/subscription_icons.dart';
import 'add_subscription_screen.dart';
import 'paywall_screen.dart';
import 'recap_screen.dart';
import 'settings_screen.dart';

const Color _brightGreen = Color(0xFF4CAF72);

// ── Black (graphite) theme (dashboard) ──────────────────────────────────────
const Color _dBg = Color(0xFF111316); // graphite page background
const Color _dCard = Color(0xFF1C2024); // charcoal card / chip surface
const Color _dInk = Color(0xFFF1F3F4); // primary text / icons
const Color _dSubtle = Color(0xFF9AA0A6); // secondary text
const Color _dLine = Color(0xFF2A2F35); // borders / dividers / progress tracks
const Color _dHiBg = Color(0xFF241F12); // highlight / warning card background
const Color _dHiBorder = Color(0xFF6B5424); // highlight / warning card border

/// Home screen: two tabs — Overview (Apžvalga) and Analytics (Analitika).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  static const route = '/dashboard';

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // Three tabs: Overview, Analytics, Settings. Listened to so the FAB can hide
  // on the Settings tab.
  late final TabController _tab = TabController(length: 3, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    // After the first frame, surface the once-a-month recap if one is due.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowRecap());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _maybeShowRecap() {
    if (!mounted) return;
    final recap = RecapService.pendingRecap();
    if (recap == null) return;
    RecapService.markShown();
    showMonthlyRecap(context, recap);
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';

    final base = Theme.of(context);
    // One dark override for the whole dashboard subtree so every default-
    // coloured Text/icon/input flips to light — no per-widget hunting.
    final darkTheme = base.copyWith(
      scaffoldBackgroundColor: _dBg,
      // Material Card widgets (upcoming-payments card, each subscription row)
      // read their colour from here — without this they'd stay white on black.
      cardTheme: base.cardTheme.copyWith(color: _dCard),
      textTheme: base.textTheme.apply(bodyColor: _dInk, displayColor: _dInk),
      iconTheme: const IconThemeData(color: _dInk),
      popupMenuTheme: base.popupMenuTheme.copyWith(color: _dCard),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: _dCard,
        hintStyle: const TextStyle(color: _dSubtle),
        prefixIconColor: _dSubtle,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _dLine),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _dLine),
        ),
      ),
    );
    return Theme(
      data: darkTheme,
      child: Scaffold(
        backgroundColor: _dBg,
        // No add button on the Settings tab.
        floatingActionButton: _tab.index == 2
            ? null
            : FloatingActionButton.extended(
                backgroundColor: VaultieColors.primary,
                foregroundColor: Colors.white,
                onPressed: () => _onAddPressed(context, box),
                icon: const Icon(Icons.add),
                label: Text(AppLocalizations.of(context).addButton),
              ),
        body: SafeArea(
          child: Column(
            children: [
              TabBar(
                controller: _tab,
                labelColor: _brightGreen,
                unselectedLabelColor: _dSubtle,
                indicatorColor: _brightGreen,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                tabs: [
                  Tab(text: isLt ? 'Apžvalga' : 'Overview'),
                  Tab(text: isLt ? 'Analitika' : 'Analytics'),
                  Tab(text: isLt ? 'Nustatymai' : 'Settings'),
                ],
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: box.listenable(),
                  builder: (context, Box<Subscription> b, _) {
                    final subs = b.values.toList()
                      ..sort((a, c) =>
                          a.daysUntilRenewal.compareTo(c.daysUntilRenewal));
                    return TabBarView(
                      controller: _tab,
                      children: [
                        _OverviewTab(subs: subs),
                        _AnalyticsTab(subs: subs),
                        const SettingsScreen(embedded: true),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the add form — unless a free user is at the subscription limit, in
  /// which case the paywall is shown first. If they unlock premium there, the
  /// add form opens right after so the tap isn't wasted.
  Future<void> _onAddPressed(
      BuildContext context, Box<Subscription> box) async {
    final atLimit = box.length >= kFreeSubscriptionLimit &&
        !PurchaseService.instance.isPremium;
    if (atLimit) {
      final unlocked = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const PaywallScreen(reachedFreeLimit: true),
        ),
      );
      if (unlocked != true || !context.mounted) return;
    }
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddSubscriptionScreen()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview tab
// ─────────────────────────────────────────────────────────────────────────────

enum _SortMode { renewal, priceHigh, nameAsc }

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.subs});

  final List<Subscription> subs;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _SortMode _sort = _SortMode.renewal;

  /// Selected category filter (normalized key), or null for "All".
  String? _categoryFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// The list to render: filtered by category and search query, then sorted.
  List<Subscription> _visible() {
    final q = _query.trim().toLowerCase();
    final list = widget.subs
        .where((s) =>
            _categoryFilter == null ||
            normalizeCategoryKey(s.category) == _categoryFilter)
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
        .toList();
    switch (_sort) {
      case _SortMode.renewal:
        list.sort((a, b) => a.daysUntilRenewal.compareTo(b.daysUntilRenewal));
      case _SortMode.priceHigh:
        list.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
      case _SortMode.nameAsc:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final subs = widget.subs;
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final monthlyTotal = subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);

    final visible = _visible();

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _VerifyEmailBanner()),
        const SliverToBoxAdapter(child: _NotificationBanner()),
        SliverToBoxAdapter(child: _OverviewHeader(subs: subs)),
        if (subs.isNotEmpty)
          SliverToBoxAdapter(
            // Reactive so setting/clearing the budget updates immediately.
            child: ValueListenableBuilder<double?>(
              valueListenable: AppPrefs.budget,
              builder: (context, budget, _) => budget != null
                  ? _BudgetCard(spent: monthlyTotal, budget: budget)
                  : const _SetBudgetPrompt(),
            ),
          ),
        if (subs.isEmpty)
          const SliverToBoxAdapter(child: _EmptyState())
        else ...[
          SliverToBoxAdapter(child: _UpcomingRenewals(subs: subs)),
          SliverToBoxAdapter(child: _categoryChips(subs, isLt)),
          if (subs.length >= 2) SliverToBoxAdapter(child: _searchSortBar(isLt)),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    isLt ? 'Nieko nerasta' : 'No matches',
                    style: const TextStyle(color: _dSubtle),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _SubscriptionTile(sub: visible[i]),
              ),
            ),
        ],
      ],
    );
  }

  /// Horizontal category filter chips. Shown only when the user tracks expenses
  /// in more than one category, so a single-category user isn't given a
  /// pointless filter. Chips appear in the canonical taxonomy order.
  Widget _categoryChips(List<Subscription> subs, bool isLt) {
    final present = <String>{
      for (final s in subs) normalizeCategoryKey(s.category)
    };
    if (present.length < 2) return const SizedBox.shrink();
    final ordered = [
      for (final c in kExpenseCategories)
        if (present.contains(c.key)) c.key,
    ];

    Widget chip(
        {required String? key,
        required String label,
        IconData? icon,
        Color? color}) {
      final selected = _categoryFilter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _categoryFilter = key),
          child: Container(
            padding: EdgeInsets.only(
                left: icon == null ? 14 : 10, right: 14, top: 8, bottom: 8),
            decoration: BoxDecoration(
              color: selected ? VaultieColors.primary : _dCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? VaultieColors.primary : _dLine,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: selected ? Colors.white : (color ?? _brightGreen)),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : _dInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        children: [
          chip(key: null, label: isLt ? 'Visi' : 'All'),
          for (final key in ordered)
            chip(
              key: key,
              label: categoryLabel(key, isLt),
              icon: categoryFor(key).icon,
              color: categoryFor(key).color,
            ),
        ],
      ),
    );
  }

  Widget _searchSortBar(bool isLt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: isLt ? 'Ieškoti' : 'Search',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: _dCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _dLine),
            ),
            child: PopupMenuButton<_SortMode>(
              icon: const Icon(Icons.sort, color: _dInk),
              tooltip: isLt ? 'Rūšiuoti' : 'Sort',
              onSelected: (m) => setState(() => _sort = m),
              itemBuilder: (_) => [
                _sortItem(
                    _SortMode.renewal, isLt ? 'Pagal datą' : 'By renewal'),
                _sortItem(
                    _SortMode.priceHigh, isLt ? 'Pagal kainą' : 'By price'),
                _sortItem(
                    _SortMode.nameAsc, isLt ? 'Pagal pavadinimą' : 'By name'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(_SortMode mode, String label) {
    return PopupMenuItem<_SortMode>(
      value: mode,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: _sort == mode
                ? const Icon(Icons.check, size: 18, color: _brightGreen)
                : null,
          ),
          Text(label),
        ],
      ),
    );
  }
}

/// Mint-gradient header: greeting + name, monthly spend, count, optional badge.
/// Dark-green overview header: greeting + monthly spend on the left, a category
/// ring on the right, and a colour-dot legend below.
class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.subs});

  final List<Subscription> subs;

  // "Featured" dark card — a subtle dark-green gradient, a hair lighter/greener
  // than the page, so the hero stands out on the graphite theme without being a
  // bright block. Green label, light text, colourful ring.
  static const _bgTop = Color(0xFF1E2A22);
  static const _bgBottom = Color(0xFF151C17);
  static const _border = Color(0xFF2C3A31);
  static const _name = Color(0xFFF1F3F4); // headings + amount
  static const _muted = Color(0xFF9AA0A6); // greeting + count
  static const _accent = Color(0xFF4CAF72); // label + icon buttons
  static const _legend = Color(0xFFB4C0B8); // legend text

  String _userName(bool isLt) {
    final u = AuthService().currentUser;
    final display = u?.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final email = u?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return isLt ? 'Naudotojau' : 'there';
  }

  String _greeting(bool isLt) {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return isLt ? 'Labas rytas' : 'Good morning';
    if (h >= 12 && h < 18) return isLt ? 'Laba diena' : 'Good afternoon';
    return isLt ? 'Labas vakaras' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final name = _userName(isLt);
    final monthlyTotal = subs.fold<double>(0, (s, e) => s + e.monthlyCost);

    // Category breakdown for the ring + legend (legacy keys normalized).
    final byCategory = <String, double>{};
    for (final s in subs) {
      byCategory.update(
        normalizeCategoryKey(s.category),
        (v) => v + s.monthlyCost,
        ifAbsent: () => s.monthlyCost,
      );
    }
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (a, e) => a + e.value);
    final hasBreakdown = total > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_bgTop, _bgBottom],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Greeting + settings/logout.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(isLt),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _name,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Amount on the left, category ring on the right.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.monthlySpend.toUpperCase(),
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatMoney(monthlyTotal),
                        style: const TextStyle(
                          color: _name,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.activeSubscriptions(subs.length),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasBreakdown) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CustomPaint(
                      painter: _DonutPainter(
                        values: [for (final e in entries) e.value],
                        colors: [
                          for (final e in entries) categoryFor(e.key).color
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // Legend: category dot + percentage.
            if (hasBreakdown) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final e in entries)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: categoryFor(e.key).color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${categoryLabel(e.key, isLt)}  ${(e.value / total * 100).round()}%',
                          style: const TextStyle(
                            color: _legend,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Artimiausi mokėjimai" — next three renewals with a colour dot and a
/// days-remaining badge (red < 7 days, orange < 14, green otherwise).
class _UpcomingRenewals extends StatelessWidget {
  const _UpcomingRenewals({required this.subs});

  final List<Subscription> subs;

  Color _badgeColor(int days) {
    if (days < 7) return VaultieColors.danger; // red
    if (days < 14) return const Color(0xFFE9A23B); // orange
    return _brightGreen; // green
  }

  String _daysText(int days, bool isLt) {
    if (days < 0) return isLt ? 'Vėluoja' : 'Overdue';
    if (days == 0) return isLt ? 'Šiandien' : 'Today';
    if (days == 1) return isLt ? '1 d.' : '1 day';
    return isLt ? '$days d.' : '$days days';
  }

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    // Soonest-due first, so "Upcoming" actually shows the next payments.
    final upcoming = ([...subs]
          ..sort((a, b) => a.daysUntilRenewal.compareTo(b.daysUntilRenewal)))
        .take(3)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLt ? 'Artimiausi mokėjimai' : 'Upcoming payments',
                style: const TextStyle(
                  color: _dInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < upcoming.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _renewalRow(upcoming[i], isLt),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _renewalRow(Subscription sub, bool isLt) {
    final days = sub.daysUntilRenewal;
    final color = _badgeColor(days);
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: categoryFor(sub.category).color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            sub.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _dInk,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _daysText(days, isLt),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analytics tab
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsTab extends StatefulWidget {
  const _AnalyticsTab({required this.subs});

  final List<Subscription> subs;

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final subs = widget.subs;

    if (subs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l.analyticsEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _dSubtle),
          ),
        ),
      );
    }

    final monthly = subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);
    final yearly = monthly * 12;
    final daily = yearly / 365;

    final byCategory = <String, double>{};
    for (final s in subs) {
      // Normalise so legacy category strings collapse into the same key the
      // Overview header uses; otherwise the two tabs disagree on the breakdown.
      byCategory.update(
          normalizeCategoryKey(s.category), (v) => v + s.monthlyCost,
          ifAbsent: () => s.monthlyCost);
    }
    final entries = byCategory.entries.toList()
      ..sort((a, c) => c.value.compareTo(a.value));

    // Top expenses by normalized monthly cost.
    final top = ([...subs]
          ..sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost)))
        .take(5)
        .toList();

    // Biggest single charge still due within the current calendar month.
    final now = DateTime.now();
    final dueThisMonth = subs.where((s) {
      final d = s.nextBillingDate;
      return s.daysUntilRenewal >= 0 &&
          d.year == now.year &&
          d.month == now.month;
    }).toList()
      ..sort((a, b) => b.cost.compareTo(a.cost));
    final biggest = dueThisMonth.isEmpty ? null : dueThisMonth.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        _AnnualForecastCard(yearly: yearly, monthly: monthly),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: isLt ? 'Šį mėnesį' : 'This month',
                value: formatMoney(monthly),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: isLt ? 'Per dieną' : 'Per day',
                value: formatMoney(daily),
              ),
            ),
          ],
        ),
        if (biggest != null) ...[
          const SizedBox(height: 20),
          _BiggestPaymentCard(sub: biggest),
        ],
        const SizedBox(height: 28),
        _sectionTitle(context, isLt ? 'Didžiausios išlaidos' : 'Top expenses'),
        const SizedBox(height: 12),
        for (final s in top) _TopExpenseRow(sub: s, monthlyTotal: monthly),
        const SizedBox(height: 24),
        _sectionTitle(context, l.byCategory),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _DonutPainter(
                values: [for (final e in entries) e.value],
                colors: [for (final e in entries) categoryFor(e.key).color],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatMoney(monthly),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20)),
                    Text(l.slashMonth, style: const TextStyle(color: _dSubtle)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        for (final e in entries)
          _CategoryRow(
            color: categoryFor(e.key).color,
            icon: categoryFor(e.key).icon,
            label: categoryLabel(e.key, isLt),
            amount: formatMoney(e.value),
            fraction: monthly == 0 ? 0.0 : e.value / monthly,
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _dCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _dSubtle, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ],
      ),
    );
  }
}

/// Prominent hero card: what the current expenses cost over a year.
class _AnnualForecastCard extends StatelessWidget {
  const _AnnualForecastCard({required this.yearly, required this.monthly});

  final double yearly;
  final double monthly;

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2A22), Color(0xFF151C17)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2C3A31)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                isLt ? 'Metinė prognozė' : 'Annual forecast',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(yearly),
            style: const TextStyle(
                color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            isLt
                ? '≈ ${formatMoney(monthly)}/mėn. · pagal dabartines išlaidas'
                : '≈ ${formatMoney(monthly)}/mo · based on your current expenses',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Highlighted card for the single most expensive charge still due this month.
class _BiggestPaymentCard extends StatelessWidget {
  const _BiggestPaymentCard({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final days = sub.daysUntilRenewal;
    final due = days == 0
        ? (isLt ? 'šiandien' : 'today')
        : days == 1
            ? (isLt ? 'rytoj' : 'tomorrow')
            : (isLt ? 'po $days d.' : 'in $days days');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dHiBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _dHiBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLt
                ? 'Didžiausias šio mėn. mokėjimas'
                : 'Biggest payment this month',
            style: const TextStyle(
                color: Color(0xFF9A7B2E),
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SubscriptionAvatar(
                name: sub.name,
                category: sub.category,
                logoDomain: sub.logoDomain,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(due,
                        style: const TextStyle(color: _dSubtle, fontSize: 13)),
                  ],
                ),
              ),
              Text(
                sub.isEstimated
                    ? '~${formatMoney(sub.cost)}'
                    : formatMoney(sub.cost),
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of the Top expenses list: avatar, name/category, monthly figure + %.
class _TopExpenseRow extends StatelessWidget {
  const _TopExpenseRow({required this.sub, required this.monthlyTotal});

  final Subscription sub;
  final double monthlyTotal;

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final pct = monthlyTotal == 0 ? 0.0 : sub.monthlyCost / monthlyTotal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          SubscriptionAvatar(
            name: sub.name,
            category: sub.category,
            logoDomain: sub.logoDomain,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sub.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                Text(categoryLabel(sub.category, isLt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _dSubtle, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${sub.isEstimated ? '~' : ''}${formatMoney(sub.monthlyCost)}${isLt ? '/mėn.' : '/mo'}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text('${(pct * 100).round()}%',
                  style: const TextStyle(color: _dSubtle, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.color,
    required this.icon,
    required this.label,
    required this.amount,
    required this.fraction,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${(fraction * 100).round()}%  ',
                  style: const TextStyle(color: _dSubtle)),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: _dLine,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight donut chart so we don't need a charting dependency.
class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final stroke = size.width * 0.16;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );

    var start = -math.pi / 2;
    const gap = 0.04;
    for (var i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * (2 * math.pi);
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values;
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared pieces (unchanged behaviour)
// ─────────────────────────────────────────────────────────────────────────────

/// Subtle, dismissible banner shown only when iOS notification permission was
/// requested and denied — nudging the user to enable payment reminders. Never
/// shown if permission was never asked or is granted.
class _NotificationBanner extends StatefulWidget {
  const _NotificationBanner();

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner> {
  bool _denied = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _dismissed = AppPrefs.notifBannerDismissed;
    if (!_dismissed) _check();
  }

  Future<void> _check() async {
    final denied = await NotificationService.instance.isPermissionDenied();
    if (mounted) setState(() => _denied = denied);
  }

  Future<void> _openSettings() async {
    // iOS deep-link to this app's Settings page.
    try {
      await launchUrl(Uri.parse('app-settings:'),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing sensible to do if the platform can't open Settings.
    }
  }

  void _dismiss() {
    AppPrefs.setNotifBannerDismissed(true);
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || !_denied) return const SizedBox.shrink();
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: _dHiBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _dHiBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_outlined,
                color: Color(0xFF9A7B2E), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLt ? 'Priminimai išjungti' : 'Reminders are off',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    isLt
                        ? 'Įjunk, kad gautum mokėjimų priminimus'
                        : 'Enable them to get payment alerts',
                    style: const TextStyle(color: _dSubtle, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _openSettings,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9A7B2E),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(isLt ? 'Įjungti' : 'Enable',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            InkWell(
              onTap: _dismiss,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 16, color: _dSubtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim reminder shown at the top of the Overview tab while the signed-in user
/// hasn't verified their email. Offers a resend and a "check again" refresh.
class _VerifyEmailBanner extends StatefulWidget {
  const _VerifyEmailBanner();

  @override
  State<_VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends State<_VerifyEmailBanner> {
  final _auth = AuthService();
  bool _busy = false;

  Future<void> _resend(bool isLt) async {
    setState(() => _busy = true);
    await _auth.sendEmailVerification();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isLt
            ? 'Patvirtinimo laiškas išsiųstas dar kartą.'
            : 'Verification email sent again.'),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _auth.reloadUser();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to show once verified (or if somehow not signed in).
    if (!_auth.isLoggedIn || _auth.isEmailVerified) {
      return const SizedBox.shrink();
    }
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _dHiBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _dHiBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined,
              color: Color(0xFFB7791F)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isLt
                  ? 'Patvirtinkite savo el. paštą, kad apsaugotumėte paskyrą.'
                  : 'Verify your email to secure your account.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF7A5B1E)),
            ),
          ),
          if (_busy)
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              children: [
                TextButton(
                  onPressed: _refresh,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                  child: Text(isLt ? 'Atnaujinti' : 'Refresh'),
                ),
                TextButton(
                  onPressed: () => _resend(isLt),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                  child: Text(isLt ? 'Siųsti vėl' : 'Resend'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({required this.sub});

  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final days = sub.daysUntilRenewal;
    final renews = days < 0
        ? l.renewOverdue
        : days == 0
            ? l.renewToday
            : days == 1
                ? l.renewTomorrow
                : l.renewInDays(days);

    return Dismissible(
      key: ValueKey(sub.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: VaultieColors.danger,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) {
        // Record the cancellation (kept for future savings insights). Guarded
        // so it never throws if the box somehow isn't open.
        if (Hive.isBoxOpen(HiveBoxes.cancellations)) {
          Hive.box(HiveBoxes.cancellations).add({
            'monthly': sub.monthlyCost,
            'date': DateTime.now().millisecondsSinceEpoch,
            'name': sub.name,
          });
        }
        Hive.box<Subscription>(HiveBoxes.subscriptions).delete(sub.id);
        NotificationService.instance.cancelForSubscription(sub.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.removedFromVault(sub.name))),
        );
      },
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          // Tapping a subscription opens the form in edit mode; saving there
          // reschedules its renewal reminders via NotificationService.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AddSubscriptionScreen(existing: sub),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SubscriptionAvatar(
                  name: sub.name,
                  category: sub.category,
                  logoDomain: sub.logoDomain,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${categoryLabel(sub.category, isLt)} · $renews',
                        style: const TextStyle(
                          color: _dSubtle,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      sub.isEstimated
                          ? '~${formatMoney(sub.cost)}'
                          : formatMoney(sub.cost),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      billingCycleLabel(l, sub.billingCycle),
                      style: const TextStyle(
                        color: _dSubtle,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Monthly-budget progress: bar + "spent of budget", turning orange near the
/// limit and red when over.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.spent, required this.budget});

  final double spent;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final ratio = budget <= 0 ? 0.0 : spent / budget;
    final over = spent > budget;
    final color = over
        ? VaultieColors.danger
        : ratio >= 0.8
            ? const Color(0xFFE9A23B)
            : _brightGreen;
    return GestureDetector(
      // Tap the card to change or remove the budget — no trip to Settings.
      onTap: () => editMonthlyBudget(context, isLt: isLt),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _dCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _dLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isLt ? 'Mėnesio biudžetas' : 'Monthly budget',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 14, color: _dSubtle),
                const Spacer(),
                Text(
                  '${(ratio * 100).round()}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: _dLine,
                color: color,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              over
                  ? (isLt
                      ? 'Viršyta ${formatMoney(spent - budget)}'
                      : 'Over by ${formatMoney(spent - budget)}')
                  : (isLt
                      ? '${formatMoney(spent)} iš ${formatMoney(budget)}'
                      : '${formatMoney(spent)} of ${formatMoney(budget)}'),
              style: const TextStyle(color: _dSubtle, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim, optional prompt shown when no budget is set — discoverable but never
/// forced. Tapping opens the same manual budget editor.
class _SetBudgetPrompt extends StatelessWidget {
  const _SetBudgetPrompt();

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: GestureDetector(
        onTap: () => editMonthlyBudget(context, isLt: isLt),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _dCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _dLine),
          ),
          child: Row(
            children: [
              const Icon(Icons.savings_outlined, color: _brightGreen, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLt
                          ? 'Nustatyti mėnesio biudžetą'
                          : 'Set a monthly budget',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    Text(
                      isLt ? 'Neprivaloma' : 'Optional',
                      style: const TextStyle(color: _dSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.add, color: _brightGreen),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 110),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l.vaultEmptyTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            l.vaultEmptyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _dSubtle),
          ),
          const SizedBox(height: 30),
          _emptyLabel(
              isLt ? 'Pradėk nuo kategorijos' : 'Start with a category'),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 8,
            childAspectRatio: 0.82,
            children: [
              for (final cat in kExpenseCategories)
                _catQuickTile(context, cat, isLt),
            ],
          ),
          const SizedBox(height: 26),
          _emptyLabel(
              isLt ? 'Arba populiari paslauga' : 'Or a popular service'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            alignment: WrapAlignment.center,
            children: [
              for (final b in kPopularGrid) _QuickAddTile(brand: b),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _dSubtle,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      );

  /// A category tile on the empty state — opens the add form with that category
  /// (and its defaults) preselected.
  Widget _catQuickTile(BuildContext context, ExpenseCategory cat, bool isLt) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AddSubscriptionScreen(initialCategory: cat.key),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cat.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(cat.icon, color: cat.color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            cat.label(isLt),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.1,
              fontWeight: FontWeight.w500,
              color: _dSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable popular-service tile on the empty dashboard: opens the add form
/// with that service preselected.
class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile({required this.brand});

  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final label = brand == Brand.other
        ? (isLt ? 'Kita' : 'Other')
        : brandSpec(brand).label;
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddSubscriptionScreen(initialBrand: brand),
              ),
            ),
            child: BrandLogo(brand: brand, size: 54),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _dSubtle),
          ),
        ],
      ),
    );
  }
}
