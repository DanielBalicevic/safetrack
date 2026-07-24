import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around Firebase Auth and Google Sign-In.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  bool _googleReady = false;

  // iOS OAuth client ID (CLIENT_ID in GoogleService-Info.plist).
  static const _iosGoogleClientId =
      '167177354370-pcoe6msv8ui96eivpg2d8bmqdb73mc2u.apps.googleusercontent.com';

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> registerWithEmail(String email, String password) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// google_sign_in 7.x must be initialized once before [authenticate].
  Future<UserCredential> signInWithGoogle() async {
    if (!_googleReady) {
      await GoogleSignIn.instance.initialize(clientId: _iosGoogleClientId);
      _googleReady = true;
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final idToken = googleUser.authentication.idToken;

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    // Sign out of Google too, so the next sign-in asks for the account again.
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {
      // A Google sign-out failure must not block the Firebase sign-out.
    }
    await _auth.signOut();
  }
}
