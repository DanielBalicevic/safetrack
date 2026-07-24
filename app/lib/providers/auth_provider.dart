import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth_service.dart';
import '../services/messaging_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Session state. Listens to Firebase auth changes and exposes the sign-in
/// actions to the screens.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? service})
      : _service = service ?? AuthService() {
    _sub = _service.authStateChanges.listen(_onAuthChanged);
  }

  final AuthService _service;
  late final StreamSubscription<User?> _sub;

  AuthStatus _status = AuthStatus.unknown;
  AuthStatus get status => _status;

  User? _user;
  User? get user => _user;

  bool _busy = false;
  bool get busy => _busy;

  void _onAuthChanged(User? user) {
    _user = user;
    _status =
        user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    notifyListeners();
  }

  // Actions return null on success, or a message to show to the user.

  Future<String?> signInWithEmail(String email, String password) {
    return _run(() => _service.signInWithEmail(email, password));
  }

  Future<String?> registerWithEmail(String email, String password) {
    return _run(() => _service.registerWithEmail(email, password));
  }

  Future<String?> signInWithGoogle() {
    return _run(() => _service.signInWithGoogle());
  }

  Future<String?> sendPasswordReset(String email) {
    return _run(() => _service.sendPasswordReset(email));
  }

  Future<void> signOut() async {
    final uid = _user?.uid;
    if (uid != null) await MessagingService.instance.clearToken(uid);
    await _service.signOut();
  }

  Future<String?> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
      return null;
    } on FirebaseAuthException catch (e) {
      return _messageFor(e);
    } on GoogleSignInException catch (e) {
      // The user closed the Google dialog.
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      return 'Could not sign in with Google. Please try again.';
    } catch (_) {
      return 'Something went wrong. Please try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'The password must be at least 6 characters.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Authentication error (${e.code}).';
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
