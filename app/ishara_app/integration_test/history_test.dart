// On the emulator, with the mock glove (debug build default):
//   flutter test integration_test/history_test.dart -d <device>
// Talk → History → Starred, through the real app: the mock glove signs
// "hello" (kit A/hello.csv through the real pipeline), the sentence lands
// in History as today's conversation, gets a star, and Starred speaks it on
// a tap in the spoken-language voice. Prints HISTORY lines for the record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

import '../test/support/fake_talk.dart' show FakeTextToSpeech;

Future<void> waitFor(
  WidgetTester t,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('not found: $f');
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapAndWait(WidgetTester t, Finder f) async {
  await waitFor(t, f);
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a signed sentence reaches History; a star keeps it in '
      'Starred; a tap there speaks it', (t) async {
    void mark(String what) => debugPrint('HISTORY $what');
    final tts = FakeTextToSpeech();
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
          textToSpeechProvider.overrideWithValue(tts),
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
    final source = c.read(gloveSourceProvider);
    final found = await source.scan().firstWhere((l) => l.isNotEmpty);
    await source.connect(found.first);
    await waitFor(t, find.text('Glove connected'));

    await tapAndWait(t, find.byKey(const ValueKey('talk-mock')));
    await tapAndWait(t, find.byKey(const ValueKey('mock-file-hello')));
    Navigator.of(t.element(find.byKey(const ValueKey('mock-person')))).pop();
    final repo = c.read(conversationRepositoryProvider);
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (!repo.messages.any((m) => m.side == MessageSide.me)) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('no feed');
      await t.pump(const Duration(milliseconds: 200));
    }
    final me = repo.messages.lastWhere((m) => m.side == MessageSide.me);
    mark('signed: ${me.text} (conversation ${me.conversationKey})');

    // History: one conversation, titled "Today, hh:mm"
    await tapAndWait(t, find.text('History').last);
    final row = find.byKey(ValueKey('history-row-${me.conversationKey}'));
    await waitFor(t, row);
    expect(
      find.descendant(of: row, matching: find.textContaining('Today, ')),
      findsOneWidget,
    );
    mark('row: today');
    await tapAndWait(t, row);
    await tapAndWait(t, find.byKey(const ValueKey('star-0')));
    final phrases = c.read(savedPhrasesRepositoryProvider).phrases;
    expect(phrases.map((p) => p.text), [me.text]);
    mark('starred: ${phrases.single.text}');

    // back to the list → Starred → tap speaks it in English
    await tapAndWait(t, find.byKey(const ValueKey('conversation-back')));
    await tapAndWait(t, find.byKey(const ValueKey('seg-1')));
    await tapAndWait(t, find.byKey(ValueKey('starred-${phrases.single.id}')));
    await t.pump(const Duration(milliseconds: 400));
    expect(tts.spoken.last, me.text);
    expect(tts.languages.last, SpokenLanguage.en);
    mark('spoken: ${tts.spoken.last}');
  });
}
