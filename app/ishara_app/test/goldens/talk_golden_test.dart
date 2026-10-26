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
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';

import '../support/fake_glove.dart';
import '../support/fake_talk.dart';

/// Settings fixed for one scenario (language, theme).
class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// Talk's glove → text state fixed for one scenario.
class _FixedGlove extends TalkGlove {
  new(this.fixed);
  final TalkGloveState fixed;
  @override
  TalkGloveState build() => fixed;
}

/// Talk's speech state fixed for one scenario.
class _FixedTalk extends TalkSpeech {
  new(this.fixed, {this.levelNow = 0});
  final TalkSpeechState fixed;
  final double levelNow;
  @override
  TalkSpeechState build() {
    setLevelForTest(levelNow);
    return fixed;
  }

  // the state is fixed: a press only moves the mic (slide to cancel)
  @override
  Future<void> pressMic() async {}
  @override
  Future<void> releaseMic({bool checkLength = true}) async {}
  @override
  Future<void> cancelMic() async {}
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

/// A glove past the three checks (Pair "connected"), with or without a
/// stored calibration.
FakeGloveSource _connected({bool stored = true}) {
  final g = FakeGloveSource(stored: stored);
  g.connect(g.found.single).ignore();
  return g;
}

Widget _app(
  AppLanguage language,
  ThemeMode mode,
  TalkSpeechState talk,
  List<TalkMessage> Function(AppLanguage) feed,
  TalkGloveState glove,
  FakeGloveSource Function() source, {
  bool tapMode = false,
  double level = 0,
}) => ProviderScope(
  overrides: [
    appSettingsControllerProvider.overrideWith(
      () => _Fixed(
        AppSettings(language: language, themeMode: mode, micTap: tapMode),
      ),
    ),
    appRouterProvider.overrideWith(
      (ref) => buildRouter(initialLocation: AppRoutes.talk),
    ),
    gloveSourceProvider.overrideWithValue(source()),
    // the product screen: no developer panel (it shows only with the mock)
    activeGloveKindProvider.overrideWithValue(GloveSourceKind.ble),
    glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
    keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
    avatarCastProvider.overrideWithValue(AsyncData(_cast)),
    avatarRuntimeProvider.overrideWithValue(AsyncData(_runtime())),
    conversationProvider.overrideWithValue(AsyncData(feed(language))),
    talkSpeechProvider.overrideWith(() => _FixedTalk(talk, levelNow: level)),
    talkGloveProvider.overrideWith(() => _FixedGlove(glove)),
    ...TalkFakes().overrides,
  ],
  child: const IsharaApp(),
);

Future<void> _screen(
  String name,
  TalkSpeechState Function(AppLanguage) talk, {
  List<TalkMessage> Function(AppLanguage)? feed,
  TalkGloveState Function(AppLanguage)? glove,
  FakeGloveSource Function()? source,
  bool tapMode = false,
  double level = 0,
  bool slideToCancel = false,
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
    if (slideToCancel) {
      // hold each mic and slide it toward the start side, past the cancel
      // distance ("Release to cancel"); never let go
      final mics = find.byKey(const ValueKey('talk-mic'));
      for (var i = 0; i < mics.evaluate().length; i++) {
        final mic = mics.at(i);
        final rtl = Directionality.of(t.element(mic)) == TextDirection.rtl;
        final g = await t.startGesture(t.getCenter(mic));
        await g.moveBy(Offset(rtl ? 60 : -60, 0));
        await g.moveBy(Offset(rtl ? 60 : -60, 0));
      }
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
            child: _app(
              lang,
              mode,
              talk(lang),
              feed ?? (_) => const [],
              glove?.call(lang) ?? const TalkGloveState(),
              source ?? _connected,
              tapMode: tapMode,
              level: level,
            ),
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

/// The user's live words: confirmed ones and a tentative one ("…").
TalkGloveState _words(AppLanguage l) {
  final ar = l == AppLanguage.ar;
  LiveWord w(int id, String en, String a, LiveWordState s) => LiveWord(
    id: id,
    label: en,
    text: ar ? a : en,
    spoken: ar ? a : en,
    state: s,
  );
  return TalkGloveState(
    words: [
      w(1, 'me', 'أنا', LiveWordState.confirmed),
      w(2, 'hungry', 'جعان', LiveWordState.confirmed),
      w(3, 'water', 'مية', LiveWordState.tentative),
    ],
  );
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
    (_) => TalkSpeechState(
      mic: MicState.listening,
      faceToFace: true,
      recordingSince: DateTime(2026, 10, 26),
    ),
    glove: _words,
    level: .6,
  );
  // hold to talk (2026-10-26): recording, sliding to cancel, tap mode,
  // released too soon, waiting for the last words
  final recording = TalkSpeechState(
    mic: MicState.listening,
    recordingSince: DateTime(2026, 10, 26),
  );
  await _screen('recording', (_) => recording, level: .6);
  await _screen(
    'recording_cancel',
    (_) => recording,
    level: .3,
    slideToCancel: true,
  );
  await _screen('recording_tap', (_) => recording, level: .6, tapMode: true);
  await _screen(
    'too_short',
    (_) => const TalkSpeechState(notice: MicNotice.tooShort),
  );
  await _screen(
    'finishing',
    (_) => const TalkSpeechState(mic: MicState.finishing),
  );
  await _screen('idle_tap', (_) => const TalkSpeechState(), tapMode: true);
  await _screen(
    'glove_words',
    (_) => const TalkSpeechState(),
    glove: _words,
    feed: _feed,
  );
  await _screen(
    'no_glove',
    (_) => const TalkSpeechState(),
    source: FakeGloveSource.new,
  );
  await _screen(
    'no_calibration',
    (_) => const TalkSpeechState(),
    source: () => _connected(stored: false),
  );
  await _screen(
    'mic_blocked',
    (_) => const TalkSpeechState(
      mic: MicState.permissionBlocked,
      privacyNotice: true,
    ),
  );
}
