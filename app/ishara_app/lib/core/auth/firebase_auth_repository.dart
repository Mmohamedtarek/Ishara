import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:ishara_app/core/auth/auth_repository.dart';

/// Firebase Authentication's error codes → the screen's problems. Never
/// shown raw (step 10b brief).
AuthProblem authProblemFor(String code) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'user-disabled' ||
  'INVALID_LOGIN_CREDENTIALS' => AuthProblem.invalidCredentials,
  'email-already-in-use' => AuthProblem.emailInUse,
  'weak-password' ||
  'password-does-not-meet-requirements' => AuthProblem.weakPassword,
  'invalid-email' => AuthProblem.invalidEmail,
  'network-request-failed' => AuthProblem.network,
  'too-many-requests' => AuthProblem.tooManyRequests,
  'requires-recent-login' => AuthProblem.requiresRecentLogin,
  _ => AuthProblem.unknown,
};

/// Email + password accounts on Firebase Authentication (Q-B2). The session
/// survives restarts (Firebase keeps it; no "Remember me").
class FirebaseAuthRepository implements AuthRepository {
  /// [language]: the app language, for the verification and reset emails.
  new(this._auth, {required this._language});

  final fb.FirebaseAuth _auth;
  final String Function() _language;

  static AuthUser? _map(fb.User? u) => u == null
      ? null
      : AuthUser(
          id: u.uid,
          email: u.email ?? '',
          name: u.displayName ?? '',
          emailVerified: u.emailVerified,
        );

  /// Runs [call]; Firebase errors become [AuthFailure].
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthFailure(authProblemFor(e.code), cause: e.code);
    } on fb.FirebaseException catch (e) {
      throw AuthFailure(
        e.code == 'network-request-failed' || e.code == 'unavailable'
            ? AuthProblem.network
            : AuthProblem.unknown,
        cause: e.code,
      );
    }
  }

  fb.User _signedIn() {
    final u = _auth.currentUser;
    if (u == null) throw const AuthFailure(AuthProblem.unknown);
    return u;
  }

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> get userChanges => _auth.userChanges().map(_map);

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      _guard(() async {
        final c = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        return _map(c.user)!;
      });

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    final c = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final u = c.user!;
    // the account exists from here: the name is best effort (offline it
    // stays empty until the profile is written), never an error that would
    // make "Create" fail and a retry hit "email already in use"
    try {
      await u.updateDisplayName(name.trim());
      await u.reload();
    } on fb.FirebaseException {
      // signed in all the same
    }
    final fresh = _auth.currentUser ?? u;
    // the verification email goes at once (S6-1); a failure here leaves
    // "Resend" in Settings
    try {
      await _auth.setLanguageCode(_language());
      await fresh.sendEmailVerification();
    } on fb.FirebaseException {
      // shown as "not verified" with Resend
    }
    return _map(fresh)!;
  });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() async {
    await _auth.setLanguageCode(_language());
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      // the screen never reveals which accounts exist
      if (e.code != 'user-not-found') rethrow;
    }
  });

  @override
  Future<void> sendEmailVerification() => _guard(() async {
    await _auth.setLanguageCode(_language());
    await _signedIn().sendEmailVerification();
  });

  @override
  Future<AuthUser?> refreshUser() => _guard(() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    await u.reload();
    final fresh = _auth.currentUser;
    // a new token carries email_verified for the security rules
    await fresh?.getIdToken(true);
    return _map(fresh);
  });

  @override
  Future<void> reauthenticate(String password) => _guard(() async {
    final u = _signedIn();
    await u.reauthenticateWithCredential(
      fb.EmailAuthProvider.credential(email: u.email!, password: password),
    );
  });

  @override
  Future<void> deleteUser() => _guard(() => _signedIn().delete());

  @override
  Future<void> signOut() => _auth.signOut();
}
