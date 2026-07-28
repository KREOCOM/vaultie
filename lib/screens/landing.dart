import 'package:flutter/material.dart';

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
Widget landingAfterAuth() {
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
  if (!PurchaseService.instance.isPremium) {
    return const OnbPaywall(next: BankConnectScreen());
  }
  final saved = DashboardStore.load();
  return saved != null
      ? DashboardPreview(data: saved)
      : const BankConnectScreen();
}
