import 'dart:convert';

import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/sync/remote_store.dart';
import 'package:meta/meta.dart';

/// How a deletion run ended.
enum DeletionResult {
  /// The account and the phone's data are gone.
  done,

  /// The server wants a recent sign-in: ask the password, then
  /// [AccountDeletion.reauthenticateAndResume].
  needsPassword,

  /// Offline or another failure: still pending, tried again at the next
  /// start (or the next tap).
  failed,

  /// Nothing was pending.
  nothing,
}

/// Settings › Delete account, on the client (Q-B1: Spark plan, no Cloud
/// Functions). Order: "deletion pending" on the phone → every
/// `users/{uid}` document the app can reach → the Auth user → the phone's
/// database wiped → the flag cleared. Each step can run again, so a run
/// cut off anywhere (offline, killed) is finished by [resume] at the next
/// start.
///
/// Moving to a callable Cloud Function later: [deleteRemoteData] and the
/// Auth step become one call; the pending flag and the wipe stay.
class AccountDeletion {
  new({
    required this.db,
    required this.remote,
    required this.auth,
    required this.wipeLocal,
    this.pauseSync,
    this.resumeSync,
    this.onStep,
  });

  final AppDatabase db;
  final RemoteStore? remote;
  final AuthRepository auth;

  /// Empties the phone's database (every table but `meta`) and what the
  /// running app holds; the app shows Welcome after it.
  final Future<void> Function() wipeLocal;

  /// Stops the sync first: a push after the documents were deleted would
  /// bring some back, and nobody could delete them once the Auth user is
  /// gone.
  final Future<void> Function()? pauseSync;

  /// Lets the sync follow the signed-in user again when a run ends (done,
  /// failed or nothing to do), so an account made afterwards syncs. While
  /// the password is awaited it stays paused; a deletion still pending
  /// keeps it off by itself.
  final Future<void> Function()? resumeSync;

  /// Called at each point where the app could be killed (tests throw from
  /// it): `pending`, `remote`, `auth`, `wiped`.
  @visibleForTesting
  final Future<void> Function(String point)? onStep;

  static const kPending = 'account.deletion';
  static final _log = Log('account');

  Future<void> _step(String p) async => await onStep?.call(p);

  Future<Map<String, Object?>?> _flag() async {
    final row = await (db.select(
      db.meta,
    )..where((t) => t.key.equals(kPending))).getSingleOrNull();
    if (row == null) return null;
    final v = jsonDecode(row.value);
    return v is Map<String, Object?> && v['uid'] is String ? v : null;
  }

  Future<void> _setFlag(Map<String, Object?> v) => db
      .into(db.meta)
      .insertOnConflictUpdate(
        MetaCompanion.insert(key: kPending, value: jsonEncode(v)),
      );

  /// The pending deletion's account id, if any.
  Future<String?> pending() async => (await _flag())?['uid'] as String?;

  /// Starts deleting the signed-in account (the user confirmed with its
  /// email). The [password] comes first, every time (Q-B1, user
  /// 2026-11-27): nothing is deleted or flagged until it is right, so a
  /// cancel or a wrong password leaves the account as it was. Throws
  /// `AuthFailure` (wrong password, offline).
  Future<DeletionResult> start({required String password}) async {
    final u = auth.currentUser;
    if (u == null) return DeletionResult.nothing;
    await auth.reauthenticate(password);
    await _setFlag({'uid': u.id});
    await _step('pending');
    return await _run(u.id);
  }

  /// At start: finishes a deletion an earlier run left pending.
  Future<DeletionResult> resume() async {
    final uid = await pending();
    if (uid == null) return DeletionResult.nothing;
    return await _run(uid);
  }

  /// After [DeletionResult.needsPassword].
  Future<DeletionResult> reauthenticateAndResume(String password) async {
    await auth.reauthenticate(password); // throws AuthFailure
    return await resume();
  }

  /// Every document of the account the app can reach.
  Future<void> deleteRemoteData(String uid) async {
    final r = remote;
    if (r == null) return;
    final base = 'users/$uid';
    for (final c in ['activity', 'phrases', 'settings']) {
      for (final d in await r.list('$base/$c')) {
        await r.delete('$base/$c/${d.id}');
      }
    }
    await r.delete(base);
  }

  Future<DeletionResult> _run(String uid) async {
    await pauseSync?.call();
    final result = await _steps(uid);
    if (result != DeletionResult.needsPassword) await resumeSync?.call();
    return result;
  }

  Future<DeletionResult> _steps(String uid) async {
    final user = auth.currentUser;
    if (user != null && user.id != uid) {
      // another account is signed in: the old one can't be reached any more
      _log.warn('deletion_other_account');
      await _clear();
      return DeletionResult.failed;
    }
    if (user == null && (await _flag())?['authDeleted'] != true) {
      // signed out before the account was deleted: it still exists, so the
      // phone's data stays; the deletion can start again after a sign-in
      _log.warn('deletion_signed_out');
      await _clear();
      return DeletionResult.nothing;
    }
    if (user != null) {
      try {
        // an unverified account never wrote anything (Q-B3), and the rules
        // refuse its deletes
        if (user.emailVerified) await deleteRemoteData(uid);
        await _step('remote');
        await auth.deleteUser();
      } on RemoteFailure catch (e) {
        _log.info('deletion_remote_failed', {'problem': e.problem.name});
        return DeletionResult.failed;
      } on AuthFailure catch (e) {
        if (e.problem == AuthProblem.requiresRecentLogin) {
          return DeletionResult.needsPassword;
        }
        _log.info('deletion_auth_failed', {'problem': e.problem.name});
        return DeletionResult.failed;
      }
      await _setFlag({'uid': uid, 'authDeleted': true});
      await _step('auth');
    }
    // the account is gone (or was before this start): the phone's data too
    await wipeLocal();
    await _step('wiped');
    await _clear();
    _log.info('deleted');
    return DeletionResult.done;
  }

  Future<void> _clear() =>
      (db.delete(db.meta)..where((t) => t.key.equals(kPending))).go();
}
