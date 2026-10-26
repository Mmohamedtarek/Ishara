import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/device/haptics.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/presentation/talk_screen.dart';

import '../support/fake_speech.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

class _Haptics implements Haptics {
  new(this.pulses);
  final List<String> pulses;
  @override
  Future<void> tap() async => pulses.add('tap');
  @override
  Future<void> short() async => pulses.add('short');
  @override
  Future<void> long() async => pulses.add('long');
}

class _Talk {
  new({
    List<Object>? heard,
    SpeechSupport? support,
    FakeMicPermissions? perms,
    bool untilStop = false,
  }) : stt = FakeSpeechToText(
         heard: heard,
         support: support ?? SpeechSupport.ready,
         untilStop: untilStop,
       ),
       perms = perms ?? FakeMicPermissions(current: MicPermission.granted);

  final FakeSpeechToText stt;
  final FakeMicPermissions perms;
  final talk = TalkFakes();

  /// Haptic pulses felt ('tap', 'short', 'long').
  final pulses = <String>[];

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
        hapticsProvider.overrideWithValue(_Haptics(pulses)),
        ...talk.overrides,
        if (feed != null)
          conversationProvider.overrideWithValue(AsyncData(feed)),
      ],
    );
  }
}

Finder _text(String s) => find.textContaining(s, findRichText: true);

final Finder _mic = find.byKey(const ValueKey('talk-mic'));

/// The mic's semantics node in tap mode.
Finder _micSemantics() =>
    find.bySemanticsLabel(RegExp(r'^(Start recording|Stop and send)$'));

/// The mic's grow factor.
double _scale(WidgetTester t) => t
    .widget<AnimatedScale>(
      find.ancestor(of: _mic, matching: find.byType(AnimatedScale)),
    )
    .scale;

/// Presses the mic and keeps it held (hold to talk).
Future<TestGesture> _press(WidgetTester t) async {
  final g = await t.startGesture(t.getCenter(_mic));
  await settle(t, n: 3);
  return g;
}

