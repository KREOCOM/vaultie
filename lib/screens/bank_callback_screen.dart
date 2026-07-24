import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../content_theme.dart';
import '../i18n.dart';
import '../services/dashboard_store.dart';
import 'bank_connect_screen.dart';
import 'bank_import_screen.dart';
import 'preview/dashboard_preview.dart';

/// Finishes a bank connection that returned via a deep link.
///
/// When a bank hands off to its own app (SEB, Swedbank), the return doesn't
/// come back inside the ASWebAuthenticationSession — it fires the universal
/// link and (re)launches Vaultie with the authorisation `code`. The in-app
/// flow's awaiting future is gone by then, so this screen picks the code up and
/// runs the exact same completion the in-app flow does, then lands on the
/// dashboard. The bank label is recovered from the pending-connect marker set
/// before the browser opened.
class BankCallbackScreen extends StatefulWidget {
  const BankCallbackScreen({super.key, required this.code});

  final String code;

  @override
  State<BankCallbackScreen> createState() => _BankCallbackScreenState();
}

class _BankCallbackScreenState extends State<BankCallbackScreen> {
  bool _failed = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  Future<void> _finish() async {
    try {
      // Cold-launching via the bank's universal link can beat Firebase Auth's
      // session restore. finishBankAuth is an authenticated call, so firing it
      // before the user hydrates fails — and that burns the one-time code, forcing
      // a whole new consent. Wait (bounded) for the restored session first.
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 20));
      }
      final r = await completeBankConnection(
        widget.code,
        bank: DashboardStore.pendingConnect(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => r.dash != null
              ? DashboardPreview(data: r.dash!, deeper: r.deeper)
              : BankImportScreen(result: r.scan),
        ),
      );
    } catch (_) {
      await DashboardStore.setPendingConnect(null);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: contentTheme(Theme.of(context)),
      child: Scaffold(
        backgroundColor: cBg,
        body: SafeArea(
          child: Center(
            child: _failed ? _errorView() : _busyView(),
          ),
        ),
      ),
    );
  }

  Widget _busyView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/icon/app_icon.png',
                width: 72, height: 72, fit: BoxFit.cover),
          ),
          const SizedBox(height: 28),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            _isLt
                ? 'Užbaigiame banko prijungimą…'
                : 'Finishing your bank connection…',
            style: TextStyle(fontSize: 15.5, color: cInk, fontWeight: FontWeight.w600),
          ),
        ],
      );

  Widget _errorView() => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 44, color: cInk),
            const SizedBox(height: 16),
            Text(
              _isLt
                  ? 'Nepavyko užbaigti prijungimo. Bandyk prijungti banką iš naujo.'
                  : "We couldn't finish the connection. Please try connecting your bank again.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.5, color: cInk, height: 1.4),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const BankConnectScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: cAccent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(tr('Prijungti banką'),
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
}
