// On the emulator or a phone, with the mock glove (debug build default):
//   flutter test integration_test/talk_test.dart -d <device>
// Glove → text through the real pipeline: the mock glove streams the kit's
// A/hello.csv as BLE frames → recognizer (3 models, Decider) → Talk. The
// kit says that file gives tentative → confirm "hello" three times
// (mock/expected.json). Prints TALK lines for the step record.
// Speech → sign, hold to talk (2026-10-26): hold and release, too short,
// slide to cancel, face to face, and tap mode, on the real screen with a
// scripted recognizer (the words come when the mic is let go).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

import '../test/support/fake_speech.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // the app's log in the run's output (what Talk did, for the record)
  setUpLogging();

  Future<void> waitFor(
    WidgetTester t,
    Finder f, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('not found: $f');
      }
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('glove → text: the mock glove signs hello, Talk shows and '
      'speaks it, then it goes to the feed', (t) async {
    final sw = Stopwatch()..start();
    void mark(String what) =>
        debugPrint('TALK ${sw.elapsedMilliseconds} ms $what');
    final store = MemoryKeyValueStore({
      'onboarding.done': true,
      'setup.spoken': 'en',
      'setup.role': 'sign',
      // the Mock panel shows only in developer mode (S9-3)
      'settings.developer': true,
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.talk),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    await waitFor(t, find.byKey(const ValueKey('screen-talk')));
    final c = ProviderScope.containerOf(
      t.element(find.byKey(const ValueKey('screen-talk'))),
    );
    // connect the mock glove (as Pair would)
    final source = c.read(gloveSourceProvider);
    final found = await source.scan().firstWhere((l) => l.isNotEmpty);
    await source.connect(found.first);
    mark('connected');
    await waitFor(t, find.text('Glove connected'));

    await t.tap(find.byKey(const ValueKey('talk-mock')));
    await waitFor(t, find.byKey(const ValueKey('mock-file-hello')));
    await t.tap(find.byKey(const ValueKey('mock-file-hello')));
    await t.pump(const Duration(milliseconds: 300));
    Navigator.of(t.element(find.byKey(const ValueKey('mock-person')))).pop();
    mark('playing A/hello.csv');

    final word = find.descendant(
      of: find.byKey(const ValueKey('talk-live-words')),
      matching: find.text('hello'),
    );
    await waitFor(t, word);
    mark('hello shown');

    final repo = c.read(conversationRepositoryProvider);
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (!repo.messages.any((m) => m.side == MessageSide.me)) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('no feed');
      await t.pump(const Duration(milliseconds: 200));
    }
    final me = repo.messages.lastWhere((m) => m.side == MessageSide.me);
    mark('feed: ${me.text}');
    expect(me.text.split(' ').toSet(), {'hello'});
  });

  testWidgets('speech → sign, hold to talk: hold and let go, too short, '
      'slide to cancel, face to face, tap mode', (t) async {
    final sw = Stopwatch()..start();
    void mark(String what) =>
        debugPrint('TALK ${sw.elapsedMilliseconds} ms $what');
    final stt = FakeSpeechToText(
      heard: ['hello', 'thank you'],
      untilStop: true,
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(
            MemoryKeyValueStore({
              'onboarding.done': true,
              'setup.spoken': 'en',
              'setup.role': 'sign',
              'talk.privacySeen': true,
            }),
          ),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.talk),
          ),
          speechToTextProvider.overrideWithValue(stt),
          micPermissionsProvider.overrideWithValue(
            FakeMicPermissions(current: MicPermission.granted),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    final mic = find.byKey(const ValueKey('talk-mic'));
    await waitFor(t, mic);
    final c = ProviderScope.containerOf(t.element(mic));
    // read each time: the repository is rebuilt once the app rules load
    ConversationRepository repo() => c.read(conversationRepositoryProvider);
    int heard() =>
        repo().messages.where((m) => m.side == MessageSide.them).length;

    // 1. hold 1.5 s and let go: "hello" is signed and goes to the feed
    var g = await t.startGesture(t.getCenter(mic));
    await waitFor(t, find.text('Slide to cancel'));
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text('0:01'), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
    await g.up();
    var end = DateTime.now().add(const Duration(seconds: 40));
    while (heard() < 1) {
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('no feed; recognizer: ${stt.calls}');
      }
      await t.pump(const Duration(milliseconds: 200));
    }
    mark('hold → heard ${repo().messages.last.text}');
    expect(repo().messages.last.text, 'hello');

    // 2. too short: nothing sent
    g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 100));
    await g.up();
    await waitFor(t, find.text('Hold the mic while you speak.'));
    expect(stt.heard, ['thank you']);
    mark('too short: hint, nothing sent');

    // 3. slide to cancel (left in English)
    g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(seconds: 1));
    await g.moveBy(const Offset(-120, 0));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Release to cancel'), findsOneWidget);
    await g.up();
    await t.pump(const Duration(milliseconds: 500));
    expect(stt.calls.last, 'cancel');
    expect(stt.heard, ['thank you']);
    mark('slide to cancel: thrown away');

    // 4. face to face: the turned card cancels toward the screen's right
    await t.tap(find.byKey(const ValueKey('talk-f2f')));
    await t.pump(const Duration(seconds: 1));
    await waitFor(t, find.text('Hold the mic to reply'));
    g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(seconds: 1));
    await g.moveBy(const Offset(120, 0));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('Release to cancel'), findsOneWidget);
    await g.up();
    await t.pump(const Duration(milliseconds: 500));
    expect(stt.calls.last, 'cancel');
    await t.tap(find.byKey(const ValueKey('talk-f2f')));
    await t.pump(const Duration(seconds: 1));
    mark('face to face: slide to cancel');

    // 5. tap mode (Settings › Tap to start and stop): tap, tap
    c.read(appSettingsControllerProvider.notifier).setMicTap(on: true);
    await t.pump(const Duration(seconds: 3));
    await t.tap(mic);
    await waitFor(t, find.text('Stop and send'));
    await t.pump(const Duration(milliseconds: 800));
    await t.tap(mic);
    end = DateTime.now().add(const Duration(seconds: 40));
    while (heard() < 2) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('no feed');
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(repo().messages.last.text, 'thank you');
    mark('tap mode → heard ${repo().messages.last.text}');
    await t.pumpWidget(const SizedBox());
  });
}
