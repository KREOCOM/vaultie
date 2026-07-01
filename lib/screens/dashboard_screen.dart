import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../l10n/localized_labels.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';
import '../widgets/subscription_avatar.dart';
import 'add_subscription_screen.dart';
import 'auth_screen.dart';
import 'paywall_screen.dart';

/// Category donut colours.
const List<Color> _catPalette = [
  VaultieColors.primary,
  VaultieColors.primaryLight,
  VaultieColors.accent,
  Color(0xFFE9A23B),
  Color(0xFF4A6FA5),
  Color(0xFF8E5BA6),
  Color(0xFFD9534F),
  Color(0xFF6B7E74),
];

const Color _brightGreen = Color(0xFF4CAF72);

/// Home screen: two tabs — Overview (Apžvalga) and Analytics (Analitika).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const route = '/dashboard';

  static final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
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
                labelColor: VaultieColors.primary,
                unselectedLabelColor: VaultieColors.subtle,
                indicatorColor: VaultieColors.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                tabs: [
                  Tab(text: isLt ? 'Apžvalga' : 'Overview'),
                  Tab(text: isLt ? 'Analitika' : 'Analytics'),
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
                      children: [
                        _OverviewTab(subs: subs),
                        _AnalyticsTab(subs: subs),
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
        MaterialPageRoute(builder: (_) => const PaywallScreen()),
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.subs});

  final List<Subscription> subs;

  @override
  Widget build(BuildContext context) {
    final monthlyTotal = subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _VerifyEmailBanner()),
        SliverToBoxAdapter(
          child:
              _OverviewHeader(monthlyTotal: monthlyTotal, count: subs.length),
        ),
        if (subs.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else ...[
          SliverToBoxAdapter(child: _UpcomingRenewals(subs: subs)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            sliver: SliverList.separated(
              itemCount: subs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _SubscriptionTile(sub: subs[i]),
            ),
          ),
        ],
      ],
    );
  }
}

/// Green header: avatar, time-of-day greeting + user name, monthly spend, count.
class _OverviewHeader extends StatelessWidget {
  const _OverviewHeader({required this.monthlyTotal, required this.count});

  final double monthlyTotal;
  final int count;

  String _greeting(bool isLt) {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return isLt ? 'Labas rytas' : 'Good morning';
    if (h >= 12 && h < 18) return isLt ? 'Labas' : 'Good afternoon';
    return isLt ? 'Labas vakaras' : 'Good evening';
  }

  String _userName(bool isLt) {
    final u = AuthService().currentUser;
    final display = u?.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final email = u?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return isLt ? 'Naudotojau' : 'there';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final name = _userName(isLt);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VaultieColors.primary, // #174E35
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SubscriptionAvatar(name: name, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting(isLt),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () async {
                  await AuthService().signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false,
                  );
                },
                child:
                    const Icon(Icons.logout, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l.monthlySpend, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            DashboardScreen._money.format(monthlyTotal),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(l.activeSubscriptions(count),
              style: const TextStyle(color: Colors.white70)),
        ],
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
    final upcoming = subs.take(3).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isLt ? 'Artimiausi mokėjimai' : 'Upcoming renewals',
                style: const TextStyle(
                  color: VaultieColors.ink,
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
            color: SubscriptionAvatar.colorFor(sub.name),
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
              color: VaultieColors.ink,
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

enum _Range { months, years, days }

class _AnalyticsTab extends StatefulWidget {
  const _AnalyticsTab({required this.subs});

  final List<Subscription> subs;

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  _Range _range = _Range.months;

  static const _monthsEn = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _monthsLt = [
    'Sau',
    'Vas',
    'Kov',
    'Bal',
    'Geg',
    'Bir',
    'Lie',
    'Rgp',
    'Rgs',
    'Spa',
    'Lap',
    'Grd',
  ];

  DateTime _createdAt(Subscription s) {
    final micros = int.tryParse(s.id);
    return micros != null
        ? DateTime.fromMicrosecondsSinceEpoch(micros)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// The bar series for the active range. Since the app keeps no historical
  /// spend, each bucket is reconstructed from which subscriptions existed then
  /// (their id encodes the creation time).
  (List<double>, List<String>) _series(bool isLt) {
    final subs = widget.subs;
    final now = DateTime.now();
    final values = <double>[];
    final labels = <String>[];

    switch (_range) {
      case _Range.months:
        for (var i = 5; i >= 0; i--) {
          final month = DateTime(now.year, now.month - i, 1);
          final next = DateTime(month.year, month.month + 1, 1);
          values.add(subs
              .where((s) => _createdAt(s).isBefore(next))
              .fold<double>(0, (sum, s) => sum + s.monthlyCost));
          labels.add((isLt ? _monthsLt : _monthsEn)[month.month - 1]);
        }
      case _Range.years:
        for (var i = 5; i >= 0; i--) {
          final year = now.year - i;
          final next = DateTime(year + 1, 1, 1);
          values.add(subs
              .where((s) => _createdAt(s).isBefore(next))
              .fold<double>(0, (sum, s) => sum + s.yearlyCost));
          labels.add("'${year % 100}");
        }
      case _Range.days:
        final today = DateTime(now.year, now.month, now.day);
        for (var i = 6; i >= 0; i--) {
          final day = today.subtract(Duration(days: i));
          final next = day.add(const Duration(days: 1));
          values.add(subs
              .where((s) => _createdAt(s).isBefore(next))
              .fold<double>(0, (sum, s) => sum + s.yearlyCost / 365));
          labels.add('${day.day}');
        }
    }
    return (values, labels);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isLt = Localizations.localeOf(context).languageCode == 'lt';
    final subs = widget.subs;
    final money = DashboardScreen._money;

    if (subs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l.analyticsEmpty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VaultieColors.subtle),
          ),
        ),
      );
    }

    final monthly = subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);
    final yearly = monthly * 12;
    final daily = yearly / 365;
    final (values, labels) = _series(isLt);

