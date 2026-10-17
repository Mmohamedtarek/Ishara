import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';

import '../support/local_db.dart';

void main() {
  var t = DateTime.utc(2026, 10, 14, 9);
  DateTime now() => t = t.add(const Duration(minutes: 1));

  test(
    'star → a saved phrase (Phase 0 fields), language from the text',
    () async {
      final db = memoryDb();
      final repo = LocalSavedPhrasesRepository(db, now: now);
      await repo.star('  Where is the pharmacy?  ');
      await repo.star('محتاج مساعدة');
      expect(repo.phrases.map((p) => (p.text, p.lang)), [
        ('محتاج مساعدة', 'ar'),
        ('Where is the pharmacy?', 'en'),
      ]);
      expect(repo.find('Where is the pharmacy?'), isNotNull);
      final rows = await db.select(db.phrases).get();
      expect(rows, hasLength(2));
      expect(rows.first.content, 'Where is the pharmacy?');
      expect(rows.first.updatedAtUs, rows.first.createdAtUs);
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
    final db = memoryDb();
    final repo = LocalSavedPhrasesRepository(db, now: now);
    await repo.star('yes');
    final id = repo.find('yes')!.id;
    await repo.unstar('yes');
    expect(repo.phrases, isEmpty);
    expect(repo.find('yes'), isNull);
    final row = await db.select(db.phrases).getSingle();
    expect(row.deleted, isTrue);
    expect(row.updatedAtUs, greaterThan(row.createdAtUs));
    await repo.star('yes');
    expect(repo.find('yes')!.id, id);
    await repo.unstar('nope'); // nothing to do
    final again = LocalSavedPhrasesRepository(
      db,
      now: now,
      initial: (await reload(db)).phrases,
    );
    expect(again.phrases.single.text, 'yes');
    expect(again.phrases.single.id, id);
    await repo.dispose();
    await again.dispose();
  });

  test('times keep their microseconds through the database', () async {
    final db = memoryDb();
    final at = DateTime.utc(2026, 10, 14, 9, 0, 0, 123, 456);
    final repo = LocalSavedPhrasesRepository(db, now: () => at);
    await repo.star('hi');
    final back = (await reload(db)).phrases.single;
    expect(back.createdAt, at);
    expect(back.updatedAt, at);
    expect(back.toJson(), repo.find('hi')!.toJson());
    await repo.dispose();
  });

  test('export keeps its step 9 shape (tombstones included)', () async {
    final repo = LocalSavedPhrasesRepository(memoryDb(), now: now);
    await repo.star('a');
    await repo.star('b');
    await repo.unstar('b');
    final out = repo.export();
    expect(out.keys, {'phrases.version', 'phrases.all'});
    expect(out['phrases.version'], 1);
    expect(out['phrases.all'], contains('"deleted":true'));
    await repo.dispose();
  });
}
