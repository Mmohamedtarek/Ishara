import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/kv_migration.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/core/storage/local_data.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';

import '../support/local_db.dart';

/// A real snapshot of the old store (test/storage/legacy_snapshots/, written
/// by each version's own code: app/tools/legacy_snapshots/make.sh).
Map<String, Object> snapshot(String v) => (jsonDecode(
  File('test/storage/legacy_snapshots/$v.json').readAsStringSync(),
) as Map<String, Object?>).cast<String, Object>();

const versions = ['v6', 'v7', 'v8', 'v9'];

/// Everything the database holds, without the new message ids, in a form
/// two runs can be compared by.
Future<Map<String, Object?>> contents(AppDatabase db) async {
  final d = await LocalData.load(db);
  final kv = await DriftKeyValueStore.load(db);
  return {
    'prefs': {for (final k in kv.keys.toList()..sort()) k: kv.read(k)},
    'messages': [for (final m in d.messages) m.message.toJson()],
    'phrases': [for (final p in d.phrases) p.toJson()],
    'activity': [for (final a in d.activity) a.json],
    'contacts': [for (final c in d.contacts) c.toJson()],
    'kept': [for (final k in d.kept) '${k.key}|${k.reason}|${k.value}'],
    'messageIds': d.messages.map((m) => m.id).toSet().length,
  };
}

/// The export the old store gave for [old] (Privacy › Export: the stored
/// values as they were), decoded for comparison.
Map<String, Object?> oldExport(Map<String, Object> old) => {
  'talk.messages': jsonDecode(old['talk.messages'] as String? ?? '[]'),
  'phrases.all': jsonDecode(old['phrases.all'] as String? ?? '[]'),
  'learn.activity': jsonDecode(old['learn.activity'] as String? ?? '[]'),
};

Future<Map<String, Object?>> newExport(AppDatabase db) async {
  final d = await LocalData.load(db);
  final kv = await DriftKeyValueStore.load(db);
  final talk = LocalConversationRepository(
    db,
    kv,
    gap: () => const Duration(minutes: 10),
    initial: d.messages,
  );
  final phrases = LocalSavedPhrasesRepository(db, initial: d.phrases);
  final log = LocalActivityRepository(db, initial: d.activity);
  Object? list(Map<String, Object> export, String key) =>
      jsonDecode(export[key] as String? ?? '[]');
  final out = {
    'talk.messages': list(talk.export(), 'talk.messages'),
    'phrases.all': list(phrases.export(), 'phrases.all'),
    'learn.activity': list(log.export(), 'learn.activity'),
  };
  await talk.dispose();
  await phrases.dispose();
  await log.dispose();
  return out;
}

