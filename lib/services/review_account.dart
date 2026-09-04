import 'package:firebase_auth/firebase_auth.dart';

/// The single account App Review signs in with.
///
/// Apple requires "a valid demo account username and password" or a
/// "fully-featured demo mode" for anything behind a sign-in (Guideline 2.1). A
/// reviewer cannot satisfy Vaultie's real path: connecting a bank needs an
/// account at a European bank and that bank's own two-factor step, neither of
/// which we can hand over. Without this they would reach the bank list, be
/// unable to go further, and reject the build as incomplete — costing a review
/// cycle.
///
/// So this one address, and only this one, opens straight into the sample month
/// the onboarding already uses: every screen populated, nothing connected.
///
/// Deliberately narrow: a single hard-coded address, matched exactly. It grants
/// no privileges beyond seeing sample data — no bank access, no real money, no
/// server-side power. The Cloud Functions still check the entitlement and the
/// signed-in uid the same way they do for anyone else.
class ReviewAccount {
  ReviewAccount._();

  /// Create this account in Firebase Authentication (email/password) and put the
  /// credentials in the App Review notes. The domain does not need to exist —
  /// nothing is ever sent to it, and [isSignedIn] below is what makes the
  /// unverified address usable.
  static const email = 'appreview@vaultieapp.com';

  /// True when the reviewer's account is the one signed in.
  static bool get isSignedIn {
    final e = FirebaseAuth.instance.currentUser?.email;
    return e != null && e.toLowerCase().trim() == email;
  }
}
