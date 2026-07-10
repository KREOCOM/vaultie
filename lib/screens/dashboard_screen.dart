import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_prefs.dart';
import '../content_theme.dart';
import '../expense_categories.dart';
import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/auth_service.dart';
import '../services/feature_flags.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';
import '../services/recap_service.dart';
import '../widgets/budget_dialog.dart';
import '../widgets/subscription_avatar.dart';
import '../widgets/subscription_icons.dart';
import 'add_subscription_screen.dart';
import 'bank_info_screen.dart';
import 'paywall_screen.dart';
import 'recap_screen.dart';
import 'savings_screen.dart';
import 'settings_screen.dart';

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

    // Listen to the light/dark toggle so the whole dashboard subtree (including
    // the embedded Settings tab) rebuilds instantly when it changes.
    return ValueListenableBuilder<bool>(
      valueListenable: AppPrefs.darkMode,
      builder: (context, dark, _) {
        applyContentTheme(dark);
        return Theme(
          data: contentTheme(Theme.of(context)),
          child: Scaffold(
            backgroundColor: cBg,
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
                    labelColor: cAccent,
                    unselectedLabelColor: cSubtle,
                    indicatorColor: cAccent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
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
                            // Not const: must rebuild when the theme toggles.
                            // ignore: prefer_const_constructors
                            SettingsScreen(embedded: true),
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
      },
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
          SliverToBoxAdapter(child: _ThisMonthCard(subs: subs)),
          const SliverToBoxAdapter(child: _SavingsCard()),
          SliverToBoxAdapter(child: _UpcomingRenewals(subs: subs)),
          // Pro / feature discovery sits below the money summary, not above it,
          // so the dashboard leads with what the user came for. The bank card
          // only appears when the remote `banking_enabled` flag is on, so the
          // feature can be flipped on/off from Firebase without an app update.
          SliverToBoxAdapter(
            child: ValueListenableBuilder<bool>(
              valueListenable: FeatureFlags.instance.bankingEnabled,
              builder: (context, bankingOn, _) =>
                  bankingOn ? const _ConnectBankCard() : const SizedBox.shrink(),
            ),
          ),
          SliverToBoxAdapter(child: _categoryChips(subs, isLt)),
          if (subs.length >= 2) SliverToBoxAdapter(child: _searchSortBar(isLt)),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    isLt ? 'Nieko nerasta' : 'No matches',
                    style: TextStyle(color: cSubtle),
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
              color: selected ? VaultieColors.primary : cCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? VaultieColors.primary : cLine,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: selected ? Colors.white : (color ?? cAccent)),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : cInk,
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
              color: cCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cLine),
            ),
            child: PopupMenuButton<_SortMode>(
              icon: Icon(Icons.sort, color: cInk),
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
                ? Icon(Icons.check, size: 18, color: cAccent)
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

  /// Last calendar month's recurring total from the monthlyStats snapshots, or
  /// null if there's no prior month to compare against yet.
  double? _lastMonthTotal() {
    if (!Hive.isBoxOpen(HiveBoxes.monthlyStats)) return null;
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1, 1);
    final key = '${prev.year}-${prev.month.toString().padLeft(2, '0')}';
    final raw = Hive.box(HiveBoxes.monthlyStats).get(key);
    if (raw == null) return null;
    return (Map.from(raw as Map)['total'] as num?)?.toDouble();
  }

  /// A small pill that turns the monthly figure into meaning: down vs last
  /// month reads as a win (green), up as a heads-up (amber). Icon + label, so
  /// it isn't colour-alone. Hidden when nothing changed.
  Widget _monthTrendChip(bool isLt, double monthlyTotal, double lastMonth) {
    final diff = monthlyTotal - lastMonth;
    if (diff.abs() < 0.5) return const SizedBox.shrink();
    final down = diff < 0;
    final color = down ? cAccent : const Color(0xFFE9A23B);
    final amount = formatMoney(diff.abs());
    final label = down
        ? (isLt ? '$amount mažiau nei praeitą mėn.' : '$amount less than last month')
        : (isLt ? '$amount daugiau nei praeitą mėn.' : '$amount more than last month');
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(down ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final name = _userName(isLt);
    final monthlyTotal = subs.fold<double>(0, (s, e) => s + e.monthlyCost);
    final lastMonth = _lastMonthTotal();

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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cFeatTop, cFeatBottom],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: cFeatBorder),
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
                        style: TextStyle(
                          color: cFeatSubtle,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cFeatInk,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Empty vault: a warm welcome instead of a bare "€0.00" so the
            // first-run header feels inviting, not empty. The add options live
            // in the empty state below.
            if (subs.isEmpty)
              Text(
                isLt
                    ? 'Sveikas atvykęs į Vaultie — susirinkim visas tavo pasikartojančias išlaidas vienoje vietoje.'
                    : 'Welcome to Vaultie — let\'s get all your recurring spend in one place.',
                style: TextStyle(color: cFeatSubtle, fontSize: 15, height: 1.4),
              )
            else ...[
              // Amount on the left, category ring on the right.
              Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.monthlySpend.toUpperCase(),
                        style: TextStyle(
                          color: cAccent,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatMoney(monthlyTotal),
                        style: TextStyle(
                          color: cFeatInk,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.activeSubscriptions(subs.length),
                        style: TextStyle(
                          color: cFeatSubtle,
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
            // At-a-glance insight: is recurring spend up or down vs last month?
            if (lastMonth != null)
              _monthTrendChip(isLt, monthlyTotal, lastMonth),
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
                          style: TextStyle(
                            color: cFeatSubtle,
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
          ],
        ),
      ),
    );
  }
}

