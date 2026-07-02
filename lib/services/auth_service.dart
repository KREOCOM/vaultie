import 'package:firebase_auth/firebase_auth.dart';

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

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Re-fetches the user so [isEmailVerified] reflects a just-clicked link.
  Future<void> reloadUser() async {
    await _auth.currentUser?.reload();
  }

  Future<void> signOut() => _auth.signOut();

  /// Permanently deletes the signed-in account. Firebase may throw a
  /// [FirebaseAuthException] with code `requires-recent-login` if the session
  /// is too old — the caller should then ask the user to sign in again.
  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
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
    default:
      return isLithuanian
          ? 'Įvyko klaida. Bandykite dar kartą.'
          : 'Something went wrong. Please try again.';
  }
}
