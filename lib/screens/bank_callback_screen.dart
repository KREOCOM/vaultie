import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../content_theme.dart';
import '../i18n.dart';
import '../services/dashboard_store.dart';
import 'bank_connect_screen.dart';
import 'bank_how_it_works.dart';
import 'bank_import_screen.dart';
import 'onb_notifications.dart';
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
  const BankCallbackScreen({super.key, required this.code, required this.state});

  final String code;
  // The `state` Enable Banking echoed back on this same callback — the
  // server checks it against what THIS device's own startBankAuth issued
  // before exchanging `code` (2026-08-16 fix, see completeBankConnection's
  // own doc).
  final String state;

  @override
  State<BankCallbackScreen> createState() => _BankCallbackScreenState();
}

class _BankCallbackScreenState extends State<BankCallbackScreen> {
  bool _failed = false;

  bool get _isLt => Localizations.localeOf(context).languageCode == 'lt';

  // A cycling "we're working" progress while the scan runs, so a multi-bank,
  // 30-60s scan never reads as frozen — a static "we'll open your overview
  // soon" was all this screen ever showed while completeBankConnection() was
  // still genuinely working, which is indistinguishable from a hang to
  // someone watching it. Same stages bank_connect_screen.dart used to cycle
  // through before both completion paths were unified onto this one screen.
  Timer? _stageTimer;
  int _stage = 0;
  static const _stagesLt = [
    'Baigiame prijungimą…',
    'Traukiame tavo sandorius…',
    'Analizuojame išlaidas, pajamas ir sąskaitas…',
    'Beveik baigėm…',
  ];
  static const _stagesEn = [
    'Finishing the connection…',
    'Fetching your transactions…',
    'Analysing spending, income and bills…',
    'Almost done…',
  ];

  @override
  void initState() {
    super.initState();
    _stageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        if (_stage < 3) _stage++;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    super.dispose();
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
        widget.state,
        bank: DashboardStore.pendingConnect(),
      );
      if (!mounted) return;
      // Clears the stack rather than replacing one route.
      //
      // On a cold launch this screen sits on top of the splash, which is now
      // inert — its timer has already fired and stood down (see splash_screen).
      // pushReplacement would leave that dead route underneath, giving the
      // dashboard a back arrow to nowhere.
      final landing = r.dash != null
          ? DashboardPreview(data: r.dash!, deeper: r.deeper)
          : BankImportScreen(result: r.scan);
      // The one moment worth spending the OS notification prompt on: the scan
      // has just found this person's real payments, so the reminders being
      // offered are about something they can already see. Asked once ever.
      final next = AppPrefs.notifIntroShown
          ? landing
          : OnbNotifications(next: landing);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
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

  /// The connected bank's logo with an "approved" tick on its corner, falling
  /// back to its initial and then to a plain tick.
  ///
  /// Enable Banking ships a logo for the banks people actually use, but not for
  /// every smaller ASPSP — and the logo is a network image, so it can also just
  /// fail. Each step down still confirms the connection; none of them can leave
  /// the screen without an answer on it.
  Widget _bankMark() {
    final logo = DashboardStore.pendingConnectLogo();
    final name = DashboardStore.pendingConnect() ?? '';
    final initial =
        name.isNotEmpty ? name.characters.first.toUpperCase() : null;

    Widget plate(Widget child) => Container(
          width: 78,
          height: 78,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            // White, because a bank's mark is drawn for white and several of
            // them disappear entirely on a dark ground.
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Center(child: child),
        );

    Widget base;
    if (logo != null && logo.isNotEmpty) {
      base = plate(Image.network(
        logo,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => initial != null
            ? Text(initial,
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF10182F)))
            : const Icon(Icons.account_balance_rounded,
                size: 32, color: Color(0xFF10182F)),
      ));
    } else if (initial != null) {
      base = plate(Text(initial,
          style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Color(0xFF10182F))));
    } else {
      base = Container(
        width: 74,
        height: 74,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
            color: Color(0x2634D399), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded,
            size: 38, color: Color(0xFF34D399)),
      );
      return base; // already a tick — don't badge a tick with a tick
    }

    return SizedBox(
      width: 92,
      height: 86,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Align(alignment: Alignment.topCenter, child: base),
          Positioned(
            right: 2,
            bottom: 0,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF34D399),
                shape: BoxShape.circle,
                border: Border.all(color: cxBg, width: 3),
              ),
              child: const Icon(Icons.check_rounded,
                  size: 16, color: Color(0xFF06301F)),
            ),
          ),
        ],
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
            // The BANK's own mark, not a generic tick.
            //
            // Coming back from a bank's own login, the thing that has to land
            // first is "yes — that bank, the one you just approved". A green
            // check says something worked; it does not say what. The mark is
            // already on the phone from the redirect screen, so this costs
            // nothing, and the small tick riding on its corner keeps the
            // "approved" reading it used to carry alone.
            _bankMark(),
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(
                (_isLt ? _stagesLt : _stagesEn)[_stage.clamp(0, 3)],
                key: ValueKey(_stage),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9FB0D8)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLt ? 'Neuždaryk programėlės.' : 'Keep the app open.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF7F8DB0)),
            ),
          ],
        ),
      );

  Widget _errorView() => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: cxInk),
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