/// Compact "this month" recurring summary (Bilance-inspired). Vaultie has no
/// income/balance data — that needs a bank — so instead of a true "balance
/// after recurrings" we show what is honestly derivable from the subscriptions
/// alone: how much of this month's recurring bills is still to be paid.
class _ThisMonthCard extends StatelessWidget {
  const _ThisMonthCard({required this.subs});

  final List<Subscription> subs;

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Split this calendar month's recurring charges into already-paid and still
    // upcoming. Vaultie stores no payment history, so "paid" is derived: a
    // charge one cycle before the next one that falls earlier this month has
    // already happened. (Approximate for weekly cycles with several charges a
    // month; exact for the common monthly/quarterly/yearly cases.)
    double paid = 0;
    double upcoming = 0;
    var n = 0;
    for (final s in subs) {
      if (s.daysUntilRenewal >= 0 &&
          s.nextBillingDate.year == now.year &&
          s.nextBillingDate.month == now.month) {
        upcoming += s.cost;
        n++;
      }
      final prev = s.billingCycle.advanceFrom(s.nextBillingDate, -1);
      if (prev.year == now.year &&
          prev.month == now.month &&
          !prev.isAfter(today)) {
        paid += s.cost;
      }
    }
    final total = paid + upcoming;
    final fraction = total <= 0 ? 1.0 : (paid / total).clamp(0.0, 1.0);
    final pct = (fraction * 100).round();

