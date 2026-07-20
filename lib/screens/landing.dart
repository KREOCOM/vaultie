import 'package:flutter/material.dart';

import '../services/dashboard_store.dart';
import '../services/purchase_service.dart';
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
