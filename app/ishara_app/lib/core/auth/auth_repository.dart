import 'dart:async';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';

/// A signed-in account (email + password only, Q-B2).
@immutable
class AuthUser {
  const new({
    required this.id,
    required this.email,
    required this.name,
    this.emailVerified = false,
  });

  final String id;
  final String email;
  final String name;

  /// Sync starts only after the email is verified (Q-B3).
  final bool emailVerified;

  AuthUser copyWith({bool? emailVerified}) => AuthUser(
    id: id,
    email: email,
    name: name,
    emailVerified: emailVerified ?? this.emailVerified,
  );

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.name == name &&
      other.emailVerified == emailVerified;

  @override
  int get hashCode => Object.hash(id, email, name, emailVerified);
}

/// Why an auth call failed. One message per kind on screen.
enum AuthProblem {
  /// Wrong email or password (one message for both, as Firebase now
  /// answers, so the screen doesn't reveal which accounts exist).
  invalidCredentials,

  /// Create account: the email already has an account.
  emailInUse,

  /// Create account: the password is too weak for the server (shown as the
  /// password field's "at least 8 characters").
  weakPassword,

  /// The server rejected the email's form (shown as the email field's
  /// "Enter a valid email address").
  invalidEmail,

  /// Deleting the account: the sign-in is too old; the password is asked
  /// again (Q-B1).
  requiresRecentLogin,

  /// No connection.
  network,

  /// Too many attempts; try again later.
  tooManyRequests,

  /// No accounts this run: Firebase couldn't start (the app works as a
  /// guest).
  unavailable,

  /// Anything else.
  unknown,
}

final class AuthFailure extends Failure {
  const new(this.problem, {super.cause}) : super('auth call failed');

  final AuthProblem problem;

  @override
  String get kind => 'auth_${problem.name}';
}

/// Every account call goes through this interface (CLAUDE.md: Firebase sits
/// behind a repository with a local fake; the app and all tests run with no
/// Firebase project): [FakeAuthRepository] (S6-1) or
/// `FirebaseAuthRepository` (step 10b, `--dart-define=BACKEND`).
abstract interface class AuthRepository {
  /// The signed-in user (null = guest or signed out), and its changes.
  AuthUser? get currentUser;
  Stream<AuthUser?> get userChanges;

  /// Throws [AuthFailure].
  Future<AuthUser> signIn({required String email, required String password});

  /// Throws [AuthFailure].
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  });

  /// Sends a password-reset email. Succeeds for unknown emails too (the
  /// screen must not reveal which accounts exist). Throws [AuthFailure] for
  /// network problems.
  Future<void> sendPasswordReset(String email);

  /// Sends the verification email to the signed-in user (S6-1, Q-B3).
  /// Throws [AuthFailure].
  Future<void> sendEmailVerification();

  /// Asks the server for the signed-in user again ("I've verified"), with a
  /// fresh token so the security rules see a verified email at once.
  /// Returns the user (null when signed out). Throws [AuthFailure].
  Future<AuthUser?> refreshUser();

  /// Signs in again with [password] (before deleting the account, when the
  /// server asks for a recent sign-in). Throws [AuthFailure].
  Future<void> reauthenticate(String password);

  /// Deletes the signed-in account on the server (its data must be deleted
  /// first, Q-B1). Throws [AuthFailure] ([AuthProblem.requiresRecentLogin]
  /// when the sign-in is too old).
  Future<void> deleteUser();

  Future<void> signOut();
}

/// Accounts are off this run: Firebase was asked for but couldn't start
/// (`Backend.unavailable`). Nobody is ever signed in; every account call
/// says [AuthProblem.unavailable]. No in-memory accounts (user 2026-11-27):
/// they would vanish at restart and never sync.
class UnavailableAuthRepository implements AuthRepository {
  const new();

  static const _off = AuthFailure(AuthProblem.unavailable);

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> get userChanges => const Stream.empty();

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      Future.error(_off);

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) => Future.error(_off);

  @override
  Future<void> sendPasswordReset(String email) => Future.error(_off);

  @override
  Future<void> sendEmailVerification() => Future.error(_off);

  @override
  Future<AuthUser?> refreshUser() async => null;

  @override
  Future<void> reauthenticate(String password) => Future.error(_off);

  @override
  Future<void> deleteUser() => Future.error(_off);

  @override
  Future<void> signOut() async {}
}

