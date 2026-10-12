import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';

import '../support/fake_avatar_page.dart';
import '../support/fake_speech.dart';
import '../support/kit.dart';

/// A page that is up and ends every sign as soon as it starts.
class _QuickPage extends FakePage {
  @override
  Future<void> send(Map<String, Object?> command) async {
    await super.send(command);
    if (command['cmd'] case 'play' || 'noSign') {
      scheduleMicrotask(() => post('signEnded', {'id': command['id']}));
    }
  }
}

class _Rig {
  new _(this.c, this.stt, this.perms, this.page, this.kv);

  final ProviderContainer c;
  final FakeSpeechToText stt;
  final FakeMicPermissions perms;
  final FakePage page;
  final KeyValueStore kv;

  TalkSpeech get talk => c.read(talkSpeechProvider.notifier);
  TalkSpeechState get state => c.read(talkSpeechProvider);
  List<TalkMessage> get feed => c.read(conversationRepositoryProvider).messages;

  /// Signs sent to the avatar: a label, or null for "no sign".
  List<String?> get played => [
    for (final s in page.sent)
      if (s['cmd'] == 'play' || s['cmd'] == 'noSign') s['label'] as String?,
  ];

  /// Taps the mic and waits until the heard sentence is in the feed.
  Future<void> say() async {
    final before = feed.length;
    await talk.tapMic();
    await _until(() => feed.length > before);
  }

