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

  /// Sync starts only after the email is verified (Q-B3, step 10).
  final bool emailVerified;
}

/// Why an auth call failed. One message per kind on screen.
enum AuthProblem {
  /// Wrong email or password (one message for both, as Firebase now
  /// answers, so the screen doesn't reveal which accounts exist).
  invalidCredentials,

  /// Create account: the email already has an account.
  emailInUse,

  /// No connection.
  network,

  /// Too many attempts; try again later.
  tooManyRequests,

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
/// Firebase project). Step 6 uses [FakeAuthRepository] (S6-1); step 10 adds
/// the Firebase one.
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

  Future<void> signOut();
}

/// On the phone only (no network): accounts live in memory for this run.
/// [offline] and [failNext] let tests and the developer screens show every
/// error state.
class FakeAuthRepository implements AuthRepository {
  new({this.delay = const Duration(milliseconds: 600)});

  /// Simulated network time, so the loading state is visible.
  final Duration delay;

  /// Every call fails with [AuthProblem.network].
  bool offline = false;

  /// The next call fails with this problem.
  AuthProblem? failNext;

  final _accounts = <String, ({String password, AuthUser user})>{};
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  /// Emails a reset was "sent" to (tests).
  final resetsSent = <String>[];

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
      id: 'local-${_accounts.length + 1}',
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
  Future<void> signOut() async => _set(null);

  Future<void> dispose() => _changes.close();
}

/// Form checks on the Login / Create account screen (prototype submit
/// handler, email only: Q-B2). Each is true when the value is not fine.
abstract final class AuthValidation {
  /// Prototype: `!nm` → errName.
  static bool nameMissing(String name) => name.trim().isEmpty;

  /// Prototype: `!id` → errId.
  static bool emailMissing(String email) => email.trim().isEmpty;

  /// Prototype email pattern `^[^\s@]+@[^\s@]+\.[^\s@]+$` (the phone-number
  /// pattern is gone with Q-B2).
  static bool emailMalformed(String email) =>
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

  /// Prototype: `pw.length < 8` → errPw.
  static bool passwordTooShort(String password) => password.length < 8;
}
