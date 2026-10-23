import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';

import '../support/fake_glove.dart';
import '../support/fake_talk.dart';

class _Rig {
  new _(this.c, this.fakes, this.glove, this.perms);

  final ProviderContainer c;
  final TalkFakes fakes;
  final FakeGloveSource glove;
  final FakeGlovePermissions perms;

  TalkGlove get talk => c.read(talkGloveProvider.notifier);
  TalkGloveState get state => c.read(talkGloveProvider);
  FakeRecognitionFeed get feed => fakes.feed;
  List<String> get spoken => fakes.tts.spoken;
  List<TalkMessage> get messages =>
      c.read(conversationRepositoryProvider).messages;
  List<(String, LiveWordState)> get words => [
    for (final w in state.words) (w.text, w.state),
  ];

  static Future<_Rig> make({
    String spoken = 'en',
    String role = 'sign',
    bool paired = false,
    bool voice = true,
    bool connectedFirst = false,
    Duration timeout = const Duration(milliseconds: 150),
  }) async {
    final fakes = TalkFakes()..timeout = timeout;
    fakes.tts.hasVoice = voice;
    final glove = FakeGloveSource();
    if (connectedFirst) await glove.connect(glove.found.single);
    final perms = FakeGlovePermissions();
    final kv = MemoryKeyValueStore({
      'setup.spoken': spoken,
      'setup.role': role,
      if (paired) 'glove.id': 'g1',
      if (paired) 'glove.name': 'Ishara-3FA2',
    });
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(kv),
        gloveSourceProvider.overrideWithValue(glove),
        glovePermissionsProvider.overrideWithValue(perms),
        ...fakes.overrides,
      ],
    );
    addTearDown(() async {
      c.dispose();
      await fakes.feed.dispose();
      await glove.dispose();
    });
    if (connectedFirst) {
      // as in the app after Pair: the glove's status is already known
      // (and ready) when Talk starts
      c.listen(gloveStatusProvider, (_, _) {});
      await _until(
        () => c.read(gloveStatusProvider).value?.phase == GlovePhase.ready,
      );
    }
    // as the Talk screen does: a provider nobody listens to is paused
    c.listen(talkGloveProvider, (_, _) {});
    await _until(() => fakes.tts.languages.isNotEmpty);
    return _Rig._(c, fakes, glove, perms);
  }
}

