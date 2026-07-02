import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';

/// Account settings: shows the signed-in email, lets the user sign out, and —
/// as required by App Store guideline 5.1.1(v) — permanently delete their
/// account (with a confirmation dialog).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const route = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  bool _busy = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
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

  /// Clears a Hive box, opening it first if it isn't already open (all boxes
  /// are opened in main.dart, but this stays safe against an unopened box).
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
      // Wipe local data so a future account starts clean. Guarded so a box
      // that (for any reason) isn't open yet is opened first rather than
      // throwing "box not found".
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
        // Firebase requires a fresh login before deletion; sign out and ask
        // the user to sign in again, then retry.
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

  @override
  Widget build(BuildContext context) {
    final isLt = _isLt;
    final email = _auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(isLt ? 'Nustatymai' : 'Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Account card.
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_circle_outlined,
                    color: VaultieColors.primary),
                title: Text(isLt ? 'Paskyra' : 'Account'),
                subtitle: Text(email),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: VaultieColors.primary),
                title: Text(isLt ? 'Atsijungti' : 'Sign out'),
                onTap: _busy ? null : _signOut,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isLt ? 'Pavojinga zona' : 'Danger zone',
              style: const TextStyle(
                color: VaultieColors.subtle,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: VaultieColors.danger,
                side: const BorderSide(color: VaultieColors.danger),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VaultieColors.danger,
                      ),
                    )
                  : const Icon(Icons.delete_forever),
              label: Text(isLt ? 'Ištrinti paskyrą' : 'Delete account'),
            ),
          ],
        ),
      ),
    );
  }
}
