// Step 10 states, EN / AR x light / dark (the runner's images are the
// reference: .github/workflows/goldens.yml).
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/device/app_info.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/core/sync/sync_engine.dart';
import 'package:ishara_app/core/sync/sync_providers.dart';

import '../support/fake_glove.dart';
import '../support/fake_sos.dart';
import '../support/fake_speech.dart';
import '../support/fake_talk.dart';

class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// Mona, verified (step 9's Settings golden shows her before the link).
class _Verified extends FakeAuthRepository {
  new({this.recentLogin = false}) : super(delay: Duration.zero);
  final bool recentLogin;

  @override
  AuthUser? get currentUser => const AuthUser(
    id: 'u1',
    email: 'mona@example.com',
    name: 'Mona',
    emailVerified: true,
  );

  @override
  Future<void> deleteUser() async {
    if (recentLogin) throw const AuthFailure(AuthProblem.requiresRecentLogin);
  }
}

class _Sync implements SyncControl {
  @override
  Future<bool> flush({Duration limit = Duration.zero}) async => false;

  @override
  Future<void> clearSyncedData() async {}
}

final _cast = AvatarCast.parse(File(avatarCastAsset).readAsStringSync());
final _library = AvatarLibrary.parse(
  File('assets/packs/asl/avatar/library.json').readAsStringSync(),
  language: SignLanguage.asl,
);

AvatarRuntime _runtime() {
  final surface = UnavailableAvatarSurface();
  return AvatarRuntime(
    AvatarController(
      page: surface,
      library: _library,
      libraryUrl: '',
      castUrl: '',
      cast: _cast,
    ),
    surface,
  );
}

/// Carries a scenario's [StorageHealth], so the test can raise it after
/// the start (the notice shows for 6 s from then).
class StorageNoticeProbe extends StatelessWidget {
  const new({required this.health, required this.child, super.key});

  final StorageHealth health;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

Widget _app(
  AppLanguage language,
  ThemeMode mode, {
  required String route,
  SyncState sync = SyncState.synced,
  bool recentLogin = false,
}) {
  final health = StorageHealth();
  return StorageNoticeProbe(
    health: health,
    child: ProviderScope(
      overrides: [
        appSettingsControllerProvider.overrideWith(
          () => _Fixed(AppSettings(language: language, themeMode: mode)),
        ),
        appRouterProvider.overrideWith(
          (ref) => buildRouter(initialLocation: route),
        ),
        gloveSourceProvider.overrideWithValue(FakeGloveSource()),
        activeGloveKindProvider.overrideWithValue(GloveSourceKind.ble),
        glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
        keyValueStoreProvider.overrideWithValue(
          MemoryKeyValueStore({'setup.spoken': 'en', 'onboarding.done': true}),
        ),
        authRepositoryProvider.overrideWithValue(
          _Verified(recentLogin: recentLogin),
        ),
        syncStateProvider.overrideWithValue(ValueNotifier(sync)),
        syncControlProvider.overrideWithValue(_Sync()),
        storageHealthProvider.overrideWithValue(health),
        avatarCastProvider.overrideWithValue(AsyncData(_cast)),
        avatarRuntimeProvider.overrideWithValue(AsyncData(_runtime())),
        appVersionProvider.overrideWithValue(const AsyncData('1.0.0 (1)')),
        speechToTextProvider.overrideWithValue(FakeSpeechToText()),
        micPermissionsProvider.overrideWithValue(
          FakeMicPermissions(current: MicPermission.granted),
        ),
        ...TalkFakes().overrides,
        ...SosFakes().overrides,
      ],
      child: const IsharaApp(),
    ),
  );
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// Scrolls every scenario's Settings list to the end, then taps [key] in
/// each.
Future<void> Function(WidgetTester) _tapAtEnd(
  String key, {
  Future<void> Function(WidgetTester t)? then,
}) => (t) async {
  for (final e in find.byKey(const ValueKey('settings-body')).evaluate()) {
    await t.drag(find.byWidget(e.widget).first, const Offset(0, -4000));
  }
  await t.pump(const Duration(milliseconds: 400));
  for (final e in find.byKey(ValueKey(key)).evaluate().toList()) {
    await t.tap(find.byWidget(e.widget).first);
  }
  await t.pump(const Duration(milliseconds: 400));
  await _settle(t);
  if (then != null) await then(t);
};

Future<void> _golden(
  String name, {
  required String route,
  SyncState sync = SyncState.synced,
  bool recentLogin = false,
  Future<void> Function(WidgetTester t)? act,
  Interaction? whilePerforming,
}) => goldenTest(
  '$name: EN / AR x light / dark',
  fileName: 'step10_$name',
  whilePerforming: whilePerforming,
  pumpBeforeTest: (t) async {
    await _settle(t);
    if (act != null) await act(t);
    // past any toast: no timer left
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  },
  builder: () => GoldenTestGroup(
    columns: 4,
    children: [
      for (final lang in AppLanguage.values)
        for (final mode in [ThemeMode.light, ThemeMode.dark])
          GoldenTestScenario(
            name: '${lang.name} ${mode.name}',
            constraints: const BoxConstraints.tightFor(width: 390, height: 844),
            child: _app(
              lang,
              mode,
              route: route,
              sync: sync,
              recentLogin: recentLogin,
            ),
          ),
    ],
  ),
);

Future<void> _typeEmails(WidgetTester t) async {
  for (final e in find.byKey(const ValueKey('delete-email')).evaluate()) {
    await t.enterText(find.byWidget(e.widget).first, 'mona@example.com');
  }
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> main() async {
  await _golden('settings_synced', route: AppRoutes.settings);
  await _golden(
    'settings_pending',
    route: AppRoutes.settings,
    sync: SyncState.pending,
  );
  await _golden(
    'sign_out_unsynced',
    route: AppRoutes.settings,
    sync: SyncState.pending,
    act: _tapAtEnd('settings-sign-out'),
  );
  await _golden(
    'delete_confirm',
    route: AppRoutes.settings,
    act: _tapAtEnd('settings-delete-account', then: _typeEmails),
  );
  await _golden(
    'delete_password',
    route: AppRoutes.settings,
    recentLogin: true,
    act: _tapAtEnd(
      'settings-delete-account',
      then: (t) async {
        await _typeEmails(t);
        for (final e in find.byKey(const ValueKey('delete-go')).evaluate()) {
          await t.tap(find.byWidget(e.widget).first);
        }
        await _settle(t);
        await _settle(t);
      },
    ),
  );
  // step 10a review (N1): the out-of-storage notice over Talk, captured
  // while it shows; its 6 s go by after the picture
  await _golden(
    'storage_notice',
    route: AppRoutes.talk,
    whilePerforming: (t) async {
      for (final e in find.byType(StorageNoticeProbe).evaluate()) {
        (e.widget as StorageNoticeProbe).health.writeFailed(StateError('x'));
      }
      // the fade-in (0.35 s) needs frames to run
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      return () => t.pump(const Duration(seconds: 7));
    },
  );
}
