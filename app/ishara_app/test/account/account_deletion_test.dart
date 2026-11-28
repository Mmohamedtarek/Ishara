import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/account/account_deletion.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/sync/remote_store.dart';

import '../support/local_db.dart';

/// Q-B1: every step of the deletion, and a kill after each one.
void main() {
  late FakeRemoteServer server;
  late FakeAuthRepository auth;
  late AppDatabase db;
  late FakeRemoteStore remote;
  var wiped = 0;

  setUp(() async {
    server = FakeRemoteServer();
    auth = FakeAuthRepository(delay: Duration.zero);
    db = memoryDb();
    remote = FakeRemoteStore(server, user: () => auth.currentUser);
    wiped = 0;
    await auth.createAccount(
      name: 'Alice',
      email: 'alice@example.com',
      password: 'secret123',
    );
    auth.verify('alice@example.com');
    await auth.refreshUser();
    final uid = auth.currentUser!.id;
    // what the account holds
    for (final p in [
      'users/$uid',
      'users/$uid/settings/app',
      'users/$uid/phrases/a1',
      'users/$uid/phrases/a2',
      'users/$uid/activity/e1',
      'users/$uid/activity/e2',
      'users/$uid/activity/e3',
    ]) {
      server.docs[p] = {'x': 1};
    }
    // and someone else's, never touched
    server.docs['users/bob/phrases/b1'] = {'x': 1};
  });

  tearDown(() async {
    await auth.dispose();
    await server.dispose();
  });

  AccountDeletion deletion({Future<void> Function(String)? onStep}) =>
      AccountDeletion(
        db: db,
        remote: remote,
        auth: auth,
        wipeLocal: () async => wiped++,
        onStep: onStep,
      );

  Future<void> expectAllGone() async {
    expect(server.docs.keys, ['users/bob/phrases/b1']);
    expect(auth.currentUser, isNull);
    expect(
      await auth
          .signIn(email: 'alice@example.com', password: 'secret123')
          .then((_) => 'exists', onError: (_) => 'gone'),
      'gone',
    );
    expect(wiped, greaterThan(0));
    expect(await deletion().pending(), isNull);
  }

  test('the whole order: pending → documents → Auth user → wipe → flag '
      'cleared', () async {
    final steps = <String>[];
    final r = await deletion(onStep: (p) async => steps.add(p))
        .start(password: 'secret123');
    expect(r, DeletionResult.done);
    expect(steps, ['pending', 'remote', 'auth', 'wiped']);
    await expectAllGone();
    expect(wiped, 1);
  });

  for (final point in ['pending', 'remote', 'auth', 'wiped']) {
    test('killed after "$point": the next start finishes it', () async {
      await expectLater(
        deletion(
          onStep: (p) async {
            if (p == point) throw StateError('killed');
          },
        ).start(password: 'secret123'),
        throwsStateError,
      );
      expect(await deletion().pending(), isNotNull);
      // the next start
      expect(await deletion().resume(), DeletionResult.done);
      await expectAllGone();
    });
  }

  test('offline halfway through the documents: still pending; online, '
      'resumed', () async {
    var calls = 0;
    final flaky = _Flaky(remote, failAfter: 3, calls: () => ++calls);
    final d = AccountDeletion(
      db: db,
      remote: flaky,
      auth: auth,
      wipeLocal: () async => wiped++,
    );
    expect(await d.start(password: 'secret123'), DeletionResult.failed);
    expect(await d.pending(), isNotNull);
    expect(auth.currentUser, isNotNull);
    expect(wiped, 0);
    flaky.failAfter = null;
    expect(await d.resume(), DeletionResult.done);
    await expectAllGone();
  });

  test('the password comes first: wrong or offline, nothing is deleted or '
      'flagged', () async {
    final steps = <String>[];
    final d = deletion(onStep: (p) async => steps.add(p));
    await expectLater(
      d.start(password: 'wrong'),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.problem,
          'problem',
          AuthProblem.invalidCredentials,
        ),
      ),
    );
    expect(steps, isEmpty);
    expect(await d.pending(), isNull);
    expect(server.docs.keys, hasLength(greaterThan(1))); // all still there
    expect(auth.currentUser, isNotNull);
    expect(wiped, 0);
  });

  test('resumed at a later start and a recent sign-in needed: asks the '
      'password, then finishes', () async {
    await expectLater(
      deletion(
        onStep: (p) async {
          if (p == 'pending') throw StateError('killed');
        },
      ).start(password: 'secret123'),
      throwsStateError,
    );
    auth.requireRecentLogin = true;
    final d = deletion();
    expect(await d.resume(), DeletionResult.needsPassword);
    expect(await d.pending(), isNotNull);
    // the documents are already gone; the Auth user isn't
    expect(server.docs.keys, ['users/bob/phrases/b1']);
    expect(auth.currentUser, isNotNull);
    await expectLater(
      d.reauthenticateAndResume('wrong'),
      throwsA(
        isA<AuthFailure>().having(
          (f) => f.problem,
          'problem',
          AuthProblem.invalidCredentials,
        ),
      ),
    );
    expect(await d.reauthenticateAndResume('secret123'), DeletionResult.done);
    await expectAllGone();
  });

  test(
    'the sync is paused first (a push could bring documents back)',
    () async {
      var paused = 0;
      final d = AccountDeletion(
        db: db,
        remote: remote,
        auth: auth,
        wipeLocal: () async => wiped++,
        pauseSync: () async => paused++,
      );
      expect(await d.start(password: 'secret123'), DeletionResult.done);
      expect(paused, 1);
    },
  );

  test('the sync is resumed when a run ends, but not while the password is '
      'awaited (an account made afterwards syncs)', () async {
    var resumed = 0;
    AccountDeletion d() => AccountDeletion(
      db: db,
      remote: remote,
      auth: auth,
      wipeLocal: () async => wiped++,
      pauseSync: () async {},
      resumeSync: () async => resumed++,
    );
    await expectLater(
      AccountDeletion(
        db: db,
        remote: remote,
        auth: auth,
        wipeLocal: () async => wiped++,
        onStep: (p) async {
          if (p == 'pending') throw StateError('killed');
        },
      ).start(password: 'secret123'),
      throwsStateError,
    );
    auth.requireRecentLogin = true;
    expect(await d().resume(), DeletionResult.needsPassword);
    expect(resumed, 0);
    expect(await d().reauthenticateAndResume('secret123'), DeletionResult.done);
    expect(resumed, 1);
    // nothing pending: a resume at the next start ends at once, resumed
    expect(await d().resume(), DeletionResult.nothing);
    expect(resumed, 1); // (no run: nothing was paused)
  });

  test('an unverified account: nothing on the server to delete (the rules '
      'would refuse it); the Auth user and the phone data go', () async {
    final a = FakeAuthRepository(delay: Duration.zero);
    addTearDown(a.dispose);
    await a.createAccount(name: 'U', email: 'u@b.co', password: 'secret123');
    final r = FakeRemoteStore(server, user: () => a.currentUser);
    final writes = server.writes.length;
    final d = AccountDeletion(
      db: db,
      remote: r,
      auth: a,
      wipeLocal: () async => wiped++,
    );
    expect(await d.start(password: 'secret123'), DeletionResult.done);
    expect(a.currentUser, isNull);
    expect(wiped, 1);
    expect(server.writes.length, writes);
    expect(server.docs.keys, contains('users/bob/phrases/b1'));
  });

  test('pending, but signed out before the account went: the phone data '
      'stays, the flag is cleared', () async {
    await expectLater(
      deletion(
        onStep: (p) async {
          if (p == 'pending') throw StateError('killed');
        },
      ).start(password: 'secret123'),
      throwsStateError,
    );
    await auth.signOut();
    expect(await deletion().resume(), DeletionResult.nothing);
    expect(wiped, 0);
    expect(await deletion().pending(), isNull);
    // the account still exists
    expect(
      await auth
          .signIn(email: 'alice@example.com', password: 'secret123')
          .then((_) => 'exists'),
      'exists',
    );
  });

  test('nothing pending: resume does nothing', () async {
    expect(await deletion().resume(), DeletionResult.nothing);
    expect(wiped, 0);
  });
}

/// Fails with "offline" after [failAfter] successful calls.
class _Flaky implements RemoteStore {
  new(this._inner, {required this.failAfter, required this._calls});

  final RemoteStore _inner;
  int? failAfter;
  final int Function() _calls;

  void _tick() {
    final n = _calls();
    final f = failAfter;
    if (f != null && n > f) throw const RemoteFailure(RemoteProblem.network);
  }

  @override
  Future<void> delete(String path) async {
    _tick();
    await _inner.delete(path);
  }

  @override
  Future<Map<String, Object?>?> get(String path) => _inner.get(path);

  @override
  Future<List<RemoteDoc>> list(String collection) => _inner.list(collection);

  @override
  Future<void> set(String path, Map<String, Object?> data) =>
      _inner.set(path, data);

  @override
  Stream<List<RemoteDoc>> watch(String collection) => _inner.watch(collection);

  @override
  Stream<Map<String, Object?>?> watchDoc(String path) => _inner.watchDoc(path);
}