/// On the phone only (no network): accounts live in memory for this run.
/// [offline] and [failNext] let tests and the developer screens show every
/// error state.
class FakeAuthRepository implements AuthRepository {
  new({this.delay = const Duration(milliseconds: 600)});

  /// Simulated network time, so the loading state is visible (tests may
  /// change it between calls).
  Duration delay;

  /// Every call fails with [AuthProblem.network].
  bool offline = false;

  /// The next call fails with this problem.
  AuthProblem? failNext;

  final _accounts = <String, ({String password, AuthUser user})>{};

  /// Ids are never reused, even after a deletion.
  int _lastId = 0;
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  /// Emails a reset was "sent" to (tests).
  final resetsSent = <String>[];

  /// Emails a verification was "sent" to (tests).
  final verificationsSent = <String>[];

  /// The next [deleteUser] asks for a recent sign-in (tests).
  bool requireRecentLogin = false;

  /// The user opened the verification link (tests, developer screens): the
  /// next [refreshUser] sees it.
  void verify(String email) {
    final key = email.trim().toLowerCase();
    final a = _accounts[key];
    if (a == null) return;
    _accounts[key] = (
      password: a.password,
      user: a.user.copyWith(emailVerified: true),
    );
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get userChanges => _changes.stream;

  Future<void> _call() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final f = failNext;
    failNext = null;
    if (offline) throw const AuthFailure(AuthProblem.network);
    if (f != null) throw AuthFailure(f);
  }

  void _set(AuthUser? u) {
    _user = u;
    _changes.add(u);
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await _call();
    final a = _accounts[email.trim().toLowerCase()];
    if (a == null || a.password != password) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
    _set(a.user);
    return a.user;
  }

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    await _call();
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw const AuthFailure(AuthProblem.emailInUse);
    }
    final user = AuthUser(
      id: 'local-${++_lastId}',
      email: key,
      name: name.trim(),
    );
    _accounts[key] = (password: password, user: user);
    _set(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _call();
    resetsSent.add(email.trim().toLowerCase());
  }

  @override
  Future<void> sendEmailVerification() async {
    await _call();
    final u = _user;
    if (u != null) verificationsSent.add(u.email);
  }

  @override
  Future<AuthUser?> refreshUser() async {
    await _call();
    final u = _user;
    if (u == null) return null;
    final fresh = _accounts[u.email]?.user;
    if (fresh == null) {
      _set(null); // deleted elsewhere
      return null;
    }
    if (fresh != u) _set(fresh);
    return fresh;
  }

  @override
  Future<void> reauthenticate(String password) async {
    await _call();
    final u = _user;
    if (u == null || _accounts[u.email]?.password != password) {
      throw const AuthFailure(AuthProblem.invalidCredentials);
    }
    requireRecentLogin = false;
  }

  @override
  Future<void> deleteUser() async {
    await _call();
    if (requireRecentLogin) {
      throw const AuthFailure(AuthProblem.requiresRecentLogin);
    }
    final u = _user;
    if (u == null) return;
    _accounts.remove(u.email);
    _set(null);
  }

  @override
  Future<void> signOut() async => _set(null);

  Future<void> dispose() => _changes.close();
}

/// Form checks on the Login / Create account screen (prototype submit
/// handler, email only: Q-B2). Each is true when the value is not fine.
abstract final class AuthValidation {
  /// Prototype: `!nm` → errName.
  static bool nameMissing(String name) => name.trim().isEmpty;

  /// The account's name is at most this long (the security rules check
  /// the profile's `displayName` ≤ 100, step 10b).
  static const nameMax = 100;

  static bool nameTooLong(String name) => name.trim().length > nameMax;

  /// Prototype: `!id` → errId.
  static bool emailMissing(String email) => email.trim().isEmpty;

  /// Prototype email pattern `^[^\s@]+@[^\s@]+\.[^\s@]+$` (the phone-number
  /// pattern is gone with Q-B2).
  static bool emailMalformed(String email) =>
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

  /// Prototype: `pw.length < 8` → errPw.
  static bool passwordTooShort(String password) => password.length < 8;
}
