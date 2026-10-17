import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';

import '../support/local_db.dart';

Duration _gap() => const Duration(minutes: 10);

LocalConversationRepository _repo([AppDatabase? db, KeyValueStore? kv]) =>
    LocalConversationRepository(
      db ?? memoryDb(),
      kv ?? MemoryKeyValueStore(),
      gap: _gap,
    );

/// The repository after a restart: what the database holds.
Future<LocalConversationRepository> _reopen(
  AppDatabase db,
  KeyValueStore kv,
) async => LocalConversationRepository(
  db,
  kv,
  gap: _gap,
  initial: (await reload(db)).messages,
);

void main() {
  final at = DateTime(2026, 10, 12, 9, 30);
  TalkMessage m(String text, {MessageSide side = MessageSide.them}) =>
      TalkMessage(side: side, text: text, at: at);

  test('messages persist in the database and load back in order', () async {
    final db = memoryDb();
    final kv = MemoryKeyValueStore();
    final repo = _repo(db, kv);
    final seen = <List<TalkMessage>>[];
    repo.changes.listen(seen.add);
    await repo.add(m('hello'));
    await repo.add(m('شكرا', side: MessageSide.me));
    expect(seen.last.map((x) => x.text), ['hello', 'شكرا']);
    final again = await _reopen(db, kv);
    expect(
      [for (final x in again.messages) (x.side, x.text, x.at)],
      [(MessageSide.them, 'hello', at), (MessageSide.me, 'شكرا', at)],
    );
    // both in one conversation, with a stored id
    expect(again.messages.map((x) => x.conversation).toSet(), hasLength(1));
    expect(again.messages.first.conversation, isNotNull);
    await repo.dispose();
    await again.dispose();
  });

  test('no size limit any more (2026-10-12): 600 messages all stay', () async {
    final db = memoryDb();
    final kv = MemoryKeyValueStore();
    final repo = _repo(db, kv);
    for (var i = 0; i < 600; i++) {
      await repo.add(m('$i'));
    }
    expect(repo.messages.length, 600);
    final again = await _reopen(db, kv);
    expect(again.messages.length, 600);
    expect(again.messages.first.text, '0');
    expect(again.messages.last.text, '599');
    await repo.dispose();
    await again.dispose();
  });

  test('export keeps its step 9 shape', () async {
    final repo = _repo();
    await repo.add(m('hello'));
    final out = repo.export();
    expect(out.keys, {'talk.version', 'talk.messages'});
    expect(out['talk.version'], 2);
    expect(out['talk.messages'], contains('"text":"hello"'));
    await repo.startNewConversation();
    expect(repo.export()['talk.newConversation'], isTrue);
    await repo.dispose();
  });

  test('messages are read-only outside', () {
    final repo = _repo();
    expect(() => repo.messages.add(m('x')), throwsUnsupportedError);
  });

  test('equality', () {
    expect(m('a'), m('a'));
    expect(m('a').hashCode, m('a').hashCode);
    expect(m('a') == m('b'), isFalse);
  });

  group('conversations (S9-4)', () {
    final t0 = DateTime(2026, 10, 14, 9);
    TalkMessage at(DateTime t, [String text = 'x']) =>
        TalkMessage(side: MessageSide.me, text: text, at: t);
    Future<List<String?>> ids(
      List<DateTime> times, {
      int clearAfter = -1,
    }) async {
      final repo = _repo();
      for (final (i, t) in times.indexed) {
        await repo.add(at(t));
        if (i == clearAfter) await repo.startNewConversation();
      }
      final out = [for (final x in repo.messages) x.conversation];
      await repo.dispose();
      return out;
    }

    bool sameAsPrevious(List<String?> ids, int i) => ids[i] == ids[i - 1];

    test(
      'the 10-minute gap: 9:59 later stays, 10:01 later starts new',
      () async {
        final a = await ids([
          t0,
          t0.add(const Duration(minutes: 9, seconds: 59)),
        ]);
        expect(sameAsPrevious(a, 1), isTrue);
        final b = await ids([
          t0,
          t0.add(const Duration(minutes: 10, seconds: 1)),
        ]);
        expect(sameAsPrevious(b, 1), isFalse);
      },
    );

    test('Clear: the next message starts a new conversation (also after a '
        'restart)', () async {
      final a = await ids([
        t0,
        t0.add(const Duration(seconds: 5)),
      ], clearAfter: 0);
      expect(sameAsPrevious(a, 1), isFalse);
      final db = memoryDb();
      final kv = MemoryKeyValueStore();
      final r1 = _repo(db, kv);
      await r1.add(at(t0));
      await r1.startNewConversation();
      final r2 = await _reopen(db, kv);
      await r2.add(at(t0.add(const Duration(seconds: 5))));
      expect(
        r2.messages[0].conversation == r2.messages[1].conversation,
        isFalse,
      );
      // and only the next one
      await r2.add(at(t0.add(const Duration(seconds: 9))));
      expect(r2.messages[1].conversation, r2.messages[2].conversation);
    });

    test('midnight: 23:58 and 00:01 are two conversations', () async {
      final a = await ids([
        DateTime(2026, 10, 14, 23, 58),
        DateTime(2026, 10, 15, 0, 1),
      ]);
      expect(sameAsPrevious(a, 1), isFalse);
    });

    test('the background never splits: messages 8 minutes apart around a '
        'pause stay in one conversation', () async {
      // the app went to the background between them: nothing in the repo
      // sees it, only the times count
      final a = await ids([
        t0,
        t0.add(const Duration(minutes: 8)),
        t0.add(const Duration(minutes: 16)),
      ]);
      expect(a.toSet(), hasLength(1));
    });

    test('older messages (no id) are one conversation per local day; one '
        'that goes on gets an id for all of it', () async {
      // talk v1 (step 7): no conversation ids
      final old = LegacyData.read(
        MemoryKeyValueStore({
          'talk.messages':
              '[{"side":"them","text":"a","at":"2026-10-13T09:00:00.000"},'
              '{"side":"me","text":"b","at":"2026-10-14T09:00:00.000"},'
              '{"side":"me","text":"c","at":"2026-10-14T09:01:00.000"}]',
        }),
      );
      final db = memoryDb();
      final kv = MemoryKeyValueStore();
      final repo = LocalConversationRepository(
        db,
        kv,
        gap: _gap,
        initial: old.messages,
      );
      expect(repo.messages.map((x) => x.conversationKey), [
        'day:2026-10-13',
        'day:2026-10-14',
        'day:2026-10-14',
      ]);
      await repo.add(at(DateTime(2026, 10, 14, 9, 5), 'd'));
      final keys = repo.messages.map((x) => x.conversationKey).toList();
      expect(keys[0], 'day:2026-10-13');
      expect(keys.sublist(1).toSet(), hasLength(1));
      expect(keys[1], isNot(startsWith('day:')));
      await repo.dispose();
      // (seeded rows aren't in this database: only the new one is)
      expect((await reload(db)).messages.single.message.text, 'd');
    });

    test('A, Clear, B; deleting B: the next message starts a new '
        'conversation, never joins the cleared A', () async {
      final repo = _repo();
      await repo.add(at(t0, 'a'));
      await repo.startNewConversation();
      await repo.add(at(t0.add(const Duration(minutes: 1)), 'b'));
      await repo.deleteConversation(repo.messages.last.conversationKey);
      await repo.add(at(t0.add(const Duration(minutes: 2)), 'c'));
      final keys = repo.messages.map((x) => x.conversationKey).toList();
      expect(keys, hasLength(2));
      expect(keys[1], isNot(keys[0]));
      await repo.dispose();
    });

    test('delete a conversation, then Undo puts it back in order', () async {
      final db = memoryDb();
      final repo = _repo(db);
      await repo.add(at(t0, 'a'));
      await repo.add(at(t0.add(const Duration(minutes: 30)), 'b'));
      await repo.add(at(t0.add(const Duration(minutes: 31)), 'c'));
      final key = repo.messages.first.conversationKey;
      final removed = await repo.deleteConversation(key);
      expect(removed.map((x) => x.text), ['a']);
      expect(repo.messages.map((x) => x.text), ['b', 'c']);
      await repo.restore(removed);
      expect(repo.messages.map((x) => x.text), ['a', 'b', 'c']);
      expect(await repo.deleteConversation('nope'), isEmpty);
      expect((await reload(db)).messages.map((r) => r.message.text), [
        'a',
        'b',
        'c',
      ]);
      await repo.deleteAll();
      expect(repo.messages, isEmpty);
      expect((await reload(db)).messages, isEmpty);
      await repo.dispose();
    });
  });
}
