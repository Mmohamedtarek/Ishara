import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

void main() {
  final at = DateTime(2026, 10, 12, 9, 30);
  TalkMessage m(String text, {MessageSide side = MessageSide.them}) =>
      TalkMessage(side: side, text: text, at: at);

  test('messages persist on the phone store and load back in order', () async {
    final kv = MemoryKeyValueStore();
    final repo = LocalConversationRepository(kv);
    final seen = <List<TalkMessage>>[];
    repo.changes.listen(seen.add);
    await repo.add(m('hello'));
    await repo.add(m('شكرا', side: MessageSide.me));
    expect(kv.getInt(LocalConversationRepository.kVersion), 1);
    expect(seen.last.map((x) => x.text), ['hello', 'شكرا']);
    final again = LocalConversationRepository(kv);
    expect(again.messages, [m('hello'), m('شكرا', side: MessageSide.me)]);
    await repo.dispose();
    await again.dispose();
  });

  test('keeps the newest maxMessages', () async {
    final repo = LocalConversationRepository(MemoryKeyValueStore());
    for (var i = 0; i < LocalConversationRepository.maxMessages + 3; i++) {
      await repo.add(m('$i'));
    }
    expect(repo.messages.length, LocalConversationRepository.maxMessages);
    expect(repo.messages.first.text, '3');
    await repo.dispose();
  });

  test('a broken stored value starts empty instead of failing', () {
    for (final raw in ['not json', '{"a": 1}']) {
      final kv = MemoryKeyValueStore({'talk.messages': raw});
      expect(LocalConversationRepository(kv).messages, isEmpty, reason: raw);
    }
  });

  test('bad entries are skipped, good ones kept', () {
    final kv = MemoryKeyValueStore({
      'talk.messages':
          '[{"side":"them","text":"hi","at":"2026-10-12T09:30:00.000"},'
          '{"side":"x","text":"a","at":"2026-10-12T09:30:00.000"},'
          '{"side":"me","text":3,"at":"2026-10-12T09:30:00.000"},'
          '{"side":"me","text":"b","at":"never"},7]',
    });
    expect(LocalConversationRepository(kv).messages, [m('hi')]);
  });

  test('export and clear, for the step 10 migration', () async {
    final kv = MemoryKeyValueStore();
    final repo = LocalConversationRepository(kv);
    expect(repo.export(), isEmpty);
    await repo.add(m('hello'));
    final out = repo.export();
    expect(out.keys, {'talk.version', 'talk.messages'});
    await repo.clear();
    expect(kv.keys, isEmpty);
    expect(repo.messages, isEmpty);
    await repo.dispose();
  });

  test('messages are read-only outside', () {
    final repo = LocalConversationRepository(MemoryKeyValueStore());
    expect(() => repo.messages.add(m('x')), throwsUnsupportedError);
  });

  test('equality', () {
    expect(m('a'), m('a'));
    expect(m('a').hashCode, m('a').hashCode);
    expect(m('a') == m('b'), isFalse);
  });
}
