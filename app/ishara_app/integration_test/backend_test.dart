// Step 10b against the Firebase Emulator Suite on the laptop:
//   (cd firebase && npx firebase emulators:start --only auth,firestore \
//      --project demo-ishara)
//   adb reverse tcp:9099 tcp:9099 && adb reverse tcp:8080 tcp:8080
//   flutter test integration_test/backend_test.dart -d <phone> \
//     --dart-define=BACKEND=emulator
// Sign up in the app → verify (the emulator's link) → "I've verified" →
// star a phrase → a second simulated phone signs in → the phrase arrives.
// Then account deletion, killed after each step and finished by the next
// run, checked on the emulator. Prints BACKEND lines for the record.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/account/account_deletion.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/firebase_auth_repository.dart';
import 'package:ishara_app/core/backend/backend.dart';
import 'package:ishara_app/core/backend/firebase_project.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/sync/remote_store.dart';
import 'package:ishara_app/core/sync/sync_engine.dart';
import 'package:ishara_app/core/sync/sync_providers.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';

const _auth = 'http://$emulatorHost:$emulatorAuthPort';
const _store = 'http://$emulatorHost:$emulatorFirestorePort';
const String _project = emulatorProjectId;

void mark(String s) => debugPrint('BACKEND $s');

Future<Object?> _http(
  String method,
  String url, [
  Object? body,
  bool admin = true,
]) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    // the emulator's admin access (no rules); the verification link's own
    // call goes without it, as the browser would
    if (admin) req.headers.set('Authorization', 'Bearer owner');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return text.isEmpty ? null : jsonDecode(text);
  } finally {
    client.close();
  }
}

/// Opens the verification link the emulator "sent" to [email].
Future<void> _verify(String email) async {
  final codes =
      (await _http('GET', '$_auth/emulator/v1/projects/$_project/oobCodes'))!
          as Map<String, Object?>;
  final mine = (codes['oobCodes']! as List)
      .cast<Map<String, Object?>>()
      .lastWhere(
        (c) => c['email'] == email && c['requestType'] == 'VERIFY_EMAIL',
      );
  await _http(
    'POST',
    '$_auth/identitytoolkit.googleapis.com/v1/accounts:update?key=x',
    {'oobCode': mine['oobCode']},
    false,
  );
}

/// The account's documents in the emulator (admin read, no rules).
Future<List<String>> _docs(String path) async {
  final r = await _http(
    'GET',
    '$_store/v1/projects/$_project/databases/(default)/documents/$path',
  ) as Map<String, Object?>?;
  return [
    for (final d in (r?['documents'] as List?) ?? const [])
      ((d as Map)['name'] as String).split('/').last,
  ];
}

Future<bool> _authUserExists(String email) async {
  final r = await _http(
    'POST',
    '$_auth/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:query',
    {'returnUserInfo': true},
  ) as Map<String, Object?>?;
  return ((r?['userInfo'] as List?) ?? const []).any(
    (u) => (u as Map)['email'] == email,
  );
}