  static Future<_Rig> make({
    List<Object>? heard,
    SpeechSupport support = SpeechSupport.ready,
    FakeMicPermissions? perms,
    String spoken = 'en',
    String role = 'sign',
    bool avatarUp = true,
    bool catalogueFails = false,
  }) async {
    final library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
    final page = avatarUp ? _QuickPage() : FakePage();
    final avatar = AvatarController(
      page: page,
      library: library,
      libraryUrl: 'l',
      castUrl: 'c',
    );
    final kv = MemoryKeyValueStore({
      'setup.spoken': spoken,
      'setup.role': role,
    });
    final stt = FakeSpeechToText(heard: heard, support: support);
    final p = perms ?? FakeMicPermissions(current: MicPermission.granted);
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(kv),
        speechToTextProvider.overrideWithValue(stt),
        micPermissionsProvider.overrideWithValue(p),
        if (catalogueFails)
          signCatalogueProvider.overrideWith(
            (ref) async => throw StateError('signs.json missing'),
          ),
        avatarRuntimeProvider.overrideWith(
          (ref) async => AvatarRuntime(avatar, UnavailableAvatarSurface()),
        ),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await avatar.dispose();
    });
    if (avatarUp) {
      page.post('loaded');
      await Future<void>.delayed(Duration.zero);
      page.post('ready', {
        'character': 'nour',
        'signs': library.labels.toList(),
      });
      await Future<void>.delayed(Duration.zero);
    }
    return _Rig._(c, stt, p, page, kv);
  }
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'condition never met');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('speech → sign (sign rule 7: exact, longest phrase first)', () {
    test('EN: signs in order, unknown words keep the ready pose, the '
        'sentence goes to the feed', () async {
      final r = await _Rig.make(heard: ['Hi there, thank you']);
      await r.say();
      expect(r.played, ['hello', null, 'thanks']);
      expect(r.state.sentence.map((s) => s.text), [
        'Hi',
        'there,',
        'thank you',
      ]);
      expect(r.state.signing, isFalse);
      expect(r.feed.single.side, MessageSide.them);
      expect(r.feed.single.text, 'Hi there, thank you');
      expect(r.stt.calls, ['prepare en', 'listen en']);
    });

    test(
      'AR: phrases and gendered forms (S4-3), in the Arabic setting',
      () async {
        final r = await _Rig.make(
          spoken: 'ar',
          heard: ['السلام عليكم أنا جعانة ومحتاجة مية'],
        );
        await r.say();
        expect(r.played, ['hello', 'me', 'hungry', null, 'water']);
        expect(r.stt.calls, ['prepare ar', 'listen ar']);
      },
    );

    test('AR: hamza and taa marbuta forms normalize, never fuzzy', () async {
      final r = await _Rig.make(spoken: 'ar', heard: ['انا جعانه شكرا']);
      await r.say();
      expect(r.played, ['me', 'hungry', 'thanks']);
    });

    test('Q-T5 aliases only: hey, I, thank, doctors; "I love you" is one '
        'sign', () async {
      final r = await _Rig.make(heard: ['hey I love you thank doctors']);
      await r.say();
      expect(r.played, ['hello', 'iloveyou', 'thanks', 'doctor']);
    });

    test('removed aliases and near-misses get no sign (never a wrong '
        'one)', () async {
      final r = await _Rig.make(heard: ['my house okay helo thnks']);
      await r.say();
      expect(r.played, [null, null, null, null, null]);
      expect(r.feed.single.text, 'my house okay helo thnks');
    });

    test('an English word in the Arabic setting gets no sign', () async {
      final r = await _Rig.make(spoken: 'ar', heard: ['hello']);
      await r.say();
      expect(r.played, [null]);
    });

    test('the sign speed reaches the avatar', () async {
      final r = await _Rig.make(heard: ['yes']);
      r.c.read(signSpeedProvider.notifier).cycle();
      await r.say();
      final play = r.page.sent.lastWhere((s) => s['cmd'] == 'play');
      expect(play['speed'], .5);
    });

    test('Replay plays the sentence again, without a second feed '
        'message', () async {
      final r = await _Rig.make(heard: ['yes no']);
      await r.say();
      await r.talk.replay();
      expect(r.played, ['yes', 'no', 'yes', 'no']);
      expect(r.feed, hasLength(1));
    });

    test('Replay with nothing heard yet does nothing', () async {
      final r = await _Rig.make();
      await r.talk.replay();
      expect(r.played, isEmpty);
    });

    test('avatar not up: the caption still runs and the feed gets the '
        'sentence; nothing is queued for later', () async {
      final r = await _Rig.make(heard: ['yes'], avatarUp: false);
      await r.talk.tapMic();
      await _until(() => r.feed.isNotEmpty);
      expect(r.page.sent, isEmpty);
    });
  });

  group('the mic', () {
    test(
      'tap while listening stops; the words heard so far are used',
      () async {
        final r = await _Rig.make();
        r.stt.onStop = const SpeechFinal('yes');
        await r.talk.tapMic();
        expect(r.state.mic, MicState.listening);
        await r.talk.tapMic();
        await _until(() => r.feed.isNotEmpty);
        expect(r.stt.calls.last, 'stop');
        expect(r.played, ['yes']);
      },
    );

    test('a new tap while signing stops the sentence (it still goes to '
        'the feed)', () async {
      final r = await _Rig.make(heard: ['yes no'], avatarUp: false);
      await r.talk.tapMic();
      await _until(() => r.state.signing);
      await r.talk.tapMic();
      await _until(() => r.feed.isNotEmpty);
      expect(r.state.mic, MicState.listening);
    });

    test('nothing heard: D9 notice until the next tap', () async {
      final r = await _Rig.make(
        heard: [const SpeechFailed(SpeechError.noSpeech), 'yes'],
      );
      await r.talk.tapMic();
      await _until(() => r.state.notice == MicNotice.nothingHeard);
      expect(r.state.mic, MicState.idle);
      expect(r.feed, isEmpty);
      await r.say();
      expect(r.state.notice, MicNotice.none);
    });

    test('other failures: a generic notice', () async {
      final r = await _Rig.make(heard: [const SpeechFailed(SpeechError.other)]);
      await r.talk.tapMic();
      await _until(() => r.state.notice == MicNotice.failed);
    });

    test('the language disappears while listening', () async {
      final r = await _Rig.make(
        heard: [const SpeechFailed(SpeechError.languageMissing)],
      );
      await r.talk.tapMic();
      await _until(() => r.state.mic == MicState.languageMissing);
    });

    test('the recognizer reports a refused permission', () async {
      final r = await _Rig.make(
        heard: [const SpeechFailed(SpeechError.permission)],
      );
      await r.talk.tapMic();
      await _until(() => r.state.mic == MicState.permissionNeeded);
    });

    test(
      'no recognizer (D6) / no recognition for the language (D7, D8)',
      () async {
        var r = await _Rig.make(support: SpeechSupport.unavailable);
        await r.talk.tapMic();
        expect(r.state.mic, MicState.unavailable);
        r = await _Rig.make(support: SpeechSupport.languageMissing);
        await r.talk.tapMic();
        expect(r.state.mic, MicState.languageMissing);
        expect(r.stt.calls, ['prepare en']);
      },
    );
  });

  group('microphone permission', () {
    test('asked on the first tap; granted → listens', () async {
      final perms = FakeMicPermissions();
      final r = await _Rig.make(perms: perms, heard: ['yes']);
      await r.say();
      expect(perms.requests, 1);
      expect(r.played, ['yes']);
    });

    test('refused (D4): Allow asks again', () async {
      final perms = FakeMicPermissions(answer: MicPermission.denied);
      final r = await _Rig.make(perms: perms, heard: ['yes']);
      await r.talk.tapMic();
      expect(r.state.mic, MicState.permissionNeeded);
      expect(r.stt.calls, isEmpty, reason: 'never listens without it');
      perms.answer = MicPermission.granted;
      await r.talk.allowMic();
      await _until(() => r.feed.isNotEmpty);
      expect(perms.requests, 2);
    });

    test('refused for good (D5): Open settings; granted there → cleared on '
        'resume', () async {
      final perms = FakeMicPermissions(answer: MicPermission.permanentlyDenied);
      final r = await _Rig.make(perms: perms);
      await r.talk.tapMic();
      expect(r.state.mic, MicState.permissionBlocked);
      await r.talk.openSettings();
      expect(perms.settingsOpened, 1);
      await r.talk.recheck();
      expect(r.state.mic, MicState.permissionBlocked);
      perms.current = MicPermission.granted;
      await r.talk.recheck();
      expect(r.state.mic, MicState.idle);
    });

    test('recheck does nothing in other states', () async {
      final r = await _Rig.make();
      await r.talk.recheck();
      expect(r.state.mic, MicState.idle);
    });
  });

  group('Q-D4, Q-T3', () {
    test('"I speak" opens face to face, "I sign" does not; the button '
        'toggles', () async {
      expect((await _Rig.make(role: 'speak')).state.faceToFace, isTrue);
      final r = await _Rig.make();
      expect(r.state.faceToFace, isFalse);
      r.talk.toggleFaceToFace();
      expect(r.state.faceToFace, isTrue);
    });

    test('the privacy line shows from the first mic use until OK, and only '
        'once', () async {
      final r = await _Rig.make(heard: ['yes']);
      expect(r.state.privacyNotice, isFalse);
      await r.say();
      expect(r.state.privacyNotice, isTrue);
      expect(r.kv.getBool(TalkSpeech.kPrivacySeen), isTrue);
      r.talk.dismissPrivacy();
      expect(r.state.privacyNotice, isFalse);
      r.stt.heard.add('no');
      await r.say();
      expect(r.state.privacyNotice, isFalse);
    });

    test('a refused permission shows no privacy line yet', () async {
      final r = await _Rig.make(
        perms: FakeMicPermissions(answer: MicPermission.denied),
      );
      await r.talk.tapMic();
      expect(r.state.privacyNotice, isFalse);
    });
  });

  test('the catalogue fails to load: a notice, nothing signed, nothing '
      'guessed', () async {
    final r = await _Rig.make(heard: ['yes'], catalogueFails: true);
    await r.talk.tapMic();
    await _until(() => r.state.notice == MicNotice.failed);
    expect(r.played, isEmpty);
    expect(r.feed, isEmpty);
    expect(r.state.signing, isFalse);
  });

  test('a rebuilt avatar runtime gets the signs (no stale '
      'controller)', () async {
    final library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
    final pages = <_QuickPage>[];
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(
          MemoryKeyValueStore({'setup.spoken': 'en'}),
        ),
        speechToTextProvider.overrideWithValue(
          FakeSpeechToText(heard: ['yes', 'no']),
        ),
        micPermissionsProvider.overrideWithValue(
          FakeMicPermissions(current: MicPermission.granted),
        ),
        avatarRuntimeProvider.overrideWith((ref) async {
          final page = _QuickPage();
          pages.add(page);
          final avatar = AvatarController(
            page: page,
            library: library,
            libraryUrl: 'l',
            castUrl: 'c',
          );
          ref.onDispose(avatar.dispose);
          page.post('loaded');
          await Future<void>.delayed(Duration.zero);
          page.post('ready', {
            'character': 'nour',
            'signs': library.labels.toList(),
          });
          await Future<void>.delayed(Duration.zero);
          return AvatarRuntime(avatar, UnavailableAvatarSurface());
        }),
      ],
    );
    addTearDown(c.dispose);
    final repo = c.read(conversationRepositoryProvider);
    final talk = c.read(talkSpeechProvider.notifier);
    List<String?> played(FakePage p) => [
      for (final s in p.sent)
        if (s['cmd'] == 'play') s['label'] as String?,
    ];
    await talk.tapMic();
    await _until(() => repo.messages.length == 1);
    expect(played(pages.single), ['yes']);
    c.invalidate(avatarRuntimeProvider);
    await talk.tapMic();
    await _until(() => repo.messages.length == 2);
    expect(pages, hasLength(2));
    expect(played(pages.last), ['no']);
  });

  test('the feed message carries the clock time', () async {
    final r = await _Rig.make(heard: ['yes']);
    final at = DateTime(2026, 10, 12, 10, 5);
    r.talk.setClock(() => at);
    await r.say();
    expect(r.feed.single.at, at);
  });
}
