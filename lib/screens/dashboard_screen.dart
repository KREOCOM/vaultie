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
import '../widgets/wallet_mascot.dart';
import 'add_subscription_screen.dart';
import 'analytics_screen.dart';
import 'auth_screen.dart';
import 'paywall_screen.dart';

/// Home screen: a summary header plus the list of tracked subscriptions.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const route = '/dashboard';

  static final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Subscription>(HiveBoxes.subscriptions);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VaultieColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _onAddPressed(context, box),
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context).addButton),
      ),
      body: SafeArea(
        child: ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<Subscription> b, _) {
            final subs = b.values.toList()
              ..sort(
                  (a, c) => a.daysUntilRenewal.compareTo(c.daysUntilRenewal));
            final monthlyTotal =
                subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);

            final mood = switch (monthlyTotal) {
              < 30 => MascotMood.happy,
              < 100 => MascotMood.neutral,
              _ => MascotMood.worried,
            };

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _VerifyEmailBanner()),
                SliverToBoxAdapter(
                  child: _Header(
                    monthlyTotal: monthlyTotal,
                    count: subs.length,
                    mood: mood,
                  ),
                ),
                if (subs.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    sliver: SliverList.separated(
                      itemCount: subs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _SubscriptionTile(sub: subs[i]),
                    ),
                  ),
              ],
            );
          },
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

class _Header extends StatelessWidget {
  const _Header({
    required this.monthlyTotal,
    required this.count,
    required this.mood,
  });

  final double monthlyTotal;
  final int count;
  final MascotMood mood;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VaultieColors.primaryLight, VaultieColors.primary],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.monthlySpend,
                            style: const TextStyle(color: Colors.white70)),
                        InkWell(
                          onTap: () async {
                            await AuthService().signOut();
                            if (!context.mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const AuthScreen()),
                              (route) => false,
                            );
                          },
                          child: const Icon(Icons.logout,
                              color: Colors.white70, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DashboardScreen._money.format(monthlyTotal),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.activeSubscriptions(count),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              WalletMascot(size: 92, mood: mood),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
              ),
              icon: const Icon(Icons.pie_chart_outline),
              label: Text(l.viewAnalytics),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim reminder shown at the top of the dashboard while the signed-in user
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
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Color(sub.colorValue).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    sub.name.isNotEmpty ? sub.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Color(sub.colorValue),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
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
          const WalletMascot(size: 140, mood: MascotMood.happy),
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
