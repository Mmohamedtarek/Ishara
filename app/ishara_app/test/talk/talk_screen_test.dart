import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/presentation/talk_screen.dart';

import '../support/fake_speech.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

class _Talk {
  new({List<Object>? heard, SpeechSupport? support, FakeMicPermissions? perms})
    : stt = FakeSpeechToText(
        heard: heard,
        support: support ?? SpeechSupport.ready,
      ),
      perms = perms ?? FakeMicPermissions(current: MicPermission.granted);

  final FakeSpeechToText stt;
  final FakeMicPermissions perms;
  final talk = TalkFakes();

  Future<Harness> pump(
    WidgetTester t, {
    AppLanguage language = AppLanguage.en,
    Map<String, Object> stored = const {},
    List<TalkMessage>? feed,
  }) {
    // An asset load started in one test's fake clock never finishes in the
    // next one; rootBundle caches it, so each test starts with a clean one.
    addTearDown(rootBundle.clear);
    return pumpScreen(
      t,
      const TalkScreen(),
      language: language,
      harness: Harness(store: MemoryKeyValueStore({...stored})),
      overrides: [
        speechToTextProvider.overrideWithValue(stt),
        micPermissionsProvider.overrideWithValue(perms),
        ...talk.overrides,
        if (feed != null)
          conversationProvider.overrideWithValue(AsyncData(feed)),
      ],
    );
  }
}

Finder _text(String s) => find.textContaining(s, findRichText: true);

/// Pumps until [f] finds something (files load on the real event loop).
Future<void> _until(WidgetTester t, Finder f) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await settle(t, n: 1);
  }
  expect(f, findsWidgets);
}

/// Lets the caption-only timing (no WebView in tests) run to its end.
Future<void> _finishSigning(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 500));
    await settle(t, n: 1);
  }
}

