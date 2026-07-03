import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
    await _auth.currentUser?.delete();
  }

  /// True when the signed-in user authenticated via Google.
  bool get isGoogleUser =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'google.com') ??
      false;

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
