import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../main.dart' show HiveBoxes;
import '../services/dashboard_store.dart';
import '../services/purchase_service.dart';
import '../services/review_account.dart';
import 'bank_connect_screen.dart';
import 'onb_paywall.dart';
import 'preview/dashboard_preview.dart';

/// Where a user lands after signing in: the paywall without an active plan,
/// otherwise the saved dashboard (persisted from the last bank scan) if there
/// is one, else the bank flow to connect.
///
/// This used to live in onboarding_choice_screen.dart, next to a first-run
/// "How would you like to start?" screen in the old green identity. That screen
/// is gone — the intro chain's own "Prijungti banką" screen makes the same
/// pitch in the current identity — so the function moved somewhere its name
/// still describes the file.
Future<Widget> landingAfterAuth() async {
  // App Review lands here, on the sample month, before anything else is checked.
  //
  // Above the paywall on purpose: making a reviewer complete a StoreKit sandbox
  // purchase before they can see the product is an extra step that can fail on
  // their side, and a paywall they cannot get past is one of the most common
  // reasons a first submission comes back. Below it there is nothing they could
  // reach anyway — the real dashboard needs a European bank account.
  if (ReviewAccount.isSignedIn) {
    // The REAL dashboard on the bundled sample month — not `demo: true`.
    //
    // `demo: true` is the onboarding showcase: it drives itself, paints a
    // pointer over the screen and locks every tab outside its script. A reviewer
    // handed that would watch the app operate itself and be unable to open half
    // of it — failing the very sentence in Guideline 2.1 this account exists to
    // satisfy ("ensure the demo mode exhibits your app's full features and
    // functionality").
    //
    // With no `data` and no `demo`, DashboardPreview falls back to the sample
    // payload compiled into the app and behaves exactly as it does for a real
    // user: every tab, every sheet, nothing scripted.
    return const DashboardPreview();
  }
  // Vaultie is subscription-only, so the entitlement — not the presence of
  // local data — decides who gets in. This used to key off the saved dashboard
  // alone, which meant connecting a bank once bought permanent free access:
  // the paywall was skipped for anyone who had data, including after their
  // subscription lapsed.
  //
  // confirmPremium(), not the plain isPremium getter: the on-device
  // RevenueCat SDK reflects the PHONE's own StoreKit transactions, not
  // necessarily this signed-in account's — a device that ever held a real
  // entitlement can make a brand-new, never-paid account read as premium.
  // See PurchaseService.confirmPremium's own doc for the full story and why
  // this has to be asked right here, not cached earlier.
  if (!await PurchaseService.instance.confirmPremium()) {
    return const OnbPaywall(next: BankConnectScreen());
  }
  // 2026-08-20: was gated on the saved blob's mere presence. That blob and
  // the actual bank connections it came from (`bankCount`) are written
  // together by completeBankConnection() but nothing enforces they can
  // never drift apart — someone who paid, was sent to connect a bank, and
  // quit before finishing, must land back on BankConnectScreen next time,
  // not on a dashboard built from a leftover/partial blob with zero real
  // connections behind it.
  final saved = DashboardStore.load();
  final bankCount = DashboardStore.bankCount;
  if (saved != null && bankCount > 0) return DashboardPreview(data: saved);
  // TEMP DIAGNOSTIC (2026-09-06) — a real, reproducible bug report: signing
  // out then back in with the SAME account routes to BankConnectScreen
  // instead of the dashboard, even on a brand-new install/account. Every
  // code path read so far looks correct on its own, so this shows the exact
  // values landingAfterAuth actually saw ON SCREEN (a TestFlight build has
  // no attached debugger to read debugPrint from) instead of guessing
  // further. Remove this banner once the real cause is found.
  final diag = 'saved=${saved != null} bankCount=$bankCount '
      "rawDash=${saved == null ? 'null' : 'present'} "
      'dataOwner=${Hive.box(HiveBoxes.settings).get('dataOwnerUid')} '
      'uid=${FirebaseAuth.instance.currentUser?.uid} '
      'rawBanksKey=${DashboardStore.debugRawBanks()}';
  return _DiagBanner(text: diag, child: const BankConnectScreen());
}

class _DiagBanner extends StatelessWidget {
  const _DiagBanner({required this.text, required this.child});
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                color: Colors.red.withValues(alpha: 0.92),
                padding: const EdgeInsets.all(8),
                child: SelectableText(text,
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
          ),
        ],
      );
}
