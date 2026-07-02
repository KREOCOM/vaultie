import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_prefs.dart';
import '../main.dart';
import '../models/subscription.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/purchase_service.dart';
import '../widgets/subscription_avatar.dart';
import 'auth_screen.dart';
import 'paywall_screen.dart';

// Placeholder URLs — replace with the real pages before release.
const _kPrivacyUrl = 'https://vaultie.app/privacy';
const _kTermsUrl = 'https://vaultie.app/terms';
const _kRateUrl = 'https://apps.apple.com/app/id000000000';

const Color _gold = Color(0xFFFFD24A);

/// Account & app settings. Includes in-app account deletion (App Store
/// guideline 5.1.1(v)).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const route = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  bool _busy = false;
  late bool _notifications = AppPrefs.notificationsEnabled;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  String _userName() {
    final u = _auth.currentUser;
    final display = u?.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final email = u?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return _isLt ? 'Naudotojas' : 'User';
  }

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _onNotificationsChanged(bool value) async {
    await AppPrefs.setNotificationsEnabled(value);
    setState(() => _notifications = value);
    if (!value) {
      await NotificationService.instance.cancelAll();
    } else {
      // Re-schedule reminders for every current subscription.
      final isLt = _isLt;
      final subs =
          Hive.box<Subscription>(HiveBoxes.subscriptions).values.toList();
      for (final s in subs) {
        await NotificationService.instance
            .scheduleForSubscription(s, isLithuanian: isLt);
      }
    }
  }

  Future<void> _pickLanguage() async {
    final isLt = _isLt;
    final current = AppPrefs.locale.value?.languageCode;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in [
              ('', isLt ? 'Sistemos' : 'System'),
              ('lt', 'Lietuvių'),
              ('en', 'English'),
            ])
              ListTile(
                title: Text(opt.$2),
                trailing: (current ?? '') == opt.$1
                    ? const Icon(Icons.check, color: VaultieColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(opt.$1),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await AppPrefs.setLocale(choice.isEmpty ? null : Locale(choice));
  }

  Future<void> _pickCurrency() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in [('€', 'EUR (€)'), ('\$', 'USD (\$)')])
              ListTile(
                title: Text(opt.$2),
                trailing: AppPrefs.currency.value == opt.$1
                    ? const Icon(Icons.check, color: VaultieColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(opt.$1),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await AppPrefs.setCurrency(choice);
  }

  Future<void> _openUrl(String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isLt
              ? 'Nepavyko atidaryti nuorodos.'
              : 'Could not open the link.'),
        ),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final isLt = _isLt;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isLt ? 'Ištrinti paskyrą?' : 'Delete account?'),
        content: Text(
          isLt
              ? 'Tai visam laikui ištrins jūsų paskyrą ir visus duomenis. '
                  'Šio veiksmo anuliuoti negalima.'
              : 'This permanently deletes your account and all your data. '
                  'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isLt ? 'Atšaukti' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: VaultieColors.danger),
            child: Text(isLt ? 'Ištrinti' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteAccount();
  }

  /// Clears a Hive box, opening it first if it isn't already open.
  Future<void> _wipeBox(String name) async {
    final box =
        Hive.isBoxOpen(name) ? Hive.box(name) : await Hive.openBox(name);
    await box.clear();
  }

  Future<void> _deleteAccount() async {
    final isLt = _isLt;
    setState(() => _busy = true);
    try {
      await _auth.deleteAccount();
      await _wipeBox(HiveBoxes.subscriptions);
      await _wipeBox(HiveBoxes.cancellations);
      await _wipeBox(HiveBoxes.settings);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'requires-recent-login') {
        await _auth.signOut();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isLt
                ? 'Saugumo sumetimais prisijunkite iš naujo ir bandykite ištrinti dar kartą.'
                : 'For security, please sign in again and retry deleting your account.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authErrorMessage(e, isLithuanian: isLt)),
            backgroundColor: VaultieColors.danger,
          ),
        );
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    final name = _userName();
    final email = _auth.currentUser?.email ?? '';
    final isPro = PurchaseService.instance.isPremium;
    final localeCode = AppPrefs.locale.value?.languageCode;
    final langLabel = localeCode == 'lt'
        ? 'Lietuvių'
        : localeCode == 'en'
            ? 'English'
            : (isLt ? 'Sistemos' : 'System');
    final currencyLabel =
        AppPrefs.currency.value == '\$' ? 'USD (\$)' : 'EUR (€)';

    return Scaffold(
      appBar: AppBar(title: Text(isLt ? 'Nustatymai' : 'Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _profileCard(name, email, isPro, isLt),
            const SizedBox(height: 16),
            _proCard(isLt),
            const SizedBox(height: 24),
            _sectionLabel(isLt ? 'Programa' : 'App'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined,
                        color: VaultieColors.primary),
                    title: Text(isLt ? 'Pranešimai' : 'Notifications'),
                    value: _notifications,
                    activeThumbColor: VaultieColors.primary,
                    onChanged: _busy ? null : _onNotificationsChanged,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.language,
                        color: VaultieColors.primary),
                    title: Text(isLt ? 'Kalba' : 'Language'),
                    trailing: _trailing(langLabel),
                    onTap: _pickLanguage,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading:
                        const Icon(Icons.euro, color: VaultieColors.primary),
                    title: Text(isLt ? 'Valiuta' : 'Currency'),
                    trailing: _trailing(currencyLabel),
                    onTap: _pickCurrency,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel(isLt ? 'Informacija' : 'Info'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined,
                        color: VaultieColors.primary),
                    title: Text(isLt ? 'Privatumo politika' : 'Privacy Policy'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(_kPrivacyUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.description_outlined,
                        color: VaultieColors.primary),
                    title: Text(isLt ? 'Naudojimo sąlygos' : 'Terms of Use'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(_kTermsUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.star_outline,
                        color: VaultieColors.primary),
                    title: Text(isLt ? 'Įvertinti programą' : 'Rate the app'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(_kRateUrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout),
              label: Text(isLt ? 'Atsijungti' : 'Sign out'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: VaultieColors.danger,
                side: const BorderSide(color: VaultieColors.danger),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: VaultieColors.danger),
                    )
                  : const Icon(Icons.delete_forever),
              label: Text(isLt ? 'Ištrinti paskyrą' : 'Delete account'),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Vaultie v1.0.0',
                style: TextStyle(color: VaultieColors.subtle, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trailing(String value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: VaultieColors.subtle)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: VaultieColors.subtle),
        ],
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
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

  Widget _profileCard(String name, String email, bool isPro, bool isLt) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VaultieColors.primary, // #174E35
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SubscriptionAvatar(name: name, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isPro ? _gold : Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isPro ? 'Pro' : (isLt ? 'Nemokama' : 'Free'),
              style: TextStyle(
                color: isPro ? VaultieColors.primaryDark : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proCard(bool isLt) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [VaultieColors.primaryLight, VaultieColors.primary],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('💎 Vaultie Pro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  isLt ? 'JAU GREITAI' : 'COMING SOON',
                  style: const TextStyle(
                    color: VaultieColors.primaryDark,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isLt
                ? 'Neribotos prenumeratos, išplėstinė analitika ir daugiau.'
                : 'Unlimited subscriptions, advanced analytics and more.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: VaultieColors.primary,
                elevation: 0,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              ),
              child: Text(isLt ? 'Sužinoti daugiau' : 'Learn more'),
            ),
          ),
        ],
      ),
    );
  }
}