Future<void> waitFor(
  WidgetTester t,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('not found: $f');
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> until(
  WidgetTester t,
  bool Function() done,
  String what, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException(what);
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Settings back at its top (the list keeps its place across pages).
Future<void> settingsTop(WidgetTester t) async {
  await waitFor(t, find.byKey(const ValueKey('settings-body')));
  await t.fling(
    find.byKey(const ValueKey('settings-body')),
    const Offset(0, 3000),
    3000,
  );
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> tapAndWait(WidgetTester t, Finder f) async {
  await waitFor(t, f);
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(
      await startBackend(Backend.emulator),
      Backend.emulator,
      reason: 'the emulators must be running (see the top of this file)',
    );
    await _http('DELETE', '$_auth/emulator/v1/projects/$_project/accounts');
    await _http(
      'DELETE',
      '$_store/emulator/v1/projects/$_project/databases/(default)/documents',
    );
  });

  testWidgets('sign up → verify → star → a second phone gets the phrase', (
    t,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'mona.$stamp@example.com';
    final store = MemoryKeyValueStore({
      'onboarding.done': true,
      'setup.spoken': 'en',
      'setup.role': 'sign',
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(Backend.emulator),
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.settings),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    await waitFor(t, find.byKey(const ValueKey('settings-create-account')));
    final c = ProviderScope.containerOf(
      t.element(find.byKey(const ValueKey('settings-body'))),
    )..read(syncEngineProvider);

    // 1. sign up in the app
    await tapAndWait(t, find.byKey(const ValueKey('settings-create-account')));
    await waitFor(t, find.byKey(const ValueKey('auth-name')));
    Finder input(String k) => find.descendant(
      of: find.byKey(ValueKey(k)),
      matching: find.byType(EditableText),
    );
    await t.enterText(input('auth-name'), 'Mona');
    await t.enterText(input('auth-email'), email);
    await t.enterText(input('auth-password'), 'secret123');
    await tapAndWait(t, find.byKey(const ValueKey('auth-submit')));
    final auth = c.read(authRepositoryProvider);
    await until(t, () => auth.currentUser != null, 'signed up');
    expect(auth.currentUser!.emailVerified, isFalse);
    mark('1 signed up ${auth.currentUser!.id}, not verified');
    c.read(appRouterProvider).go(AppRoutes.settings);
    await settingsTop(t);
    await waitFor(t, find.byKey(const ValueKey('settings-verify')));
    // nothing synced before the email is verified (Q-B3)
    await c.read(savedPhrasesRepositoryProvider).star('Where is the pharmacy?');
    await t.pump(const Duration(seconds: 2));
    final uid = auth.currentUser!.id;
    expect(await _docs('users/$uid/phrases'), isEmpty);
    mark('2 starred before verifying: nothing uploaded');

    // 2. verify with the emulator's link, then "I've verified"
    await _verify(email);
    await t.pump(const Duration(seconds: 1));
    await settingsTop(t);
    // Firebase may notice the verification by itself (a token refresh);
    // otherwise the user taps "I've verified"
    final check = find.byKey(const ValueKey('verify-check'));
    if (check.evaluate().isNotEmpty) {
      await t.ensureVisible(check);
      await t.pump(const Duration(milliseconds: 200));
      if (check.evaluate().isNotEmpty) await t.tap(check);
      mark('2b tapped "I\'ve verified"');
    }
    await until(t, () => auth.currentUser!.emailVerified, 'verified');
    await settingsTop(t);
    await waitFor(t, find.text('Synced with your account'));
    final id = c.read(savedPhrasesRepositoryProvider).phrases.single.id;
    expect(await _docs('users/$uid/phrases'), [id]);
    final profile = await _http(
      'GET',
      '$_store/v1/projects/$_project/databases/(default)/documents/users/$uid',
    ) as Map<String, Object?>?;
    expect((profile?['fields'] as Map?)?['displayName'], {
      'stringValue': 'Mona',
    });
    mark('3 verified: the phrase $id is in the account');

    // 3. a second phone signs in to the same account
    final app2 = await Firebase.initializeApp(
      name: 'phone2',
      options: emulatorOptions,
    );
    final auth2 = FirebaseAuth.instanceFor(app: app2);
    await auth2.useAuthEmulator(
      emulatorHost,
      emulatorAuthPort,
      automaticHostMapping: false,
    );
    final fs2 = FirebaseFirestore.instanceFor(app: app2)
      ..useFirestoreEmulator(
        emulatorHost,
        emulatorFirestorePort,
        automaticHostMapping: false,
      )
      ..settings = const Settings(persistenceEnabled: false);
    final db2 = AppDatabase(NativeDatabase.memory());
    final phrases2 = LocalSavedPhrasesRepository(db2);
    final repo2 = FirebaseAuthRepository(auth2, language: () => 'en');
    final engine2 = SyncEngine(
      db: db2,
      remote: FirestoreRemoteStore(fs2),
      auth: repo2,
      phrases: phrases2,
      activity: LocalActivityRepository(db2),
      prefs: await DriftKeyValueStore.load(db2),
      onSettingsApplied: () {},
    )..start();
    await repo2.signIn(email: email, password: 'secret123');
    await until(
      t,
      () => phrases2.find('Where is the pharmacy?') != null,
      'the phrase on phone 2',
    );
    mark('4 phone 2 signed in: "Where is the pharmacy?" arrived');

    // and back: phone 2 unstars it, phone 1 follows (live listener)
    await phrases2.unstar('Where is the pharmacy?');
    await until(
      t,
      () => c.read(savedPhrasesRepositoryProvider).phrases.isEmpty,
      'the tombstone on phone 1',
    );
    mark('5 phone 2 unstarred it: gone on phone 1 too');
    await engine2.dispose();
    await phrases2.dispose();
    await repo2.signOut();
    await db2.close();
    await app2.delete();
  });

  testWidgets('account deletion against the emulator: killed after each '
      'step, finished by the next run', (t) async {
    final fbAuth = FirebaseAuth.instance;
    final remote = FirestoreRemoteStore(FirebaseFirestore.instance);
    final repo = FirebaseAuthRepository(fbAuth, language: () => 'en');
    for (final point in ['pending', 'remote', 'auth', 'wiped']) {
      final email =
          'del.$point.${DateTime.now().millisecondsSinceEpoch}@example.com';
      await repo.createAccount(name: 'D', email: email, password: 'secret123');
      await _verify(email);
      final u = (await repo.refreshUser())!;
      for (final p in [
        'users/${u.id}',
        'users/${u.id}/settings/app',
        'users/${u.id}/phrases/a1b2',
        'users/${u.id}/activity/e1',
      ]) {
        await remote.set(p, switch (p.split('/').length) {
          2 => {
            'displayName': 'D',
            'createdAt': DateTime.now().toUtc(),
            'updatedAt': DateTime.now().toUtc(),
            'schemaVersion': 1,
          },
          4 when p.contains('/settings/') => {
            'updatedAt': DateTime.now().toUtc(),
            'theme': 'dark',
          },
          4 when p.contains('/phrases/') => {
            'text': 'hi',
            'lang': 'en',
            'createdAt': DateTime.now().toUtc(),
            'updatedAt': DateTime.now().toUtc(),
            'deleted': false,
          },
          _ => {
            'v': 1,
            'type': 'quiz',
            'label': 'hello',
            'moduleId': 'start',
            'passed': true,
            'xp': 10,
            'day': '2026-10-17',
            'at': DateTime.now().toUtc(),
            'deviceId': 'a' * 32,
          },
        });
      }
      final db = AppDatabase(NativeDatabase.memory());
      var wiped = 0;
      AccountDeletion deletion([Future<void> Function(String)? onStep]) =>
          AccountDeletion(
            db: db,
            remote: remote,
            auth: repo,
            wipeLocal: () async => wiped++,
            onStep: onStep,
          );
      await expectLater(
        deletion((p) async {
          if (p == point) throw StateError('killed');
        }).start(password: 'secret123'),
        throwsStateError,
      );
      expect(await deletion().resume(), DeletionResult.done, reason: point);
      expect(await _docs('users/${u.id}/phrases'), isEmpty, reason: point);
      expect(await _docs('users/${u.id}/activity'), isEmpty, reason: point);
      expect(await _authUserExists(email), isFalse, reason: point);
      expect(wiped, greaterThan(0), reason: point);
      expect(await deletion().pending(), isNull, reason: point);
      mark('6 deletion killed after "$point": finished, nothing left');
      await db.close();
    }
  });
}
