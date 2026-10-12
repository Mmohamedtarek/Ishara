// On the emulator or a phone, with the mock glove (debug build default):
//   flutter test integration_test/talk_test.dart -d <device>
// Glove → text through the real pipeline: the mock glove streams the kit's
// A/hello.csv as BLE frames → recognizer (3 models, Decider) → Talk. The
// kit says that file gives tentative → confirm "hello" three times
// (mock/expected.json). Prints TALK lines for the step record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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
}
