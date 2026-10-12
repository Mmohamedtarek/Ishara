import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';

import '../support/fake_glove.dart';

/// Settings fixed for one scenario (language, theme).
class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// Talk's speech state fixed for one scenario.
class _FixedTalk extends TalkSpeech {
  new(this.fixed);
  final TalkSpeechState fixed;
  @override
  TalkSpeechState build() => fixed;
}

// Every async provider Talk reads gets its value before the first frame
// (DECISIONS 2026-10-11): the cast, the avatar runtime (no WebView in
// tests: the placeholder), and the conversation.
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

Widget _app(
  AppLanguage language,
  ThemeMode mode,
  TalkSpeechState talk,
  List<TalkMessage> Function(AppLanguage) feed,
) => ProviderScope(
  overrides: [
    appSettingsControllerProvider.overrideWith(
      () => _Fixed(AppSettings(language: language, themeMode: mode)),
    ),
    appRouterProvider.overrideWith(
      (ref) => buildRouter(initialLocation: AppRoutes.talk),
    ),
    gloveSourceProvider.overrideWithValue(FakeGloveSource()),
    glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
    keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
    avatarCastProvider.overrideWithValue(AsyncData(_cast)),
    avatarRuntimeProvider.overrideWithValue(AsyncData(_runtime())),
    conversationProvider.overrideWithValue(AsyncData(feed(language))),
    talkSpeechProvider.overrideWith(() => _FixedTalk(talk)),
  ],
  child: const IsharaApp(),
);

Future<void> _screen(
  String name,
  TalkSpeechState Function(AppLanguage) talk, {
  List<TalkMessage> Function(AppLanguage)? feed,
}) => goldenTest(
  '$name: EN / AR x light / dark',
  fileName: 'talk_$name',
  // entrances done; endless animations (pulse, bars) caught mid-way
  pumpBeforeTest: (t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await t.pump(const Duration(milliseconds: 200));
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
            child: _app(lang, mode, talk(lang), feed ?? (_) => const []),
          ),
    ],
  ),
);

/// A heard sentence as Talk shows it, word by word.
List<SignSegment> _sentence(AppLanguage l) => switch (l) {
  AppLanguage.en => const [
    SignSegment(['Hello,'], 'hello'),
    SignSegment(['the'], null),
    SignSegment(['doctor'], 'doctor'),
    SignSegment(['will'], null),
    SignSegment(['call'], 'call'),
    SignSegment(['you'], 'you'),
  ],
  AppLanguage.ar => const [
    SignSegment(['أهلاً،'], 'hello'),
    SignSegment(['الدكتور'], 'doctor'),
    SignSegment(['هيتصل'], null),
    SignSegment(['بيك'], null),
  ],
};

List<TalkMessage> _feed(AppLanguage l) {
  final now = DateTime.now();
  return switch (l) {
    AppLanguage.en => [
      TalkMessage(side: MessageSide.them, text: 'Hi, how are you?', at: now),
      TalkMessage(side: MessageSide.me, text: 'Hello thank you', at: now),
      TalkMessage(
        side: MessageSide.them,
        text: 'Hello, the doctor will call you',
        at: now,
      ),
    ],
    AppLanguage.ar => [
      TalkMessage(side: MessageSide.them, text: 'أهلاً، عامل إيه؟', at: now),
      TalkMessage(side: MessageSide.me, text: 'أهلاً شكراً', at: now),
      TalkMessage(
        side: MessageSide.them,
        text: 'أهلاً، الدكتور هيتصل بيك',
        at: now,
      ),
    ],
  };
}

Future<void> main() async {
  await _screen('idle', (_) => const TalkSpeechState());
  await _screen(
    'signing',
    (l) => TalkSpeechState(sentence: _sentence(l), active: 1, signing: true),
    feed: _feed,
  );
  await _screen(
    'listening_f2f',
    (_) => const TalkSpeechState(mic: MicState.listening, faceToFace: true),
  );
  await _screen(
    'mic_blocked',
    (_) => const TalkSpeechState(
      mic: MicState.permissionBlocked,
      privacyNotice: true,
    ),
  );
}
