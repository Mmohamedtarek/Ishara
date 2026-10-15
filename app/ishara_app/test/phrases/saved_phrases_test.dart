import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

void main() {
  var t = DateTime.utc(2026, 10, 14, 9);
  DateTime now() => t = t.add(const Duration(minutes: 1));

  test(
    'star → a saved phrase (Phase 0 fields), language from the text',
    () async {
      final kv = MemoryKeyValueStore();
      final repo = LocalSavedPhrasesRepository(kv, now: now);
      await repo.star('  Where is the pharmacy?  ');
      await repo.star('محتاج مساعدة');
      expect(repo.phrases.map((p) => (p.text, p.lang)), [
        ('محتاج مساعدة', 'ar'),
        ('Where is the pharmacy?', 'en'),
      ]);
      expect(repo.find('Where is the pharmacy?'), isNotNull);
      expect(kv.getInt(LocalSavedPhrasesRepository.kVersion), 1);
      final stored = jsonDecode(
        kv.getString(LocalSavedPhrasesRepository.kPhrases)!,
      ) as List;
      expect((stored.first as Map).keys.toSet(), {
        'id',
        'text',
        'lang',
        'createdAt',
        'updatedAt',
        'deleted',
      });
      // starring twice keeps one
      await repo.star('محتاج مساعدة');
      expect(repo.phrases, hasLength(2));
      await repo.star('   ');
      expect(repo.phrases, hasLength(2));
      await repo.dispose();
    },
  );

  test('unstar keeps a tombstone (for the sync); star again revives the '
      'same id', () async {
    final kv = MemoryKeyValueStore();
    final repo = LocalSavedPhrasesRepository(kv, now: now);
    await repo.star('yes');
    final id = repo.find('yes')!.id;
    await repo.unstar('yes');
    expect(repo.phrases, isEmpty);
    expect(repo.find('yes'), isNull);
    final stored =
        jsonDecode(kv.getString(LocalSavedPhrasesRepository.kPhrases)!) as List;
    expect((stored.single as Map)['deleted'], isTrue);
    await repo.star('yes');
    expect(repo.find('yes')!.id, id);
    await repo.unstar('nope'); // nothing to do
    final again = LocalSavedPhrasesRepository(kv, now: now);
    expect(again.phrases.single.text, 'yes');
    await repo.dispose();
    await again.dispose();
  });

  test('damaged values are skipped; export and clear', () async {
    final kv = MemoryKeyValueStore({
      LocalSavedPhrasesRepository.kPhrases:
          '[{"id":"a","text":"hi","lang":"en",'
          '"createdAt":"2026-10-14T09:00:00Z",'
          '"updatedAt":"2026-10-14T09:00:00Z","deleted":false},'
          '{"id":"b","text":"x","lang":"fr",'
          '"createdAt":"2026-10-14T09:00:00Z",'
          '"updatedAt":"2026-10-14T09:00:00Z","deleted":false},5]',
    });
    final repo = LocalSavedPhrasesRepository(kv, now: now);
    expect(repo.phrases.single.text, 'hi');
    const key = LocalSavedPhrasesRepository.kPhrases;
    expect(repo.export().keys, contains(key));
    await repo.clear();
    expect(kv.keys, isEmpty);
    expect(
      LocalSavedPhrasesRepository(
        MemoryKeyValueStore({LocalSavedPhrasesRepository.kPhrases: 'not json'}),
      ).phrases,
      isEmpty,
    );
    await repo.dispose();
  });
}