void main() {
  group('every old version migrates with nothing lost', () {
    for (final v in versions) {
      test(v, () async {
        final old = snapshot(v);
        final kv = MemoryKeyValueStore(old);
        final db = memoryDb();
        final report = await KvMigration(kv, db).run();

        // every old key is gone, only after its part was stored
        expect(kv.keys, isEmpty);
        expect(report.values.fold<int>(0, (n, r) => n + r.removed), old.length);
        expect(report.values.every((r) => !r.earlier), isTrue);

        final c = await contents(db);
        // named values: the same keys, the same values and types
        final prefKeys = {
          ...LegacyKeys.onboarding,
          ...LegacyKeys.settings,
          ...LegacyKeys.flags,
        };
        expect(c['prefs'], {
          for (final k in old.keys.toList()..sort())
            if (prefKeys.contains(k)) k: old[k],
        });
        // lists: the export from the database equals the old store's
        expect(await newExport(db), oldExport(old));
        final contacts = old['sos.contacts'] as String?;
        expect(
          c['contacts'],
          contacts == null ? const <Object?>[] : jsonDecode(contacts),
        );
        // a clean store keeps nothing aside
        expect(c['kept'], isEmpty);
        // one id per message
        expect(c['messageIds'], (c['messages']! as List).length);

        // the next start finds nothing to do
        final again = await KvMigration(kv, db).run();
        expect(again, isEmpty);
        expect(await contents(db), c);
      });
    }

    test('talk v1 messages (step 7) keep no conversation id; v2 keep '
        'theirs', () async {
      final db7 = memoryDb();
      await KvMigration(MemoryKeyValueStore(snapshot('v7')), db7).run();
      final m7 = (await LocalData.load(db7)).messages;
      expect(m7, hasLength(3));
      expect(m7.every((m) => m.message.conversation == null), isTrue);
      expect(m7.first.message.conversationKey, 'day:2026-10-12');

      final db9 = memoryDb();
      await KvMigration(MemoryKeyValueStore(snapshot('v9')), db9).run();
      final m9 = (await LocalData.load(db9)).messages;
      expect(m9.map((m) => m.message.conversation).toSet(), {
        'f3ce2de7d048383a',
        '6aea71fb3327bf1e',
      });
      // microseconds and local time survive
      expect(m9[2].message.at, DateTime(2026, 10, 15, 18, 2, 1, 250, 3));
      expect(m9[2].message.at.isUtc, isFalse);
    });

    test('the settings read back exactly through the stores', () async {
      final db = memoryDb();
      await KvMigration(MemoryKeyValueStore(snapshot('v9')), db).run();
      final kv = await DriftKeyValueStore.load(db);
      expect(kv.getString('settings.theme'), 'dark');
      expect(kv.getInt('settings.signSpeed'), 15);
      expect(kv.getBool('settings.subtitles'), isFalse);
      expect(kv.getString('glove.name'), 'Ishara-0B9E');
      expect(kv.getBool('talk.newConversation'), isTrue);
      expect(kv.getString('device.id'), '74280c3741ad2ce24d8d33063a3b2c21');
    });

    test('the fallback (database not open) shows the same data as a '
        'migrated database', () async {
      final old = snapshot('v9');
      final fallback = LocalData.fromLegacy(
        LegacyData.read(MemoryKeyValueStore(old)),
      );
      final db = memoryDb();
      await KvMigration(MemoryKeyValueStore(old), db).run();
      final loaded = await LocalData.load(db);
      expect(
        [for (final m in fallback.messages) m.message],
        [for (final m in loaded.messages) m.message],
      );
      expect(
        [for (final p in fallback.phrases) p.toJson()],
        [for (final p in loaded.phrases) p.toJson()],
      );
      expect(fallback.activity, loaded.activity);
      expect(fallback.contacts, loaded.contacts);
    });
  });

  group('killed halfway: the next start finishes, nothing lost or twice', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ishara_kill_'));
    tearDown(() => dir.deleteSync(recursive: true));

    AppDatabase openFile() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      return AppDatabase(NativeDatabase(File('${dir.path}/ishara.sqlite')));
    }

    for (final v in ['v8', 'v9']) {
      test('$v, at every point', () async {
        // the clean run, and the points where a kill can happen
        final points = <String>[];
        final cleanDb = memoryDb();
        await KvMigration(
          MemoryKeyValueStore(snapshot(v)),
          cleanDb,
          onStep: (p) async => points.add(p),
        ).run();
        final clean = await contents(cleanDb);
        expect(points, contains('copying:prefs'));
        expect(points, contains('copied:talk'));
        expect(points.where((p) => p.startsWith('removed:')), isNotEmpty);

        for (final point in points) {
          final kv = MemoryKeyValueStore(snapshot(v));
          var db = openFile();
          await expectLater(
            KvMigration(
              kv,
              db,
              onStep: (p) async {
                if (p == point) throw KvMigrationKilled(p);
              },
            ).run(),
            throwsA(isA<KvMigrationKilled>()),
            reason: point,
          );
          // the process dies: the file is all that is left
          await db.close();
          db = openFile();
          final report = await KvMigration(kv, db).run();
          expect(kv.keys, isEmpty, reason: point);
          expect(await contents(db), clean, reason: point);
          // a part committed before the kill is not copied again (the
          // contents above would show a copy twice, too)
          if (point.startsWith('copied:')) {
            final part = LegacyPart.values.byName(point.substring(7));
            expect(report[part]?.earlier, isTrue, reason: point);
          }
          await db.close();
          File('${dir.path}/ishara.sqlite').deleteSync();
        }
      });
    }
  });

  group('damaged values are kept aside and never block the app', () {
    test('every kind of damage, in one store', () async {
      final old = {
        ...snapshot('v9'),
        'talk.messages':
            '[{"side":"me","text":"ok","at":"2026-10-15T10:00:00.000"},'
            '{"side":"x","text":"bad side","at":"2026-10-15T10:00:00.000"},7]',
        'phrases.all': '{not json',
        'learn.activity': 'broken again',
        'learn.activity.broken': 'broken in step 8',
        'sos.contacts': jsonEncode([
          {'name': 'A', 'phone': '+201000000001'},
          {'name': 'no plus', 'phone': '0100'},
          {'name': 'B', 'phone': '+201000000002'},
          {'name': 'C', 'phone': '+201000000003'},
          {'name': 'D', 'phone': '+201000000004'},
        ]),
        'setup.role': 5, // a wrong type stays as it was (the store ignores it)
        'mystery.key': 'from a build we never shipped',
      };
      final kv = MemoryKeyValueStore(old);
      final db = memoryDb();
      await KvMigration(kv, db).run();
      expect(kv.keys, isEmpty);
      final d = await LocalData.load(db);
      final kept = {for (final k in d.kept) k.key: (k.reason, k.value)};
      expect(kept['talk.messages[1]']?.$1, 'unreadable');
      expect(kept['talk.messages[2]'], ('unreadable', '7'));
      expect(kept['phrases.all'], ('damaged', '{not json'));
      expect(kept['learn.activity.broken'], (
        'damaged (kept by step 8)',
        'broken in step 8',
      ));
      expect(kept['learn.activity.broken.2'], ('damaged', 'broken again'));
      expect(kept['sos.contacts[1]']?.$1, 'unreadable');
      expect(kept['sos.contacts[4]']?.$1, 'over the limit');
      expect(kept['mystery.key']?.$1, 'unknown key');
      // the good values are all there
      expect(d.messages.single.message.text, 'ok');
      expect(d.phrases, isEmpty);
      expect(d.activity, isEmpty);
      expect(d.contacts.map((c) => c.name), ['A', 'B', 'C']);
      final prefs = await DriftKeyValueStore.load(db);
      expect(prefs.read('setup.role'), 5);
      expect(prefs.getString('settings.theme'), 'dark');
      // the export still carries the kept Learn values (as before)
      final log = LocalActivityRepository(
        db,
        initial: d.activity,
        broken: [
          for (final k in d.kept)
            if (LegacyKeys.isActivityBroken(k.key)) k,
        ],
      );
      // (no readable log left: only the kept values)
      expect(log.export().keys, {
        'learn.activity.broken',
        'learn.activity.broken.2',
      });
      await log.dispose();
    });

    test('a value not a list (talk) is kept aside whole', () async {
      final kv = MemoryKeyValueStore({'talk.messages': '{"a":1}'});
      final db = memoryDb();
      await KvMigration(kv, db).run();
      final d = await LocalData.load(db);
      expect(d.kept.single.key, 'talk.messages');
      expect(d.kept.single.value, '{"a":1}');
      expect(d.messages, isEmpty);
    });

    test('a newer value already in the database wins; the old one is kept '
        'aside', () async {
      final db = memoryDb();
      final kv = await DriftKeyValueStore.load(db);
      await kv.setString('settings.theme', 'light');
      await KvMigration(
        MemoryKeyValueStore({'settings.theme': 'dark', 'setup.spoken': 'en'}),
        db,
      ).run();
      final back = await DriftKeyValueStore.load(db);
      expect(back.getString('settings.theme'), 'light');
      expect(back.getString('setup.spoken'), 'en');
      final kept = (await LocalData.load(db)).kept.single;
      expect(kept.key, 'settings.theme');
      expect(kept.value, '"dark"');
      expect(kept.reason, 'a newer value is in the database');
    });

    test('a value left after its copy that differs from the database is '
        'kept aside before its key goes', () async {
      final db = memoryDb();
      final kv = MemoryKeyValueStore({'setup.spoken': 'en'});
      // the part was copied by an earlier start (marker written) ...
      await KvMigration(
        kv,
        db,
        onStep: (p) async {
          if (p == 'copied:prefs') throw const KvMigrationKilled('copied');
        },
      ).run().catchError((_) => <LegacyPart, PartReport>{});
      // ... then the database value changed (the old key was still there)
      await (await DriftKeyValueStore.load(db)).setString('setup.spoken', 'ar');
      await KvMigration(kv, db).run();
      expect(kv.keys, isEmpty);
      expect(
        (await DriftKeyValueStore.load(db)).getString('setup.spoken'),
        'ar',
      );
      final kept = (await LocalData.load(db)).kept.single;
      expect(kept.value, '"en"');
      expect(kept.reason, 'left in the old store after its copy');
    });

    test(
      'a part that fails is left in the old store; the others go on',
      () async {
        final kv = MemoryKeyValueStore(snapshot('v9'));
        final db = memoryDb();
        // the talk part's transaction fails (not a kill: an error)
        await KvMigration(
          kv,
          db,
          onStep: (p) async {
            if (p == 'copying:talk') throw StateError('disk full');
          },
        ).run();
        expect(kv.keys, containsAll(['talk.messages', 'talk.version']));
        expect(kv.keys, isNot(contains('phrases.all')));
        expect((await LocalData.load(db)).messages, isEmpty);
        // the next start moves it
        await KvMigration(kv, db).run();
        expect(kv.keys, isEmpty);
        expect((await LocalData.load(db)).messages, hasLength(4));
      },
    );
  });

  group('the key-value store on the database', () {
    test('every type a phone store holds round-trips', () async {
      final db = memoryDb();
      final kv = await DriftKeyValueStore.load(db);
      await kv.setString('s', 'نص');
      await kv.setBool('b', value: true);
      await kv.setInt('i', 15);
      await db
          .into(db.prefs)
          .insert(
            PrefsCompanion.insert(key: 'l', value: '["a","b"]', updatedAtUs: 1),
          );
      await db
          .into(db.prefs)
          .insert(
            PrefsCompanion.insert(key: 'd', value: '1.5', updatedAtUs: 1),
          );
      await db
          .into(db.prefs)
          .insert(
            PrefsCompanion.insert(key: 'bad', value: '{x', updatedAtUs: 1),
          );
      final back = await DriftKeyValueStore.load(db);
      expect(back.getString('s'), 'نص');
      expect(back.getBool('b'), isTrue);
      expect(back.getInt('i'), 15);
      expect(back.read('l'), ['a', 'b']);
      expect(back.read('d'), 1.5);
      expect(back.read('bad'), isNull);
      expect(back.getString('i'), isNull);
      await back.remove('s');
      expect((await DriftKeyValueStore.load(db)).keys, isNot(contains('s')));
    });

    test('every write stamps updatedAt (the sync needs it)', () async {
      final db = memoryDb();
      final kv = await DriftKeyValueStore.load(db);
      await kv.setString('settings.theme', 'dark');
      final row = await db.select(db.prefs).getSingle();
      expect(row.updatedAtUs, greaterThan(0));
    });
  });

  test('contacts on the database: add, replace, remove, persist', () async {
    final db = memoryDb();
    final repo = LocalEmergencyContactsRepository(db);
    await repo.add(const EmergencyContact(name: 'A', phone: '+201'));
    await repo.add(const EmergencyContact(name: 'B', phone: '+202'));
    await repo.replace(0, const EmergencyContact(name: 'C', phone: '+203'));
    await repo.remove(1);
    expect((await LocalData.load(db)).contacts, [
      const EmergencyContact(name: 'C', phone: '+203'),
    ]);
    await repo.dispose();
  });
}
