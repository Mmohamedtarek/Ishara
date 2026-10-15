import 'dart:convert';
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
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';

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

/// Signed in as Mona (the fake's state, fixed).
class _SignedIn extends FakeAuthRepository {
  new() : super(delay: Duration.zero);
  @override
  AuthUser? get currentUser =>
      const AuthUser(id: 'u1', email: 'mona@example.com', name: 'Mona');
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

/// Today 09:00 (2 messages) and yesterday 18:02: titles that never change.
Map<String, Object> _history() {
  final n = DateTime.now();
  final t0 = DateTime(n.year, n.month, n.day, 9);
  final y = t0.subtract(const Duration(days: 1));
  return {
    'talk.messages': jsonEncode([
      {
        'side': 'them',
        'text': 'Where is the pharmacy?',
        'at': DateTime(y.year, y.month, y.day, 18, 2).toIso8601String(),
        'conversation': 'c1',
      },
      {
        'side': 'them',
        'text': 'Hello, the doctor will call you',
        'at': t0.toIso8601String(),
        'conversation': 'c2',
      },
      {
        'side': 'me',
        'text': 'أنا جعانة',
        'at': t0.add(const Duration(minutes: 1)).toIso8601String(),
        'conversation': 'c2',
      },
    ]),
  };
}

final Map<String, String> _contacts = {
  'sos.contacts': jsonEncode([
    {'name': 'Mona', 'phone': '+201012345678'},
    {'name': 'Ali', 'phone': '+201123456789'},
  ]),
};

final Map<String, String> _phrases = {
  'phrases.all': jsonEncode([
    {
      'id': 'p1',
      'text': 'Where is the pharmacy?',
      'lang': 'en',
      'createdAt': '2026-10-14T09:00:00Z',
      'updatedAt': '2026-10-14T09:00:00Z',
      'deleted': false,
    },
  ]),
};

Widget _app(
  AppLanguage language,
  ThemeMode mode, {
  required String route,
  Map<String, Object> store = const {},
  bool signedIn = false,
  FakeLocation? location,
}) => ProviderScope(
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
      MemoryKeyValueStore({'setup.spoken': 'en', ...store}),
    ),
    authRepositoryProvider.overrideWithValue(
      signedIn ? _SignedIn() : FakeAuthRepository(delay: Duration.zero),
    ),
    avatarCastProvider.overrideWithValue(AsyncData(_cast)),
    avatarRuntimeProvider.overrideWithValue(AsyncData(_runtime())),
    appVersionProvider.overrideWithValue(const AsyncData('1.0.0 (1)')),
    speechToTextProvider.overrideWithValue(FakeSpeechToText()),
    micPermissionsProvider.overrideWithValue(
      FakeMicPermissions(current: MicPermission.granted),
    ),
    ...TalkFakes().overrides,
    ...SosFakes(location: location ?? FakeLocation()).overrides,
  ],
  child: const IsharaApp(),
);

Future<void> _golden(
  String name, {
  required String route,
  Map<String, Object> store = const {},
  bool signedIn = false,
  FakeLocation? location,
  Future<void> Function(WidgetTester t)? act,
}) => goldenTest(
  '$name: EN / AR x light / dark',
  fileName: 'step9_$name',
  pumpBeforeTest: (t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await t.pump(const Duration(milliseconds: 200));
    }
    if (act != null) await act(t);
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
              store: store,
              signedIn: signedIn,
              location: location,
            ),
          ),
    ],
  ),
);

/// Taps every scenario's widget with [key] (one per phone).
Future<void> Function(WidgetTester) _tapAll(String key) => (t) async {
  for (final e in find.byKey(ValueKey(key)).evaluate().toList()) {
    await t.tap(find.byWidget(e.widget).first);
  }
  // past the 2.4 s toast: the sheet alone on the image, no timer left
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
};

Future<void> main() async {
  // History
  await _golden('history_list', route: AppRoutes.history, store: _history());
  await _golden('history_empty', route: AppRoutes.history);
  await _golden(
    'history_search',
    route: AppRoutes.history,
    store: _history(),
    act: (t) async {
      for (final e in find.byKey(const ValueKey('search-field')).evaluate()) {
        await t.enterText(find.byWidget(e.widget).first, 'انا جعانه');
      }
      await t.pump(const Duration(milliseconds: 300));
    },
  );
  await _golden(
    'history_starred',
    route: AppRoutes.history,
    store: {..._history(), ..._phrases},
    act: _tapAll('seg-1'),
  );
  await _golden(
    'history_conversation',
    route: AppRoutes.conversation('c2'),
    store: {..._history(), ..._phrases},
  );
  // Settings
  await _golden('settings_guest', route: AppRoutes.settings);
  await _golden(
    'settings_signed_in',
    route: AppRoutes.settings,
    signedIn: true,
    store: _contacts,
  );
  await _golden('privacy', route: AppRoutes.privacy);
  await _golden('about', route: AppRoutes.about);
  // Avatar studio
  await _golden('avatar_studio', route: AppRoutes.avatarStudio);
  // SOS
  await _golden(
    'emergency_contacts',
    route: AppRoutes.emergencyContacts,
    store: _contacts,
  );
  await _golden(
    'sos_contacts',
    route: AppRoutes.talk,
    store: _contacts,
    location: FakeLocation(
      fresh: Fix(
        latitude: 30.04442,
        longitude: 31.235712,
        accuracyMeters: 12,
        at: DateTime(2026, 10, 14, 18, 2),
      ),
    ),
    act: _tapAll('talk-quick-sos'),
  );
  await _golden(
    'sos_no_contacts',
    route: AppRoutes.talk,
    location: FakeLocation(access: LocationAccess.denied),
    act: _tapAll('talk-quick-sos'),
  );
}