    final subtitle = n == 0
        ? (isLt ? 'Šį mėnesį daugiau mokėjimų nėra 🎉' : 'No more payments this month 🎉')
        : isLt
            // "laukia" takes the genitive: 1 mokėjimo / N mokėjimų.
            ? (n == 1 ? 'Dar laukia 1 mokėjimo' : 'Dar laukia $n mokėjimų')
            : (n == 1 ? '1 payment still due' : '$n payments still due');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cLine),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_repeat_rounded, size: 18, color: cAccent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isLt
                              ? 'Liko sumokėti šį mėnesį'
                              : 'Left to pay this month',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    formatMoney(upcoming),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 28),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: cSubtle, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // Radial gauge: share of this month's recurring already paid.
            SizedBox(
              width: 74,
              height: 74,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(74, 74),
                    painter: _MonthRingPainter(
                      fraction: fraction,
                      color: cAccent,
                      track: cLine,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$pct%',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 17)),
                      Text(isLt ? 'sumokėta' : 'paid',
                          style: TextStyle(color: cSubtle, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Radial gauge for [_ThisMonthCard]: a muted full-circle track with an accent
/// arc for the paid fraction, drawn from the top clockwise. Rounded caps.
class _MonthRingPainter extends CustomPainter {
  _MonthRingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.width - stroke) / 2,
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        fraction * 2 * math.pi,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonthRingPainter old) =>
      old.fraction != fraction;
}

/// "Artimiausi mokėjimai" — next three renewals with a colour dot and a
/// days-remaining badge (red < 7 days, orange < 14, green otherwise).
class _UpcomingRenewals extends StatelessWidget {
  const _UpcomingRenewals({required this.subs});

  final List<Subscription> subs;

  Color _badgeColor(int days) {
    if (days < 7) return VaultieColors.danger; // red
    if (days < 14) return const Color(0xFFE9A23B); // orange
    return cAccent; // green
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
                style: TextStyle(
                  color: cInk,
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
            style: TextStyle(
              color: cInk,
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
            style: TextStyle(color: cSubtle),
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
        const SizedBox(height: 20),
        const _RecurringTrendCard(),
        if (biggest != null) ...[
          const SizedBox(height: 20),
          _BiggestPaymentCard(sub: biggest),
        ],
        const SizedBox(height: 20),
        _WaysToSaveCard(subs: subs, isLt: isLt),
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
                showLabels: true,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatMoney(monthly),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20)),
                    Text(l.slashMonth, style: TextStyle(color: cSubtle)),
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
        color: cCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cSubtle, fontSize: 12)),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cFeatTop, cFeatBottom],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cFeatBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  color: cFeatSubtle, size: 18),
              const SizedBox(width: 8),
              Text(
                isLt ? 'Metinė prognozė' : 'Annual forecast',
                style: TextStyle(
                    color: cFeatSubtle,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(yearly),
            style: TextStyle(
                color: cFeatInk, fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            isLt
                ? '≈ ${formatMoney(monthly)}/mėn. · pagal dabartines išlaidas'
                : '≈ ${formatMoney(monthly)}/mo · based on your current expenses',
            style: TextStyle(color: cFeatSubtle, fontSize: 13),
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
        color: cHiBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cHiBorder),
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
                    Text(due, style: TextStyle(color: cSubtle, fontSize: 13)),
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

/// Premium entry card for the "Ways to save" screen. Free users tapping it hit
/// the paywall; Pro users open their personalised savings tips.
class _WaysToSaveCard extends StatelessWidget {
  const _WaysToSaveCard({required this.subs, required this.isLt});

  final List<Subscription> subs;
  final bool isLt;

  void _open(BuildContext context) {
    if (PurchaseService.instance.isPremium) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SavingsScreen(subscriptions: subs)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [VaultieColors.primary, VaultieColors.primaryDark],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.savings_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(isLt ? 'Kaip sutaupyti' : 'Ways to save',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                        const SizedBox(width: 8),
                        if (!PurchaseService.instance.isPremium)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: VaultieColors.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('PRO',
                                style: TextStyle(
                                    color: VaultieColors.primaryDark,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    letterSpacing: 0.5)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isLt
                          ? 'Patarimai, kaip sumažinti sąskaitas'
                          : 'Personalised tips to cut your bills',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withValues(alpha: 0.7), size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overview entry point for the bank import (Vaultie 2.0). Free users tapping it
/// hit the paywall; Pro users open the bank-connect flow. Rebuilds when the
/// premium entitlement changes so the PRO badge appears/disappears live.
class _ConnectBankCard extends StatelessWidget {
  const _ConnectBankCard();

  void _open(BuildContext context) {
    if (PurchaseService.instance.isPremium) {
      // Show the "how it works" info screen before the bank list.
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BankInfoScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    return ValueListenableBuilder<bool>(
      valueListenable: PurchaseService.instance.isPremiumListenable,
      builder: (context, isPremium, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _open(context),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cLine),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: VaultieColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.account_balance_rounded,
                          color: VaultieColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  isLt ? 'Prijungti banką' : 'Connect your bank',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: cInk,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!isPremium)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: VaultieColors.accent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('PRO',
                                      style: TextStyle(
                                          color: VaultieColors.primaryDark,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          letterSpacing: 0.5)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isLt
                                ? 'Automatiškai rask pasikartojančius mokėjimus'
                                : 'Auto-detect your recurring payments',
                            style: TextStyle(color: cSubtle, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded,
                        color: cSubtle, size: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
                    style: TextStyle(color: cSubtle, fontSize: 12)),
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
                  style: TextStyle(color: cSubtle, fontSize: 12)),
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
                  style: TextStyle(color: cSubtle)),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: cLine,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gamified savings card (Overview). Surfaces the cancellation history — which
/// the app records but never showed — as motivation: total money saved since
/// cancelling, a per-month figure, and a sparkline of savings accruing. Hidden
/// entirely until the user has cancelled at least one subscription.
class _SavingsCard extends StatelessWidget {
  const _SavingsCard();

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final box = Hive.box(HiveBoxes.cancellations);
    final entries = box.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    double monthlySaved = 0;
    double cumulative = 0;
    for (final e in entries) {
      final m = (e['monthly'] as num?)?.toDouble() ?? 0;
      final d = DateTime.fromMillisecondsSinceEpoch(
          (e['date'] as num?)?.toInt() ?? now.millisecondsSinceEpoch);
      monthlySaved += m;
      final months = now.difference(d).inDays / 30.44;
      cumulative += m * (months < 0 ? 0 : months);
    }
    final count = entries.length;

    // Cumulative saved at the end of each of the last 6 months → sparkline.
    final spark = <double>[];
    for (var i = 5; i >= 0; i--) {
      final end = DateTime(now.year, now.month - i + 1, 0);
      double c = 0;
      for (final e in entries) {
        final m = (e['monthly'] as num?)?.toDouble() ?? 0;
        final d = DateTime.fromMillisecondsSinceEpoch(
            (e['date'] as num?)?.toInt() ?? now.millisecondsSinceEpoch);
        if (!d.isAfter(end)) {
          final months = end.difference(d).inDays / 30.44;
          c += m * (months < 0 ? 0 : months);
        }
      }
      spark.add(c);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VaultieColors.primary, VaultieColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.savings_rounded,
                    color: VaultieColors.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  isLt ? 'Sutaupei atšaukdamas' : 'Saved by cancelling',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatMoney(cumulative),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 30),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLt
                            ? 'iki šiol · ${formatMoney(monthlySaved)}/mėn. · $count atšaukta'
                            : 'so far · ${formatMoney(monthlySaved)}/mo · $count cancelled',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 84,
                  height: 40,
                  child: CustomPaint(
                    size: const Size(84, 40),
                    painter: _SparklinePainter(
                        values: spark, color: VaultieColors.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal sparkline (line + soft area + endpoint dot) for [_SavingsCard]. No
/// axes — the number beside it carries the value; this shows the shape.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);
    Offset pt(int i) =>
        Offset(dx * i, size.height - ((values[i] - minV) / range) * size.height);

    final line = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(pt(i).dx, pt(i).dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        area, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pt(values.length - 1), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) => old.values != values;
}

/// Recurring-spend trend over recent months (Analytics). The data's job is
/// change-over-time, so one bar per month; a single series needs no legend (the
/// title names it). Values come from the monthlyStats snapshots taken on each
/// launch, so the chart fills in over a few months.
class _RecurringTrendCard extends StatelessWidget {
  const _RecurringTrendCard();

  static const _ltMonths = [
    '', 'Sau', 'Vas', 'Kov', 'Bal', 'Geg', 'Bir',
    'Lie', 'Rgp', 'Rgs', 'Spa', 'Lap', 'Grd'
  ];
  static const _enMonths = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final box = Hive.box(HiveBoxes.monthlyStats);
    final keys = box.keys
        .whereType<String>()
        .where((k) => RegExp(r'^\d{4}-\d{2}$').hasMatch(k))
        .toList()
      ..sort();
    final recent = keys.length <= 6 ? keys : keys.sublist(keys.length - 6);
    final months = isLt ? _ltMonths : _enMonths;
    final points = <_TrendPoint>[
      for (final k in recent)
        _TrendPoint(
          months[int.parse(k.split('-').last)],
          ((Map.from(box.get(k) as Map)['total'] as num?)?.toDouble() ?? 0.0),
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: cCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isLt ? 'Pasikartojančių tendencija' : 'Recurring trend',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              if (points.length >= 2)
                _changeBadge(points.first.value, points.last.value),
            ],
          ),
          const SizedBox(height: 16),
          if (points.length < 2)
            _lowData(isLt)
          else
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                size: const Size(double.infinity, 150),
                painter: _TrendBarPainter(
                  points: points,
                  barColor: cAccent,
                  labelColor: cSubtle,
                  valueColor: cInk,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// % change from the first shown month to the latest. Rising recurring spend
  /// is a caution (orange); falling is a win (green). Icon + label, not colour
  /// alone.
  Widget _changeBadge(double first, double last) {
    if (first <= 0) return const SizedBox.shrink();
    final pct = ((last - first) / first * 100).round();
    if (pct == 0) return const SizedBox.shrink();
    final up = pct > 0;
    final color = up ? const Color(0xFFE9A23B) : cAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text('${up ? '+' : ''}$pct%',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _lowData(bool isLt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        children: [
          Icon(Icons.insights_rounded, color: cSubtle, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isLt
                  ? 'Tendencija atsiras po kelių mėnesių — kaupiame kas mėnesį.'
                  : 'Your trend appears after a couple of months — we snapshot monthly.',
              style: TextStyle(color: cSubtle, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPoint {
  const _TrendPoint(this.label, this.value);
  final String label;
  final double value;
}

/// Bars for [_RecurringTrendCard]: thin marks, 4px-rounded tops anchored to a
/// faint baseline, the current month emphasised, values in a text token above
/// each bar and month labels below. Recessive axis (baseline only, no grid).
class _TrendBarPainter extends CustomPainter {
  _TrendBarPainter({
    required this.points,
    required this.barColor,
    required this.labelColor,
    required this.valueColor,
  });

  final List<_TrendPoint> points;
  final Color barColor;
  final Color labelColor;
  final Color valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    if (n == 0) return;
    final maxV =
        points.map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b);
    final safeMax = maxV <= 0 ? 1.0 : maxV;

    const labelH = 18.0; // month labels below the baseline
    const valueH = 15.0; // value labels above the tallest bar
    final chartBottom = size.height - labelH;
    final chartH = chartBottom - valueH;

    final slot = size.width / n;
    final barW = (slot * 0.5).clamp(8.0, 34.0);

    final baseline = Paint()
      ..color = labelColor.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, chartBottom), Offset(size.width, chartBottom), baseline);

    for (var i = 0; i < n; i++) {
      final p = points[i];
      final cx = slot * i + slot / 2;
      final h = (p.value / safeMax) * chartH;
      final top = chartBottom - h;
      final isLast = i == n - 1;

      final paint = Paint()
        ..color = isLast ? barColor : barColor.withValues(alpha: 0.42);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - barW / 2, top, barW, h),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );

      _text(canvas, formatMoney(p.value), cx, top - 13.5, valueColor,
          isLast ? FontWeight.w800 : FontWeight.w600, 9.5);
      _text(canvas, p.label, cx, chartBottom + 3, labelColor,
          isLast ? FontWeight.w700 : FontWeight.w500, 11);
    }
  }

  void _text(Canvas canvas, String s, double cx, double top, Color color,
      FontWeight fw, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
          text: s, style: TextStyle(color: color, fontSize: fontSize, fontWeight: fw)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, top));
  }

  @override
  bool shouldRepaint(covariant _TrendBarPainter old) => old.points != points;
}

/// Lightweight donut chart so we don't need a charting dependency.
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    this.showLabels = false,
  });

  final List<double> values;
  final List<Color> colors;

  /// When true, each segment ≥ 10% gets a direct "%" label on the ring band
  /// (white with a soft shadow so it reads on any category colour), so identity
  /// isn't left to the legend alone.
  final bool showLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final stroke = size.width * 0.16;
    final radius = (size.width - stroke) / 2;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);

    var start = -math.pi / 2;
    const gap = 0.04;
    for (var i = 0; i < values.length; i++) {
      final frac = values[i] / total;
      final sweep = frac * (2 * math.pi);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..color = colors[i % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );

      if (showLabels && frac >= 0.10) {
        final mid = start + sweep / 2;
        final pos = Offset(
          center.dx + radius * math.cos(mid),
          center.dy + radius * math.sin(mid),
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${(frac * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }

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
          color: cHiBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cHiBorder),
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
                    style: TextStyle(color: cSubtle, fontSize: 12),
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
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close, size: 16, color: cSubtle),
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
        color: cHiBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cHiBorder),
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
                        style: TextStyle(
                          color: cSubtle,
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
                      style: TextStyle(
                        color: cSubtle,
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
            : cAccent;
    return GestureDetector(
      // Tap the card to change or remove the budget — no trip to Settings.
      onTap: () => editMonthlyBudget(context, isLt: isLt),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cLine),
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
                Icon(Icons.edit_outlined, size: 14, color: cSubtle),
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
                backgroundColor: cLine,
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
              style: TextStyle(color: cSubtle, fontSize: 13),
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
            color: cCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cLine),
          ),
          child: Row(
            children: [
              Icon(Icons.savings_outlined, color: cAccent, size: 22),
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
                      style: TextStyle(color: cSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.add, color: cAccent),
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
            style: TextStyle(color: cSubtle),
          ),
          const SizedBox(height: 30),
          _emptyLabel(
              isLt ? 'Pradėk nuo kategorijos' : 'Start with a category'),
          const SizedBox(height: 14),
          // Single horizontal row (scrollable) instead of a tall grid, so the
          // first run reads as calm and inviting, not a wall of tiles.
          SizedBox(
            height: 82,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: [
                for (final cat in kExpenseCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SizedBox(
                        width: 62, child: _catQuickTile(context, cat, isLt)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _emptyLabel(
              isLt ? 'Arba populiari paslauga' : 'Or a popular service'),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: [
                for (final b in kPopularGrid)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: _QuickAddTile(brand: b),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyLabel(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: cSubtle,
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
            style: TextStyle(
              fontSize: 9.5,
              height: 1.1,
              fontWeight: FontWeight.w500,
              color: cSubtle,
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
            style: TextStyle(fontSize: 11, color: cSubtle),
          ),
        ],
      ),
    );
  }
}