Future<void> _until(bool Function() done, {int ms = 3000}) async {
  for (var i = 0; i < ms ~/ 5 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'condition never met');
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Decider events (AI-SPEC §5, §7; sign rule 6)', () {
    test('word: shown and spoken, in the voice language (S7-17)', () async {
      final r = await _Rig.make();
      r.feed.word('hello');
      expect(r.words, [('hello', LiveWordState.confirmed)]);
      expect(r.spoken, ['hello']);
      final ar = await _Rig.make(spoken: 'ar');
      ar.feed.word('thanks');
      expect(ar.words.single.$1, 'شكراً');
      expect(ar.spoken, ['شكراً']);
    });

    test(
      'tentative: shown, never spoken; confirm: normal and spoken',
      () async {
        final r = await _Rig.make();
        r.feed.tentative('water');
        expect(r.words, [('water', LiveWordState.tentative)]);
        expect(r.spoken, isEmpty);
        r.feed.confirm('water');
        expect(r.words, [('water', LiveWordState.confirmed)]);
        expect(r.spoken, ['water']);
      },
    );

    test('cancel: fades out, then is gone; never spoken', () async {
      final r = await _Rig.make();
      r.feed.tentative('yes');
      r.feed.cancel('yes');
      expect(r.words, [('yes', LiveWordState.cancelled)]);
      await _wait(TalkGlove.fadeOut.inMilliseconds + 100);
      expect(r.words, isEmpty);
      expect(r.spoken, isEmpty);
    });

    test('the labels come from the catalogue, the text from the spoken '
        'words (iloveyou → "I love you")', () async {
      final r = await _Rig.make();
      r.feed.word('iloveyou');
      expect(r.spoken, ['I love you']);
      expect(r.words.single.$1, 'I love you');
    });

    test('an unknown label is ignored (never a guess)', () async {
      final r = await _Rig.make();
      r.feed.word('notasign');
      expect(r.words, isEmpty);
      expect(r.spoken, isEmpty);
    });
  });

  group('Q-T1, S7-9: tapping a tentative word', () {
    test('confirms it and speaks it; a later cancel keeps it; a later '
        'confirm is not spoken again', () async {
      final r = await _Rig.make();
      r.feed.tentative('please');
      r.talk.confirmByTap(r.state.words.single.id);
      expect(r.words, [('please', LiveWordState.confirmed)]);
      expect(r.spoken, ['please']);
      expect(r.state.words.single.byUser, isTrue);
      r.feed.cancel('please');
      expect(r.words, [('please', LiveWordState.confirmed)]);
      r.feed.confirm('please');
      expect(r.spoken, ['please'], reason: 'not twice');
      expect(r.words, hasLength(1));
    });

    test('the Decider confirms it just before the tap (v3.3: a word signed '
        'alone confirms on rest): one word, spoken once', () async {
      final r = await _Rig.make();
      r.feed.tentative('please');
      final id = r.state.words.single.id;
      r.feed.confirm('please');
      r.talk.confirmByTap(id); // the tap lands on the now-confirmed word
      expect(r.words, [('please', LiveWordState.confirmed)]);
      expect(r.spoken, ['please'], reason: 'not twice');
      expect(r.state.words.single.byUser, isFalse);
    });

    test(
      'tapped, then the Decider confirms it on rest (v3.3): spoken once',
      () async {
        final r = await _Rig.make();
        r.feed.tentative('yes');
        r.talk.confirmByTap(r.state.words.single.id);
        r.feed.confirm('yes');
        expect(r.words, [('yes', LiveWordState.confirmed)]);
        expect(r.spoken, ['yes']);
      },
    );

    test('an older tapped word does not swallow a later real sign of the '
        'same word', () async {
      final r = await _Rig.make();
      r.feed.tentative('yes');
      r.talk.confirmByTap(r.state.words.single.id);
      r.feed.confirm('yes'); // the tapped word's own confirm: skipped
      // Later in the sentence: the faded "yes" was cleared away (Talk was
      // hidden), then the Decider confirms it on rest.
      r.feed.confirm('yes');
      expect(r.words, [
        ('yes', LiveWordState.confirmed),
        ('yes', LiveWordState.confirmed),
      ]);
      expect(r.spoken, ['yes', 'yes']);
    });

    test('tapped, the Decider cancels it, then the same word is signed '
        'again: the new one is shown', () async {
      final r = await _Rig.make();
      r.feed.tentative('no');
      r.talk.confirmByTap(r.state.words.single.id);
      r.feed
        ..cancel('no')
        ..tentative('no')
        ..confirm('no');
      expect(r.words, [
        ('no', LiveWordState.confirmed),
        ('no', LiveWordState.confirmed),
      ]);
      expect(r.spoken, ['no', 'no']);
    });

    test('a confirmed word can not be tapped again', () async {
      final r = await _Rig.make();
      r.feed.word('yes');
      r.talk.confirmByTap(r.state.words.single.id);
      expect(r.spoken, ['yes']);
    });

    test('a confirm whose tentative word was cleared starts the next '
        'sentence', () async {
      final r = await _Rig.make();
      r.feed.tentative('no');
      await r.talk.endSentence();
      r.feed.confirm('no');
      expect(r.words, [('no', LiveWordState.confirmed)]);
      expect(r.spoken, ['no']);
    });
  });

  group('Q-T2: the sentence and the feed', () {
    test('the conversation ends active_s after the last spoken word: '
        'confirmed words go to the feed, tentative ones are dropped '
        '(S7-20, S7-21)', () async {
      final r = await _Rig.make();
      r.feed.word('me');
      await _wait(100);
      r.feed.word('hungry');
      r.feed.tentative('water');
      await _wait(100);
      expect(r.messages, isEmpty, reason: 'the clock restarted');
      await _until(() => r.messages.isNotEmpty);
      expect(r.messages.single.side, MessageSide.me);
      expect(r.messages.single.text, 'me hungry');
      expect(r.words, isEmpty);
    });

    test('Clear moves the sentence to the feed; with only tentative words '
        'nothing goes', () async {
      final r = await _Rig.make(timeout: const Duration(seconds: 30));
      r.feed.word('hello');
      await r.talk.endSentence();
      expect(r.messages.single.text, 'hello');
      r.feed.tentative('yes');
      await r.talk.endSentence();
      expect(r.messages, hasLength(1));
      expect(r.words, isEmpty);
    });

    test('Speak repeats the sentence (S7-22: not with none)', () async {
      final r = await _Rig.make(timeout: const Duration(seconds: 30));
      await r.talk.speakSentence();
      expect(r.spoken, isEmpty);
      r.feed.word('thanks');
      r.feed.word('you');
      r.spoken.clear();
      final speaking = r.talk.speakSentence();
      expect(r.state.speaking, isTrue);
      await speaking;
      expect(r.state.speaking, isFalse);
      expect(r.spoken, ['thank you you']);
    });

    test('typed words join the sentence and are spoken when sent', () async {
      final r = await _Rig.make(timeout: const Duration(seconds: 30));
      r.feed.word('hello');
      r.talk.sendTyped('  my name is Sam ');
      expect(r.words.map((w) => w.$1), ['hello', 'my', 'name', 'is', 'Sam']);
      expect(r.spoken, ['hello', 'my name is Sam']);
      r.talk.sendTyped('   ');
      expect(r.words, hasLength(5));
      await r.talk.endSentence();
      expect(r.messages.single.text, 'hello my name is Sam');
    });

    test('a quick phrase: the sentence first, then the phrase on its own, '
        'spoken (S7-18)', () async {
      final r = await _Rig.make(timeout: const Duration(seconds: 30));
      r.feed.word('hello');
      await r.talk.quickPhrase('I need help, please.');
      expect(r.messages.map((m) => m.text), ['hello', 'I need help, please.']);
      expect(r.spoken.last, 'I need help, please.');
      expect(r.words, isEmpty);
    });
  });

  group('the voice (S7-11, S7-17, S7-23)', () {
    test('no voice for the spoken language: words shown, flag set', () async {
      final r = await _Rig.make(voice: false);
      expect(r.state.voiceMissing, isTrue);
    });

    test('changing the spoken language changes the voice', () async {
      final r = await _Rig.make();
      expect(r.fakes.tts.languages.last.name, 'en');
      await r.c
          .read(profileControllerProvider.notifier)
          .setSpoken(SpokenLanguage.ar);
      await _until(() => r.fakes.tts.languages.last.name == 'ar');
    });
  });

  group('the glove', () {
    test(
      'a recognizer failure shows D15 until the glove connects again',
      () async {
        final r = await _Rig.make();
        r.feed.fail();
        expect(r.state.recognitionFailed, isTrue);
        await r.glove.connect(r.glove.found.single);
        await _until(() => !r.state.recognitionFailed);
      },
    );

    test('S7-19: a drop → one reconnect to the paired glove, '
        '"Reconnecting…" meanwhile', () async {
      final r = await _Rig.make(paired: true);
      await r.glove.connect(r.glove.found.single);
      await _until(
        () => r.c.read(gloveStatusProvider).value?.phase == GlovePhase.ready,
      );
      r.glove.commands.clear();
      r.glove.dropLink();
      await _until(() => r.glove.commands.contains('scan'));
      await _until(
        () =>
            !r.state.reconnecting &&
            r.c.read(gloveStatusProvider).value?.phase == GlovePhase.ready,
      );
      expect(r.glove.commands.where((c) => c == 'scan'), hasLength(1));
    });

    test('no reconnect without the Bluetooth permission (no prompt)', () async {
      final r = await _Rig.make(paired: true);
      r.perms.alreadyGranted = false;
      await r.glove.connect(r.glove.found.single);
      await _until(
        () => r.c.read(gloveStatusProvider).value?.phase == GlovePhase.ready,
      );
      r.glove.commands.clear();
      r.glove.dropLink();
      await _wait(100);
      expect(r.glove.commands, isNot(contains('scan')));
      expect(r.perms.requests, 0);
      expect(r.state.reconnecting, isFalse);
    });

    test('a disconnect the user asked for is not a drop', () async {
      final r = await _Rig.make(paired: true);
      await r.glove.connect(r.glove.found.single);
      await _until(
        () => r.c.read(gloveStatusProvider).value?.phase == GlovePhase.ready,
      );
      r.glove.commands.clear();
      await r.glove.disconnect();
      await _wait(100);
      expect(r.glove.commands, ['disconnect']);
    });
  });

  test("Talk hidden (another tab): the glove's words are not shown or "
      'spoken', () async {
    final r = await _Rig.make();
    r.talk.setActive(active: false);
    r.feed.word('hello');
    expect(r.words, isEmpty);
    expect(r.spoken, isEmpty);
    r.talk.setActive(active: true);
    r.feed.word('yes');
    expect(r.spoken, ['yes']);
  });

  group('review fixes', () {
    test('the recognizer is rebuilt (glove source switch): Talk follows the '
        'new one', () async {
      final fakes = TalkFakes();
      var feed = FakeRecognitionFeed();
      final c = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(
            MemoryKeyValueStore({'setup.spoken': 'en'}),
          ),
          gloveSourceProvider.overrideWithValue(FakeGloveSource()),
          conversationTimeoutProvider.overrideWithValue(
            const AsyncData(Duration(seconds: 3)),
          ),
          textToSpeechProvider.overrideWithValue(fakes.tts),
          recognitionFeedProvider.overrideWith((ref) async => feed),
        ],
      );
      addTearDown(c.dispose);
      c.listen(talkGloveProvider, (_, _) {});
      await _until(() => fakes.tts.languages.isNotEmpty);
      final old = feed;
      feed = FakeRecognitionFeed();
      c.invalidate(recognitionFeedProvider);
      await _wait(20);
      await old.dispose();
      feed.word('hello');
      expect(fakes.tts.spoken, ['hello']);
      feed.fail();
      expect(c.read(talkGloveProvider).recognitionFailed, isTrue);
    });

    test('no voice (S7-11): nothing is spoken at all', () async {
      final r = await _Rig.make(
        voice: false,
        timeout: const Duration(seconds: 30),
      );
      r.feed.word('hello');
      r.talk.sendTyped('hi');
      await r.talk.speakSentence();
      await r.talk.quickPhrase('I need help, please.');
      expect(r.spoken, isEmpty);
      expect(r.messages.map((m) => m.text), [
        'hello hi',
        'I need help, please.',
      ]);
    });

    test('a glove already connected when Talk starts: its drop still gets '
        'the reconnect (S7-19)', () async {
      final r = await _Rig.make(paired: true, connectedFirst: true);
      r.glove.commands.clear();
      r.glove.dropLink();
      await _until(() => r.glove.commands.contains('scan'));
    });

    test('Talk hidden: faded words go (their confirm / cancel would be '
        'missed), confirmed ones stay', () async {
      final r = await _Rig.make(timeout: const Duration(seconds: 30));
      r.feed.word('me');
      r.feed.tentative('water');
      r.talk.setActive(active: false);
      await _wait(1);
      expect(r.words, [('me', LiveWordState.confirmed)]);
      r.talk.setActive(active: true);
      r.feed.confirm('water');
      expect(r.words.last, ('water', LiveWordState.confirmed));
    });
  });

  test('Talk closed while it is still starting: no state change after '
      'dispose (emulator, onboarding_test)', () async {
    final fakes = TalkFakes();
    final glove = FakeGloveSource();
    final timeout = Completer<Duration>();
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        gloveSourceProvider.overrideWithValue(glove),
        glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
        recognitionFeedProvider.overrideWithValue(AsyncData(fakes.feed)),
        textToSpeechProvider.overrideWithValue(fakes.tts),
        // the slow part of the start, as on a device
        conversationTimeoutProvider.overrideWith((_) => timeout.future),
      ],
    );
    final sub = c.listen(talkGloveProvider, (_, _) {});
    await _wait(20);
    sub.close();
    c.dispose();
    // the start goes on after Talk is gone: it must not touch the state
    timeout.complete(const Duration(seconds: 3));
    await _wait(20);
    expect(fakes.tts.languages, isEmpty);
    await fakes.feed.dispose();
    await glove.dispose();
  });

  test('the "me" message carries the clock time', () async {
    final r = await _Rig.make(timeout: const Duration(seconds: 30));
    final at = DateTime(2026, 10, 13, 9);
    r.talk.setClock(() => at);
    r.feed.word('yes');
    await r.talk.endSentence();
    expect(r.messages.single.at, at);
  });
}
