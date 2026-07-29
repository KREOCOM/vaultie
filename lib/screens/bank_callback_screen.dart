import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../content_theme.dart';
import '../i18n.dart';
import '../services/dashboard_store.dart';
import 'bank_connect_screen.dart';
import 'bank_how_it_works.dart';
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
      // Clears the stack rather than replacing one route.
      //
      // On a cold launch this screen sits on top of the splash, which is now
      // inert — its timer has already fired and stood down (see splash_screen).
      // pushReplacement would leave that dead route underneath, giving the
      // dashboard a back arrow to nowhere.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => r.dash != null
              ? DashboardPreview(data: r.dash!, deeper: r.deeper)
              : BankImportScreen(result: r.scan),
        ),
        (route) => false,
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
        // Deep navy, matching the two screens on either side of this one: the
        // hand-off to the bank before it and the bank's own page after. A white
        // screen in the middle of that made the return feel like a different app.
        backgroundColor: cxBg,
        body: SafeArea(
          child: Center(
            child: _failed ? _errorView() : _busyView(),
          ),
        ),
      ),
    );
  }

  /// What the person sees on returning from the bank.
  ///
  /// It used to be the app icon and a spinner — which says the app is alive, but
  /// not that anything was ACHIEVED. Coming back from approving access, the
  /// first thing they need is confirmation that it worked, then what is being
  /// done with it, then how long. A logo cannot say any of that.
  Widget _busyView() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: Color(0x2634D399), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded,
                  size: 38, color: Color(0xFF34D399)),
            ),
            const SizedBox(height: 22),
            Text(
              _isLt ? 'Prieiga patvirtinta' : 'Access approved',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: cxInk),
            ),
            const SizedBox(height: 10),
            Text(
              _isLt
                  ? 'Užbaigiame prijungimą ir tvarkome tavo operacijas — ieškome pasikartojančių mokėjimų, prenumeratų ir kategorijų.'
                  : "We're finishing the connection and sorting your transactions — looking for recurring payments, subscriptions and categories.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14.5, height: 1.5, color: cxSubtle),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.6, color: Color(0xFF9FB0D8)),
            ),
            const SizedBox(height: 16),
            Text(
              _isLt
                  ? 'Netrukus atidarysime tavo apžvalgą. Neuždaryk programėlės.'
                  : "We'll open your dashboard shortly. Keep the app open.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xFF7F8DB0)),
            ),
          ],
        ),
      );

  Widget _errorView() => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 44, color: cxInk),
            const SizedBox(height: 16),
            Text(
              _isLt
                  ? 'Nepavyko užbaigti prijungimo. Bandyk prijungti banką iš naujo.'
                  : "We couldn't finish the connection. Please try connecting your bank again.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15.5, color: cxInk, height: 1.4),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              // Same reasoning as the success path: don't strand the retry on
              // top of a dead splash route.
              onTap: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const BankConnectScreen()),
                (route) => false,
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