/// Holds the mic for [hold], then lets go.
Future<void> _hold(
  WidgetTester t, {
  Duration hold = const Duration(seconds: 1),
}) async {
  final g = await _press(t);
  await t.pump(hold);
  await g.up();
  await settle(t, n: 3);
}

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
    expect(_text('Hold the mic and speak.'), findsOneWidget);
    expect(_text('Nour signs it instantly.'), findsOneWidget);
    expect(find.text('Nour will sign what they say'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('speech → sign: the caption shows the words, the feed gets '
      '"Signed by Nour"', (t) async {
    final talk = _Talk(heard: ['Hi there, thank you']);
    await talk.pump(t);
    await _hold(t);
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

  testWidgets('the mic button is labelled for screen readers (TV3)', (t) async {
    final h = t.ensureSemantics();
    await _Talk().pump(t);
    expect(find.bySemanticsLabel('Hold to talk'), findsOneWidget);
    h.dispose();
  });

  group('hold to talk (2026-10-26)', () {
    testWidgets('press: recording at once, with a short haptic, the mic '
        'grows, "Listening…", a timer, "Slide to cancel" and a live level; '
        'release: stops and signs the words', (t) async {
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      expect(talk.stt.listening, isTrue);
      expect(talk.pulses, ['tap']);
      expect(find.text('Listening…'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('‹ Slide to cancel'), findsOneWidget);
      expect(_scale(t), 1.3, reason: 'the mic grows');
      double bar() => t
          .widget<Transform>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('talk-mic-level')),
                  matching: find.byType(Transform),
                )
                .at(2),
          )
          .transform
          .storage[5];
      final quiet = bar();
      talk.stt.level(.9);
      await t.pump();
      expect(bar(), greaterThan(quiet), reason: 'live level');
      await t.pump(const Duration(seconds: 2));
      expect(find.text('0:02'), findsOneWidget);
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'stop');
      expect(_scale(t), 1);
      await _until(t, find.text('hello'));
      await _finishSigning(t);
      expect(find.text('Signed by Nour'), findsOneWidget);
    });

    testWidgets('slide to cancel: "Release to cancel"; letting go throws '
        'the recording away', (t) async {
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      await t.pump(const Duration(seconds: 1));
      await g.moveBy(const Offset(-40, 0));
      await t.pump();
      expect(find.text('‹ Slide to cancel'), findsOneWidget);
      await g.moveBy(const Offset(-60, 0));
      await t.pump();
      expect(find.text('Release to cancel'), findsOneWidget);
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'cancel');
      expect(find.text('Mic ready'), findsOneWidget);
      expect(find.text('Signed by Nour'), findsNothing);
      expect(talk.stt.heard, ['hello'], reason: 'nothing was taken');
    });

    testWidgets('slid back before letting go: sent as usual', (t) async {
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      await t.pump(const Duration(seconds: 1));
      await g.moveBy(const Offset(-100, 0));
      await t.pump();
      await g.moveBy(const Offset(100, 0));
      await t.pump();
      expect(find.text('‹ Slide to cancel'), findsOneWidget);
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'stop');
      await _finishSigning(t);
    });

    testWidgets('Arabic (RTL): slide right to cancel; sliding left does '
        'not', (t) async {
      final talk = _Talk(untilStop: true);
      await talk.pump(t, language: AppLanguage.ar);
      final g = await _press(t);
      expect(find.text('‹ اسحب للإلغاء'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await g.moveBy(const Offset(-120, 0));
      await t.pump();
      expect(find.text('سيب عشان تلغي'), findsNothing);
      await g.moveBy(const Offset(240, 0));
      await t.pump();
      expect(find.text('سيب عشان تلغي'), findsOneWidget);
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'cancel');
    });

    testWidgets('too short (under 0.4 s): nothing sent, "Hold the mic '
        'while you speak."', (t) async {
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'cancel');
      expect(find.text('Hold the mic while you speak.'), findsOneWidget);
      expect(talk.stt.heard, ['hello']);
    });

    testWidgets('60 s: stops as if released', (t) async {
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      await t.pump(const Duration(seconds: 59));
      expect(talk.stt.calls.last, isNot('stop'));
      await t.pump(const Duration(seconds: 1));
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'stop');
      await _until(t, find.text('hello'));
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.where((c) => c == 'stop'), hasLength(1));
      await _finishSigning(t);
    });

    testWidgets('nothing heard after a hold: D9 for hold to talk (TV12) and '
        'D24', (t) async {
      final talk = _Talk(untilStop: true);
      await talk.pump(t);
      await _hold(t);
      expect(
        find.text(
          "Didn't catch that. Hold the mic and try again.\n"
          'Try saying it in a short sentence.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the app goes to the background while recording: the '
        'recording is thrown away', (t) async {
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      await t.pump(const Duration(seconds: 1));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'cancel');
      expect(talk.stt.heard, ['hello']);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await g.up();
      await settle(t, n: 3);
      expect(find.text('Mic ready'), findsOneWidget);
    });

    testWidgets('reduced motion: the level bars stay still', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final talk = _Talk(untilStop: true);
      await talk.pump(t);
      final g = await _press(t);
      double bar() => t
          .widget<Transform>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('talk-mic-level')),
                  matching: find.byType(Transform),
                )
                .at(2),
          )
          .transform
          .storage[5];
      final before = bar();
      talk.stt.level(1);
      await t.pump();
      expect(bar(), before);
      await g.up();
      await settle(t, n: 3);
    });

    testWidgets('a quick tap does not record (hold to talk)', (t) async {
      final talk = _Talk(untilStop: true);
      await talk.pump(t);
      await tapIt(t, _mic);
      expect(find.text('Hold the mic while you speak.'), findsOneWidget);
      expect(talk.stt.listening, isFalse);
    });

    testWidgets('face to face: the turned card works the same; "Hold the '
        'mic to reply"', (t) async {
      final talk = _Talk(untilStop: true);
      await talk.pump(t, stored: {'setup.role': 'speak'});
      await settle(t, n: 15);
      expect(find.text('Hold the mic to reply'), findsOneWidget);
      final g = await _press(t);
      await t.pump(const Duration(seconds: 1));
      // turned 180°: the person opposite slides toward their left, which
      // is the screen's right
      await g.moveBy(const Offset(120, 0));
      await t.pump();
      expect(find.text('Release to cancel'), findsOneWidget);
      await g.up();
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'cancel');
    });
  });

  group('tap mode (Settings › Tap to start and stop, or a screen reader)', () {
    testWidgets('the setting: a tap starts, the next one sends; TV2 hint; '
        'labels TV4 / TV5', (t) async {
      final h = t.ensureSemantics();
      final talk = _Talk(heard: ['hello'], untilStop: true);
      await talk.pump(t, stored: {'settings.micTap': true});
      expect(_text('Tap the mic, speak, then tap again.'), findsOneWidget);
      expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
      await tapIt(t, _mic);
      expect(talk.stt.listening, isTrue);
      expect(find.bySemanticsLabel('Stop and send'), findsOneWidget);
      expect(find.text('Stop and send'), findsOneWidget);
      expect(find.text('‹ Slide to cancel'), findsNothing);
      await t.pump(const Duration(milliseconds: 100));
      await tapIt(t, _mic);
      expect(talk.stt.calls.last, 'stop', reason: 'never "too short"');
      await _until(t, find.text('hello'));
      await _finishSigning(t);
      h.dispose();
    });

    testWidgets('a screen reader on: tap mode by itself; its "Cancel '
        'recording" action throws the recording away and announces it', (
      t,
    ) async {
      final h = t.ensureSemantics();
      final talk = _Talk(untilStop: true);
      final announced = <String>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        (m) async {
          final data = (m! as Map)['data'] as Map;
          if (data['message'] case final String s) announced.add(s);
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await talk.pump(t);
      expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
      final idle = t.getSemantics(_micSemantics());
      idle.owner!.performAction(idle.id, SemanticsAction.tap);
      await settle(t, n: 3);
      expect(talk.stt.listening, isTrue);
      final rec = t.getSemantics(_micSemantics());
      rec.owner!.performAction(
        rec.id,
        SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(
          const CustomSemanticsAction(label: 'Cancel recording'),
        ),
      );
      await settle(t, n: 3);
      expect(talk.stt.calls.last, 'cancel');
      expect(announced, ['Recording cancelled']);
      expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
      h.dispose();
    });
  });

  testWidgets('permission refused (D4): Allow asks again', (t) async {
    final perms = FakeMicPermissions(answer: MicPermission.denied);
    await _Talk(perms: perms).pump(t);
    await _hold(t);
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
    await _hold(t);
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
    await _hold(t);
    expect(
      find.text("Speech recognition isn't available on this phone."),
      findsOneWidget,
    );
  });

  testWidgets('Arabic voice, recognizer lacks Arabic: D8', (t) async {
    await _Talk(support: SpeechSupport.languageMissing)
        .pump(t, stored: {'setup.spoken': 'ar'});
    await _hold(t);
    expect(
      find.text("This phone can't recognize Arabic speech yet."),
      findsOneWidget,
    );
  });

  testWidgets('English voice, recognizer lacks English: D7', (t) async {
    await _Talk(support: SpeechSupport.languageMissing)
        .pump(t, stored: {'setup.spoken': 'en'});
    await _hold(t);
    expect(
      find.text("This phone can't recognize English speech yet."),
      findsOneWidget,
    );
  });

  testWidgets('other recognizer failures: a generic message', (t) async {
    await _Talk(heard: [const SpeechFailed(SpeechError.other)]).pump(t);
    await _hold(t);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
  });

  testWidgets('face to face: the card label, "Waiting for signs…" and the '
      'toast; the button is a toggle', (t) async {
    final h = t.ensureSemantics();
    await _Talk().pump(t);
    await tapIt(t, find.byKey(const ValueKey('talk-f2f')));
    expect(find.text('FOR THE HEARING PERSON'), findsOneWidget);
    expect(find.text('Waiting for signs…'), findsOneWidget);
    expect(find.text('Hold the mic to reply'), findsOneWidget);
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
    await _hold(t);
    expect(find.byKey(const ValueKey('talk-privacy')), findsOneWidget);
    await _finishSigning(t);
    await tapIt(t, find.byKey(const ValueKey('talk-privacy-ok')));
    expect(find.byKey(const ValueKey('talk-privacy')), findsNothing);
    expect(h.store.getBool('talk.privacySeen'), isTrue);
    await _hold(t);
    expect(find.byKey(const ValueKey('talk-privacy')), findsNothing);
    await _finishSigning(t);
  });

  testWidgets('Replay plays the last sentence again (caption lights up)', (
    t,
  ) async {
    await _Talk(heard: ['yes']).pump(t);
    await _hold(t);
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
    await _hold(t);
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
