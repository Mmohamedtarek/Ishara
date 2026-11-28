import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/sync/remote_store.dart';
import 'package:ishara_app/core/sync/sync_engine.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';

/// The account on a phone: set by the test.
class TestAuth implements AuthRepository {
  AuthUser? user;
  final _changes = StreamController<AuthUser?>.broadcast();

  void setUser(AuthUser? u) {
    user = u;
    _changes.add(u);
  }

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get userChanges => _changes.stream;

  @override
  Future<void> signOut() async => setUser(null);

  @override
  Future<AuthUser?> refreshUser() async => user;

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> reauthenticate(String password) async {}

  @override
  Future<void> deleteUser() async => setUser(null);

  Future<void> dispose() => _changes.close();
}

const alice = AuthUser(
  id: 'alice',
  email: 'alice@example.com',
  name: 'Alice',
  emailVerified: true,
);
final AuthUser aliceUnverified = alice.copyWith(emailVerified: false);
const bob = AuthUser(
  id: 'bob',
  email: 'bob@example.com',
  name: 'Bob',
  emailVerified: true,
);

/// One simulated phone: its own database, repositories and sync engine, on
/// the shared [server].
class Phone {
  new(this.server, {required this.deviceId, DateTime Function()? now})
    : db = AppDatabase(NativeDatabase.memory()),
      _now = now ?? DateTime.now;

  final FakeRemoteServer server;
  final String deviceId;
  final DateTime Function() _now;
  final AppDatabase db;
  final auth = TestAuth();
  late final RemoteStore remote = FakeRemoteStore(
    server,
    user: () => auth.user,
  );
  late final FakeRemoteStore fakeRemote = remote as FakeRemoteStore;
  late final phrases = LocalSavedPhrasesRepository(db, now: _now);
  late final activity = LocalActivityRepository(db);
  late DriftKeyValueStore prefs;
  late final SyncEngine engine;
  int settingsApplied = 0;
  int _events = 0;

  Future<Phone> boot() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    prefs = await DriftKeyValueStore.load(db);
    engine = SyncEngine(
      db: db,
      remote: remote,
      auth: auth,
      phrases: phrases,
      activity: activity,
      prefs: prefs,
      onSettingsApplied: () => settingsApplied++,
      debounce: Duration.zero,
    )..start();
    addTearDown(dispose);
    return this;
  }

  /// Lets the engine finish what it's doing (pull, push, listeners).
  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await engine.push();
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  Future<void> signIn(AuthUser? u) async {
    auth.setUser(u);
    await settle();
  }

  ActivityEvent event(String label, {int xp = 10}) {
    final at = DateTime.utc(2026, 10, 17, 9, _events++);
    return ActivityEvent(
      id: '$deviceId-e$_events',
      type: ActivityType.quiz,
      moduleId: 'start',
      passed: true,
      xp: xp,
      day: LocalDay.of(at.toLocal()),
      at: at,
      deviceId: deviceId.padRight(32, '0').substring(0, 32),
      label: label,
    );
  }

  Future<int> outboxCount() async => (await db.select(db.outbox).get()).length;

  Future<void> dispose() async {
    await engine.dispose();
    await phrases.dispose();
    await activity.dispose();
    await auth.dispose();
    await db.close();
  }
}
