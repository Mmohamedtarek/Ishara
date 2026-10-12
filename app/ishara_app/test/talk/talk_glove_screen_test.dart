import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/presentation/talk_screen.dart';

import '../support/fake_glove.dart';
import '../support/fake_speech.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

class _Screen {
  final talk = TalkFakes();
  final glove = FakeGloveSource();
  final store = MemoryKeyValueStore({'setup.spoken': 'en'});
  bool ble = false;
  late Harness h;

  Future<void> pump(
    WidgetTester t, {
    bool connect = true,
    AppLanguage language = AppLanguage.en,
  }) async {
    addTearDown(rootBundle.clear);
    addTearDown(talk.feed.dispose);
    h = await pumpScreen(
      t,
      const TalkScreen(),
      language: language,
      harness: Harness(glove: glove, store: store),
      overrides: [
        ...talk.overrides,
        if (ble) activeGloveKindProvider.overrideWithValue(GloveSourceKind.ble),
        speechToTextProvider.overrideWithValue(FakeSpeechToText()),
        micPermissionsProvider.overrideWithValue(
          FakeMicPermissions(current: MicPermission.granted),
        ),
      ],
    );
    if (connect) {
      await t.runAsync(() => glove.connect(glove.found.single));
      await settle(t);
    }
  }
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('the live box: word, tentative "…", tap confirms and speaks '
      '(Q-T1)', (t) async {
    final s = _Screen();
    await s.pump(t);
    expect(
      find.text('Sign with your glove, words appear here'),
      findsOneWidget,
    );
    s.talk.feed.word('hello');
    s.talk.feed.tentative('water');
    await settle(t);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('water…'), findsOneWidget);
    expect(s.talk.tts.spoken, ['hello']);
    await tapIt(t, find.text('water…'));
    expect(find.text('water'), findsOneWidget);
    expect(s.talk.tts.spoken, ['hello', 'water']);
  });

  testWidgets('a tentative word is a labelled button for TalkBack (D17)', (
    t,
  ) async {
    final sem = t.ensureSemantics();
    final s = _Screen();
    await s.pump(t);
    s.talk.feed.tentative('yes');
    await settle(t);
    expect(
      find.bySemanticsLabel('yes, not sure yet. Double-tap to confirm.'),
      findsOneWidget,
    );
    sem.dispose();
  });

  testWidgets('cancel fades the word out', (t) async {
    final s = _Screen();
    await s.pump(t);
    s.talk.feed.tentative('yes');
    await settle(t);
    s.talk.feed.cancel('yes');
    await t.pump(const Duration(milliseconds: 400));
    await settle(t);
    expect(find.text('yes…'), findsNothing);
  });

  testWidgets('no glove: D13 with Connect → Pair; the chip says D10', (
    t,
  ) async {
    final s = _Screen();
    await s.pump(t, connect: false);
    expect(find.text('Connect your glove to sign.'), findsOneWidget);
    expect(find.text('Glove not connected'), findsOneWidget);
    await tapIt(t, _key('talk-live-action'));
    expect(find.text('route:/pair'), findsOneWidget);
  });

  testWidgets('no stored calibration: D14 with Calibrate now', (t) async {
    final s = _Screen()..glove.stored = false;
    await s.pump(t);
    expect(find.text('Calibrate your glove to start signing.'), findsOneWidget);
    await tapIt(t, _key('talk-live-action'));
    expect(find.text('route:/calibrate'), findsOneWidget);
  });

  testWidgets('recognizer failure: D15', (t) async {
    final s = _Screen();
    await s.pump(t);
    s.talk.feed.fail();
    await settle(t);
    expect(
      find.text('Sign recognition stopped. Reconnect the glove and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('the chip: connected with the real battery %; low battery '
      '(D12); USB: no %', (t) async {
    final s = _Screen();
    await s.pump(t);
    expect(find.text('Glove connected'), findsOneWidget);
    expect(find.text('78%'), findsOneWidget);
    await s.glove.disconnect();
    s.glove.battery = const BatteryEvent(BatteryLevel.low, volts: 3.38);
    await t.runAsync(() => s.glove.connect(s.glove.found.single));
    await settle(t);
    expect(find.text('Glove battery low'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    await s.glove.disconnect();
    s.glove.battery = const BatteryEvent(BatteryLevel.usb);
    await t.runAsync(() => s.glove.connect(s.glove.found.single));
    await settle(t);
    expect(find.text('Glove connected'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('chip: connected → Settings (S7-4)', (t) async {
    final s = _Screen();
    await s.pump(t);
    await tapIt(t, _key('talk-glove-chip'));
    expect(find.text('route:/settings'), findsOneWidget);
  });

  testWidgets('Speak is disabled with no sentence; Type sends and speaks; '
      'Clear moves the sentence to the feed (Q-T2)', (t) async {
    final s = _Screen();
    await s.pump(t);
    await tapIt(t, _key('talk-speak'));
    expect(s.talk.tts.spoken, isEmpty);
    await tapIt(t, _key('talk-type'));
    await t.enterText(find.byKey(const ValueKey('talk-type-field')), 'hi Sam');
    await tapIt(t, _key('talk-type-send'));
    expect(s.talk.tts.spoken, ['hi Sam']);
    expect(find.text('Sam'), findsOneWidget);
    await tapIt(t, _key('talk-speak'));
    expect(s.talk.tts.spoken.last, 'hi Sam');
    await tapIt(t, _key('talk-clear'));
    expect(find.text('hi Sam'), findsOneWidget, reason: 'the feed');
    expect(find.text('Spoken'), findsOneWidget);
  });

  testWidgets('SOS speaks the agreed sentence (D23), adds it to the feed, '
      'shows D2', (t) async {
    final s = _Screen();
    await s.pump(t);
    await tapIt(t, _key('talk-quick-sos'));
    expect(s.talk.tts.spoken, ['I need help, please.']);
    expect(find.text('SOS spoken out loud.'), findsOneWidget);
    final repo = ProviderScope.containerOf(t.element(find.byType(TalkScreen)))
        .read(conversationRepositoryProvider);
    expect(repo.messages.single.text, 'I need help, please.');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('a quick phrase speaks its full text (I am deaf…)', (t) async {
    final s = _Screen();
    await s.pump(t);
    await tapIt(t, _key('talk-quick-4'));
    expect(s.talk.tts.spoken, ['I am deaf. I use this app to talk.']);
  });

  testWidgets('face to face: the card shows the confirmed words', (t) async {
    final s = _Screen();
    await s.pump(t);
    await tapIt(t, _key('talk-f2f'));
    s.talk.feed.word('me');
    s.talk.feed.word('hungry');
    s.talk.feed.tentative('water');
    await settle(t);
    expect((t.widget(_key('talk-mic-signs')) as Text).data, 'me hungry');
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('no voice for the spoken language: D16', (t) async {
    final s = _Screen();
    s.talk.tts.hasVoice = false;
    await s.pump(t);
    expect(
      find.text(
        'This phone has no English voice, so words are shown but not spoken.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Mock button: shown in debug with the mock glove '
      '(S7-24), opens the sheet', (t) async {
    final s = _Screen();
    await s.pump(t);
    expect(_key('talk-mock'), findsOneWidget);
    await tapIt(t, _key('talk-mock'));
    expect(_key('mock-person'), findsOneWidget);
    expect(_key('mock-file-sentences'), findsOneWidget);
  });

  testWidgets('the Mock button: hidden with the real glove', (t) async {
    final s = _Screen()..ble = true;
    await s.pump(t);
    expect(_key('talk-mock'), findsNothing);
  });

  testWidgets('the screen stays on while Talk shows (S7-5)', (t) async {
    final s = _Screen();
    await s.pump(t);
    expect(s.talk.screen.on, isTrue);
    await t.pumpWidget(const SizedBox());
    expect(s.talk.screen.calls.last, isFalse);
  });

  testWidgets("Talk gone (another route): the glove's words are not spoken", (
    t,
  ) async {
    final s = _Screen();
    await s.pump(t);
    s.h.router.go('/settings');
    await settle(t);
    expect(find.text('route:/settings'), findsOneWidget);
    s.talk.feed.word('hello');
    await settle(t);
    expect(s.talk.tts.spoken, isEmpty);
  });

  testWidgets('Arabic: the live box and buttons', (t) async {
    final s = _Screen()..store.setString('setup.spoken', 'ar').ignore();
    await s.pump(t, language: AppLanguage.ar);
    s.talk.feed.word('thanks');
    await settle(t);
    expect(
      find.descendant(
        of: _key('talk-live-words'),
        matching: find.text('شكراً'),
      ),
      findsOneWidget,
    );
    expect(find.text('انطق'), findsOneWidget);
  });
}
