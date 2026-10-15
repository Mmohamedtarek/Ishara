import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/history/presentation/history_screen.dart';

import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// Two conversations: today 09:00 (2 messages) and yesterday 18:02.
Map<String, Object> _store() {
  final today = DateTime.now();
  final t0 = DateTime(today.year, today.month, today.day, 9);
  final y = t0.subtract(const Duration(days: 1));
  return {
    'setup.spoken': 'en',
    'talk.messages': jsonEncode([
      {
        'side': 'them',
        'text': 'Where is the pharmacy?',
        'at': DateTime(y.year, y.month, y.day, 18, 2).toIso8601String(),
        'conversation': 'c1',
      },
      {
        'side': 'them',
        'text': 'Hello, the doctor will call you',
        'at': t0.toIso8601String(),
        'conversation': 'c2',
      },
      {
        'side': 'me',
        'text': 'أنا جعانة',
        'at': t0.add(const Duration(minutes: 1)).toIso8601String(),
        'conversation': 'c2',
      },
    ]),
  };
}

class _History {
  final talk = TalkFakes();
  late Harness h;
  late WidgetTester t;

  ProviderContainer get c =>
      ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

  Future<void> pump(
    WidgetTester tester, {
    Map<String, Object>? store,
    AppLanguage language = AppLanguage.en,
  }) async {
    t = tester;
    addTearDown(rootBundle.clear);
    addTearDown(talk.feed.dispose);
    h = await pumpScreen(
      t,
      const HistoryScreen(),
      language: language,
      harness: Harness(store: MemoryKeyValueStore(store ?? _store())),
      overrides: talk.overrides,
    );
  }
}

void main() {
  testWidgets('All: one row per conversation, newest first, titled by day '
      'and time; no sample data', (t) async {
    final s = _History();
    await s.pump(t);
    expect(_key('history-row-c2'), findsOneWidget);
    expect(_key('history-row-c1'), findsOneWidget);
    expect(find.text('Today, 09:00'), findsOneWidget);
    expect(find.text('Yesterday, 18:02'), findsOneWidget);
    expect(
      find.text('2 messages · Hello, the doctor will call you'),
      findsOneWidget,
    );
    expect(
      t.getTopLeft(_key('history-row-c2')).dy,
      lessThan(t.getTopLeft(_key('history-row-c1')).dy),
    );
    // the prototype's samples never appear
    for (final fake in ['Clinic visit', 'Pharmacy', 'Coffee shop']) {
      expect(find.textContaining(fake), findsNothing);
    }
  });

  testWidgets('search: Arabic forms and diacritics; nothing found', (t) async {
    final s = _History();
    await s.pump(t);
    await t.enterText(_key('search-field'), 'انا جعانه');
    await settle(t);
    expect(_key('history-row-c2'), findsOneWidget);
    expect(_key('history-row-c1'), findsNothing);
    expect(find.text('2 messages · أنا جعانة'), findsOneWidget);
    await t.enterText(_key('search-field'), 'taxi');
    await settle(t);
    expect(find.text('Nothing matches “taxi”.'), findsOneWidget);
  });

  testWidgets('empty: no history yet; nothing starred; the guest note', (
    t,
  ) async {
    final s = _History();
    await s.pump(t, store: {'setup.spoken': 'en'});
    expect(
      find.text(
        'No conversations yet. What you sign and hear in Talk shows up here.',
      ),
      findsOneWidget,
    );
    await tapIt(t, _key('seg-1'));
    expect(
      find.text(
        'Nothing starred yet. Open a conversation and tap the star next to '
        'a sentence.',
      ),
      findsOneWidget,
    );
    expect(_key('history-guest'), findsOneWidget);
  });

  testWidgets('Starred: a saved phrase speaks in the voice language; the '
      'star unstars it', (t) async {
    final s = _History();
    await s.pump(t);
    await s.c
        .read(savedPhrasesRepositoryProvider)
        .star('Where is the pharmacy?');
    await tapIt(t, _key('seg-1'));
    final row = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('starred-'),
    );
    expect(row, findsOneWidget);
    await tapIt(t, row);
    expect(s.talk.tts.languages.last.name, 'en');
    expect(s.talk.tts.spoken, ['Where is the pharmacy?']);
    await tapIt(t, find.descendant(of: row, matching: find.byType(StarButton)));
    expect(row, findsNothing);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('a conversation: every message, star → Starred, delete → '
      'Undo; deleting keeps the starred phrase', (t) async {
    final s = _History();
    await s.pump(t);
    await tapIt(t, _key('history-row-c2'));
    expect(_key('screen-conversation'), findsOneWidget);
    expect(_key('conversation-msg-0'), findsOneWidget);
    expect(_key('conversation-msg-1'), findsOneWidget);
    await tapIt(t, _key('star-1'));
    final phrases = s.c.read(savedPhrasesRepositoryProvider);
    expect(phrases.phrases.single.text, 'أنا جعانة');
    expect(find.text('Added to Starred'), findsOneWidget);
    await tapIt(t, _key('conversation-delete'));
    expect(_key('screen-history'), findsOneWidget);
    expect(_key('history-row-c2'), findsNothing);
    expect(phrases.phrases.single.text, 'أنا جعانة');
    // Undo puts it back
    await tapIt(t, find.text('Undo'));
    expect(_key('history-row-c2'), findsOneWidget);
    expect(s.c.read(conversationRepositoryProvider).messages, hasLength(3));
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets('TalkBack: rows, tabs and stars are labelled; Arabic', (t) async {
    final sem = t.ensureSemantics();
    final s = _History();
    await s.pump(t, language: AppLanguage.ar);
    // Western digits, as everywhere in the app
    expect(find.text('النهارده، 09:00'), findsOneWidget);
    expect(find.text('امبارح، 18:02'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^النهارده، 09:00\. رسالتين')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('المعلّمة'), findsOneWidget);
    // a starred row's own star is reachable (not merged into the row)
    await s.c.read(savedPhrasesRepositoryProvider).star('أنا جعانة');
    await tapIt(t, find.byKey(const ValueKey('seg-1')));
    expect(find.bySemanticsLabel('شيل العلامة'), findsOneWidget);
    expect(find.bySemanticsLabel('انطق «أنا جعانة»'), findsOneWidget);
    sem.dispose();
  });
}