void main() {
  testWidgets('idle: who it is for, mic ready, hint, the idle caption, '
      '"Today"', (t) async {
    await _Talk().pump(t);
    expect(find.byKey(const ValueKey('screen-talk')), findsOneWidget);
    expect(find.text('PERSON IN FRONT OF YOU'), findsOneWidget);
    expect(find.text('Mic ready'), findsOneWidget);
    expect(_text('Tap the mic and speak.'), findsOneWidget);
    expect(_text('Nour signs it instantly.'), findsOneWidget);
    expect(find.text('Nour will sign what they say'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('speech → sign: the caption shows the words, the feed gets '
      '"Signed by Nour"', (t) async {
    final talk = _Talk(heard: ['Hi there, thank you']);
    await talk.pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    await _until(t, find.text('Hi'));
    expect(find.text('Hi'), findsOneWidget);
    expect(find.text('there,'), findsOneWidget);
    expect(find.text('thank you'), findsNothing, reason: 'one chip per word');
    expect(find.text('thank'), findsOneWidget);
    await _finishSigning(t);
    expect(find.text('Hi there, thank you'), findsOneWidget);
    expect(find.text('Signed by Nour'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('the mic button is labelled for screen readers (D18)', (t) async {
    final h = t.ensureSemantics();
    await _Talk().pump(t);
    expect(find.bySemanticsLabel('Tap and speak'), findsOneWidget);
    h.dispose();
  });

  testWidgets('listening: "Listening…" in the state and the hint; a second '
      'tap stops', (t) async {
    final talk = _Talk();
    await talk.pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(find.text('Listening…'), findsNWidgets(2));
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(talk.stt.calls.last, 'stop');
    expect(
      find.text(
        "Didn't catch that. Tap the mic and try again.\n"
        'Try saying it in a short sentence.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('permission refused (D4): Allow asks again', (t) async {
    final perms = FakeMicPermissions(answer: MicPermission.denied);
    await _Talk(perms: perms).pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(
      find.text(
        'Allow Ishara to use the microphone so it can hear the person '
        "you're talking to.",
      ),
      findsOneWidget,
    );
    await tapIt(t, find.byKey(const ValueKey('talk-mic-allow')));
    expect(perms.requests, 2);
  });

  testWidgets('refused for good (D5): Open settings', (t) async {
    final perms = FakeMicPermissions(answer: MicPermission.permanentlyDenied);
    await _Talk(perms: perms).pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(
      find.text(
        "Turn on the microphone permission for Ishara in your phone's "
        'settings.',
      ),
      findsOneWidget,
    );
    await tapIt(t, find.byKey(const ValueKey('talk-mic-settings')));
    expect(perms.settingsOpened, 1);
  });

  testWidgets('no recognizer (D6); Arabic missing (D8)', (t) async {
    await _Talk(support: SpeechSupport.unavailable).pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(
      find.text("Speech recognition isn't available on this phone."),
      findsOneWidget,
    );
  });

  testWidgets('Arabic voice, recognizer lacks Arabic: D8', (t) async {
    await _Talk(support: SpeechSupport.languageMissing)
        .pump(t, stored: {'setup.spoken': 'ar'});
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(
      find.text("This phone can't recognize Arabic speech yet."),
      findsOneWidget,
    );
  });

  testWidgets('English voice, recognizer lacks English: D7', (t) async {
    await _Talk(support: SpeechSupport.languageMissing)
        .pump(t, stored: {'setup.spoken': 'en'});
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(
      find.text("This phone can't recognize English speech yet."),
      findsOneWidget,
    );
  });

  testWidgets('other recognizer failures: a generic message', (t) async {
    await _Talk(heard: [const SpeechFailed(SpeechError.other)]).pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
  });

  testWidgets('face to face: the card label, "Waiting for signs…" and the '
      'toast; the button is a toggle', (t) async {
    final h = t.ensureSemantics();
    await _Talk().pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-f2f')));
    expect(find.text('FOR THE HEARING PERSON'), findsOneWidget);
    expect(find.text('Waiting for signs…'), findsOneWidget);
    expect(find.text('Tap the mic to reply'), findsOneWidget);
    expect(
      find.text('Face to face: the mic card now faces the person opposite you'),
      findsOneWidget,
    );
    expect(
      t.getSemantics(find.byKey(const ValueKey('talk-f2f'))),
      matchesSemantics(
        label: 'Face to face',
        isButton: true,
        hasToggledState: true,
        isToggled: true,
        hasTapAction: true,
      ),
    );
    await t.pump(const Duration(seconds: 3));
    await tapIt(t, find.byKey(const ValueKey('talk-f2f')));
    expect(find.text('Face to face off'), findsOneWidget);
    expect(find.text('PERSON IN FRONT OF YOU'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    h.dispose();
  });

  testWidgets('"I speak" (Q-D4) opens face to face', (t) async {
    await _Talk().pump(t, stored: {'setup.role': 'speak'});
    expect(find.text('FOR THE HEARING PERSON'), findsOneWidget);
  });

  testWidgets('speed: 1x → 0.5x → 1.5x, with the toast', (t) async {
    await _Talk().pump(t);
    expect(find.text('1x'), findsOneWidget);
    await tapIt(t, find.byKey(const ValueKey('talk-speed')));
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('Sign speed 0.5x'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    await tapIt(t, find.byKey(const ValueKey('talk-speed')));
    expect(find.text('1.5x'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('the privacy line (D19): after the first mic use, until OK; '
      'never again', (t) async {
    final talk = _Talk(heard: ['yes', 'no']);
    final h = await talk.pump(t);
    expect(find.byKey(const ValueKey('talk-privacy')), findsNothing);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(find.byKey(const ValueKey('talk-privacy')), findsOneWidget);
    await _finishSigning(t);
    await tapIt(t, find.byKey(const ValueKey('talk-privacy-ok')));
    expect(find.byKey(const ValueKey('talk-privacy')), findsNothing);
    expect(h.store.getBool('talk.privacySeen'), isTrue);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(find.byKey(const ValueKey('talk-privacy')), findsNothing);
    await _finishSigning(t);
  });

  testWidgets('Replay plays the last sentence again (caption lights up)', (
    t,
  ) async {
    await _Talk(heard: ['yes']).pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    await _finishSigning(t);
    expect(find.text('Signing'), findsNothing);
    await tapIt(t, find.byKey(const ValueKey('talk-replay')));
    await _until(t, find.text('Signing'));
    expect(find.text('Signing'), findsOneWidget);
    await _finishSigning(t);
    expect(find.text('Signed by Nour'), findsOneWidget, reason: 'not twice');
  });

  testWidgets("the feed: today's messages only; identical messages both "
      'show', (t) async {
    final now = DateTime.now();
    final m = TalkMessage(side: MessageSide.me, text: 'yes', at: now);
    await _Talk().pump(
      t,
      feed: [
        TalkMessage(
          side: MessageSide.them,
          text: 'yesterday',
          at: now.subtract(const Duration(days: 1)),
        ),
        m,
        m,
      ],
    );
    expect(find.text('yesterday'), findsNothing);
    expect(find.text('yes'), findsNWidgets(2));
    expect(find.text('Spoken'), findsNWidgets(2));
  });

  testWidgets('nothing heard in Arabic: D9 and the short-sentence hint '
      '(D24, draft)', (t) async {
    await _Talk(heard: [const SpeechFailed(SpeechError.noSpeech)])
        .pump(t, language: AppLanguage.ar);
    await tapIt(t, find.byKey(const ValueKey('talk-mic')));
    expect(find.textContaining('جرّب تقولها في جملة قصيرة.'), findsOneWidget);
  });

  testWidgets('Arabic, RTL: the Arabic hint and the idle caption', (t) async {
    await _Talk().pump(t, language: AppLanguage.ar);
    expect(
      Directionality.of(t.element(find.byKey(const ValueKey('talk-mic')))),
      TextDirection.rtl,
    );
    expect(find.text('الميكروفون جاهز'), findsOneWidget);
    expect(find.text('النهارده'), findsOneWidget);
  });

  // S7-15: the prototype's 44 px icon buttons and 40 px language toggle are
  // kept (under Android's 48 dp guideline, by the user's decision).
  testWidgets('every tap target has a label', (t) async {
    final h = t.ensureSemantics();
    await _Talk().pump(t);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    h.dispose();
  });
}
