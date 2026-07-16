import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Thin wrapper around [FirebaseAuth] for email/password auth.
///
/// Keeps Firebase types out of the widgets and centralises the friendly
/// error mapping used by the auth screen.
class AuthService {
  AuthService([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  bool get isLoggedIn => _auth.currentUser != null;
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Creates an account and immediately fires off a verification email.
  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user?.sendEmailVerification();
    return cred;
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Signs in with Google via Firebase. Returns null if the user cancels the
  /// Google account picker. Google accounts arrive already email-verified.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user dismissed the picker
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Signs in with Apple via Firebase. Returns null if the user cancels the
  /// Apple sheet. A SHA-256-hashed nonce is sent to Apple and the raw nonce to
  /// Firebase, which prevents replay attacks. Apple only returns the user's
  /// name on the very first authorization, so we persist it as the displayName
  /// when present.
  Future<UserCredential?> signInWithApple() async {
    // Bind this attempt to a nonce: Apple receives the SHA-256 hash, Firebase
    // receives the raw value and re-hashes it to confirm they match.
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }

    // identityToken is nullable; without it the Firebase credential is invalid.
    final idToken = apple.identityToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'apple-no-identity-token',
        message: 'Apple did not return an identity token.',
      );
    }
    // Pass authorizationCode as accessToken. Without it the iOS firebase_auth
    // plugin serialises a null accessToken as NSNull, which corrupts the request
    // and makes Firebase reject it with "Invalid OAuth response from apple.com"
    // (flutterfire issue #3674). This is an iOS-only bug; the field must be set.
    final credential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
      accessToken: apple.authorizationCode,
    );
    final userCred = await _auth.signInWithCredential(credential);

    // Apple only returns the name on the very first authorization; persist it
    // as the displayName when we have one and Firebase doesn't already.
    final name = [apple.givenName, apple.familyName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ')
        .trim();
    final current = userCred.user?.displayName;
    if (name.isNotEmpty && (current == null || current.isEmpty)) {
      await userCred.user?.updateDisplayName(name);
    }
    return userCred;
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Sends a password-reset email. Firebase does not report whether the address
  /// is registered (no error for unknown emails), which avoids account
  /// enumeration — so the UI shows the same confirmation either way.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Re-fetches the user so [isEmailVerified] reflects a just-clicked link.
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> signOut() async {
    // Also clear the cached Google account so the picker shows next time.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {/* not signed in with Google — ignore */}
    await _auth.signOut();
  }

  /// Permanently deletes the signed-in account. Firebase may throw a
  /// [FirebaseAuthException] with code `requires-recent-login` if the session
  /// is too old — the caller should re-authenticate (see the methods below)
  /// and retry, or ask the user to sign in again.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    // Apple requires the app to REVOKE the user's token when the account is
    // deleted (App Store Guideline 5.1.1(v)). Re-authorize to get a fresh
    // authorization code, revoke it, then delete. If the user cancels the Apple
    // sheet we abort (throw) rather than delete without revoking.
    if (isAppleUser) {
      final code = await _reauthAppleForDelete(user);
      if (code == null) {
        throw FirebaseAuthException(
          code: 'apple-reauth-cancelled',
          message: 'Apple re-authentication was cancelled.',
        );
      }
      try {
        await _auth.revokeTokenWithAuthorizationCode(code);
      } catch (_) {
        // Best-effort: proceed with deletion even if revocation errors.
      }
      await _auth.currentUser?.delete();
      return;
    }
    await user.delete();
  }

  /// Re-authenticates the Apple user (fresh authorization) and returns the new
  /// authorization code for token revocation. Returns null if the user cancels.
  Future<String?> _reauthAppleForDelete(User user) async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
    final credential = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: rawNonce,
      accessToken: apple.authorizationCode,
    );
    await user.reauthenticateWithCredential(credential);
    return apple.authorizationCode;
  }

  /// True when the signed-in user authenticated via Google.
  bool get isGoogleUser =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'google.com') ??
      false;

  /// True when the signed-in user authenticated via Apple.
  bool get isAppleUser =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'apple.com') ??
      false;

  /// Re-authenticates an Apple user (required before sensitive actions like
  /// account deletion when the last sign-in is too old). Returns false if they
  /// cancel the Apple sheet.
  Future<bool> reauthenticateWithApple() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return false;
      rethrow;
    }
    // accessToken (authorizationCode) is required — see signInWithApple above.
    final credential = OAuthProvider('apple.com').credential(
      idToken: apple.identityToken,
      rawNonce: rawNonce,
      accessToken: apple.authorizationCode,
    );
    await user.reauthenticateWithCredential(credential);
    return true;
  }

  /// A cryptographically-random nonce, used to bind an Apple credential to this
  /// sign-in attempt.
  String _generateNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Re-authenticates a password user (required before sensitive actions like
  /// account deletion when the last sign-in is too old).
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final cred = EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(cred);
  }

  /// Re-authenticates a Google user. Returns false if they cancel the picker.
  Future<bool> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return false; // cancelled
    final googleAuth = await googleUser.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(cred);
    return true;
  }
}

/// Maps a [FirebaseAuthException] to a localized, user-facing message.
String authErrorMessage(FirebaseAuthException e, {required bool isLithuanian}) {
  switch (e.code) {
    case 'invalid-email':
      return isLithuanian
          ? 'Neteisingas el. pašto adresas.'
          : 'Invalid email address.';
    case 'user-disabled':
      return isLithuanian
          ? 'Ši paskyra užblokuota.'
          : 'This account has been disabled.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return isLithuanian
          ? 'Neteisingas el. paštas arba slaptažodis.'
          : 'Incorrect email or password.';
    case 'email-already-in-use':
      return isLithuanian
          ? 'Šis el. paštas jau naudojamas.'
          : 'This email is already in use.';
    case 'weak-password':
      return isLithuanian
          ? 'Slaptažodis per silpnas (min. 6 simboliai).'
          : 'Password is too weak (min. 6 characters).';
    case 'network-request-failed':
      return isLithuanian
          ? 'Nėra interneto ryšio. Bandykite dar kartą.'
          : 'No internet connection. Please try again.';
    case 'too-many-requests':
      return isLithuanian
          ? 'Per daug bandymų. Bandykite vėliau.'
          : 'Too many attempts. Try again later.';
    case 'operation-not-allowed':
      // Provider not enabled in the Firebase console (e.g. Apple/Google).
      return isLithuanian
          ? 'Šis prisijungimo būdas šiuo metu neįjungtas.'
          : 'This sign-in method is not enabled.';
    case 'account-exists-with-different-credential':
      return isLithuanian
          ? 'Šis el. paštas jau susietas su kitu prisijungimo būdu.'
          : 'This email is already linked to a different sign-in method.';
    case 'apple-no-identity-token':
      return isLithuanian
          ? 'Apple negrąžino tapatybės žetono. Bandykite dar kartą.'
          : 'Apple did not return an identity token. Please try again.';
    case 'requires-recent-login':
      return isLithuanian
          ? 'Saugumo sumetimais prisijunkite iš naujo ir bandykite dar kartą.'
          : 'For security, please sign in again, then try again.';
    default:
      return isLithuanian
          ? 'Įvyko klaida. Bandykite dar kartą.'
          : 'Something went wrong. Please try again.';
  }
}
