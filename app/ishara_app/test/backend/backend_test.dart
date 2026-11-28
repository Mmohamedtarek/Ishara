import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/auth/firebase_auth_repository.dart';
import 'package:ishara_app/core/backend/backend.dart';
import 'package:ishara_app/core/backend/firebase_project.dart';
import 'package:ishara_app/core/settings/settings_store.dart';
import 'package:ishara_app/core/sync/settings_doc.dart';
import 'package:ishara_app/core/sync/sync_providers.dart';

void main() {
  group('--dart-define=BACKEND (step 10b)', () {
    test('given: that one; firebase needs the project options', () {
      expect(resolveBackend(hasOptions: false, define: 'fake'), Backend.fake);
      expect(
        resolveBackend(hasOptions: false, define: 'emulator'),
        Backend.emulator,
      );
      expect(
        resolveBackend(hasOptions: true, define: 'firebase'),
        Backend.firebase,
      );
      expect(
        () => resolveBackend(hasOptions: false, define: 'firebase'),
        throwsA(
          isA<BackendConfigError>().having(
            (e) => e.message,
            'message',
            contains('firebase_defines.py'),
          ),
        ),
      );
    });

    // (tests run without --dart-define=BACKEND)
    test('not given: fake, with or without options; unknown: refused', () {
      expect(resolveBackend(hasOptions: true), Backend.fake);
      expect(resolveBackend(hasOptions: false), Backend.fake);
      for (final bad in ['nonsense', 'Firebase', ' firebase']) {
        expect(
          () => resolveBackend(hasOptions: true, define: bad),
          throwsA(isA<BackendConfigError>()),
          reason: bad,
        );
      }
    });

    test('project options come from the build, Android only; the emulators '
        'use a demo project', () {
      // this test run has no project values
      expect(firebaseProjectOptions(platform: TargetPlatform.android), isNull);
      const all = {
        FirebaseDefines.apiKey: 'k',
        FirebaseDefines.appId: '1:2:android:3',
        FirebaseDefines.senderId: '2',
        FirebaseDefines.projectId: 'p',
      };
      final o = firebaseProjectOptions(
        defines: all,
        platform: TargetPlatform.android,
      )!;
      expect(
        (o.apiKey, o.appId, o.messagingSenderId, o.projectId),
        ('k', '1:2:android:3', '2', 'p'),
      );
      expect(o.storageBucket, isNull);
      expect(
        firebaseProjectOptions(
          defines: {...all, FirebaseDefines.storageBucket: 'b'},
          platform: TargetPlatform.android,
        )!.storageBucket,
        'b',
      );
      for (final k in all.keys) {
        expect(
          firebaseProjectOptions(
            defines: {...all, k: ''},
            platform: TargetPlatform.android,
          ),
          isNull,
          reason: k,
        );
      }
      expect(
        firebaseProjectOptions(defines: all, platform: TargetPlatform.iOS),
        isNull,
      );
      expect(emulatorOptions.projectId, startsWith('demo-'));
    });
  });

  test("Firebase's error codes map to the screen's problems, never raw", () {
    const cases = {
      'invalid-credential': AuthProblem.invalidCredentials,
      'wrong-password': AuthProblem.invalidCredentials,
      'user-not-found': AuthProblem.invalidCredentials,
      'user-disabled': AuthProblem.invalidCredentials,
      'INVALID_LOGIN_CREDENTIALS': AuthProblem.invalidCredentials,
      'email-already-in-use': AuthProblem.emailInUse,
      'weak-password': AuthProblem.weakPassword,
      'password-does-not-meet-requirements': AuthProblem.weakPassword,
      'invalid-email': AuthProblem.invalidEmail,
      'network-request-failed': AuthProblem.network,
      'too-many-requests': AuthProblem.tooManyRequests,
      'requires-recent-login': AuthProblem.requiresRecentLogin,
      'internal-error': AuthProblem.unknown,
      'something-new': AuthProblem.unknown,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(authProblemFor(key), value, reason: key);
    }
  });

  group('settings/app ↔ the phone (Phase 0)', () {
    final at = DateTime.utc(2026, 10, 17, 9);
    test('"Tap to start and stop" stays on the phone (S10-9)', () {
      expect(SettingsDoc.keys, isNot(contains(SettingsStore.kMicTap)));
    });
    test('only valid values go up; speed in tenths ↔ 0.5 / 1 / 1.5', () {
      final phone = <String, Object>{
        'settings.language': 'ar',
        'settings.theme': 'dark',
        'setup.signLanguage': 'arsl', // never synced (sign rule 8)
        'setup.spoken': 'en',
        'setup.role': 'speak',
        'settings.character': 'nour',
        'settings.signSpeed': 15,
        'settings.subtitles': false,
        'settings.bigText': true,
        'settings.highContrast': 'yes', // damaged: left out
        'settings.vibrate': true,
        'settings.developer': true, // local only
        'glove.id': 'AA', // local only
      };
      final doc = SettingsDoc.toRemote((k) => phone[k], at);
      expect(doc, {
        'updatedAt': at,
        'uiLang': 'ar',
        'theme': 'dark',
        'spokenLanguage': 'en',
        'who': 'speak',
        'avatarId': 'nour',
        'signSpeed': 1.5,
        'subtitles': false,
        'bigText': true,
        'vibrate': true,
      });
      expect(SettingsDoc.fromRemote(doc), {
        'settings.language': 'ar',
        'settings.theme': 'dark',
        'setup.spoken': 'en',
        'setup.role': 'speak',
        'settings.character': 'nour',
        'settings.signSpeed': 15,
        'settings.subtitles': false,
        'settings.bigText': true,
        'settings.vibrate': true,
      });
    });

    test('unknown values from the account are left out', () {
      expect(
        SettingsDoc.fromRemote({
          'updatedAt': at,
          'uiLang': 'fr',
          'signSpeed': 2,
          'signLanguage': 'asl',
          'theme': 7,
        }),
        {'setup.signLanguage': 'asl'},
      );
    });
  });

  group('Firebase failing at run time (user 2026-11-27)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('accounts are off, never the fakes', () async {
      // no Firebase plugin in a host test: initializeApp fails as on a
      // phone where Firebase can't start
      expect(await startBackend(Backend.firebase), Backend.unavailable);
      expect(await startBackend(Backend.emulator), Backend.unavailable);
      expect(await startBackend(Backend.fake), Backend.fake);
    });

    test('no accounts, no remote, no sync; the app is a guest', () async {
      final c = ProviderContainer(
        overrides: [backendProvider.overrideWithValue(Backend.unavailable)],
      );
      addTearDown(c.dispose);
      final auth = c.read(authRepositoryProvider);
      expect(auth, isA<UnavailableAuthRepository>());
      expect(c.read(remoteStoreProvider), isNull);
      expect(c.read(syncEngineProvider), isNull);
      expect(auth.currentUser, isNull);
      expect(await auth.refreshUser(), isNull);
      await auth.signOut();
      final off = throwsA(
        isA<AuthFailure>().having(
          (f) => f.problem,
          'problem',
          AuthProblem.unavailable,
        ),
      );
      await expectLater(auth.signIn(email: 'a@b.co', password: 'x'), off);
      await expectLater(
        auth.createAccount(name: 'A', email: 'a@b.co', password: 'secret123'),
        off,
      );
      await expectLater(auth.sendPasswordReset('a@b.co'), off);
      await expectLater(auth.sendEmailVerification(), off);
      await expectLater(auth.reauthenticate('x'), off);
      await expectLater(auth.deleteUser(), off);
      expect(await auth.userChanges.isEmpty, isTrue);
    });
  });
}