    final byCategory = <String, double>{};
    for (final s in subs) {
      byCategory.update(s.category, (v) => v + s.monthlyCost,
          ifAbsent: () => s.monthlyCost);
    }
    final entries = byCategory.entries.toList()
      ..sort((a, c) => c.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        _RangeToggle(
          range: _range,
          isLt: isLt,
          onChanged: (r) => setState(() => _range = r),
        ),
        const SizedBox(height: 20),
        _BarChart(values: values, labels: labels),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: isLt ? 'Šį mėnesį' : 'This month',
                value: money.format(monthly),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: isLt ? 'Per metus' : 'Per year',
                value: money.format(yearly),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: isLt ? 'Per dieną' : 'Per day',
                value: money.format(daily),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          l.byCategory,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _DonutPainter(
                values: [for (final e in entries) e.value],
                colors: _catPalette,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(money.format(monthly),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20)),
                    Text(l.slashMonth,
                        style: const TextStyle(color: VaultieColors.subtle)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(entries.length, (i) {
          final e = entries[i];
          final pct = monthly == 0 ? 0.0 : e.value / monthly;
          return _CategoryRow(
            color: _catPalette[i % _catPalette.length],
            label: categoryLabel(l, e.key),
            amount: money.format(e.value),
            fraction: pct,
          );
        }),
      ],
    );
  }
}

/// Segmented Mėn / Metai / Diena toggle.
class _RangeToggle extends StatelessWidget {
  const _RangeToggle({
    required this.range,
    required this.isLt,
    required this.onChanged,
  });

  final _Range range;
  final bool isLt;
  final ValueChanged<_Range> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      _Range.months: isLt ? 'Mėn' : 'Months',
      _Range.years: isLt ? 'Metai' : 'Years',
      _Range.days: isLt ? 'Diena' : 'Days',
    };
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE1E8E3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final r in _Range.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: r == range ? VaultieColors.primary : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[r]!,
                    style: TextStyle(
                      color: r == range ? Colors.white : VaultieColors.subtle,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple vertical bar chart; the last (current) bucket is emphasised.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maxVal = values.fold<double>(0, (a, b) => b > a ? b : a);
    const chartHeight = 120.0;

    return SizedBox(
      height: chartHeight + 24,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final isLast = i == values.length - 1;
          final h = maxVal > 0 ? (values[i] / maxVal) * chartHeight : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: h < 4 ? 4 : h,
                    decoration: BoxDecoration(
                      color: isLast
                          ? VaultieColors.primary
                          : _brightGreen.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      color: VaultieColors.subtle,
                      fontSize: 11,
                      fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
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
        color: VaultieColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8E3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: VaultieColors.subtle, fontSize: 12)),
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.fraction,
  });

  final Color color;
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
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${(fraction * 100).round()}%  ',
                  style: const TextStyle(color: VaultieColors.subtle)),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: const Color(0xFFE1E8E3),
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
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0D9B5)),
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
        // Record the cancellation (kept for future savings insights).
        Hive.box(HiveBoxes.cancellations).add({
          'monthly': sub.monthlyCost,
          'date': DateTime.now().millisecondsSinceEpoch,
          'name': sub.name,
        });
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
                SubscriptionAvatar(name: sub.name, size: 48),
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
                        '${categoryLabel(l, sub.category)} · $renews',
                        style: const TextStyle(
                          color: VaultieColors.subtle,
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
                      DashboardScreen._money.format(sub.cost),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      billingCycleLabel(l, sub.billingCycle),
                      style: const TextStyle(
                        color: VaultieColors.subtle,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 128,
              height: 128,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l.vaultEmptyTitle,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            l.vaultEmptyBody,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VaultieColors.subtle),
          ),
        ],
      ),
    );
  }
}
