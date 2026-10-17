import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/device/device_id.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';

import '../../support/local_db.dart';
import '../domain/learn_domain_test_support.dart';

void main() {
  group('the activity log in the database (append-only)', () {
    test('appends, keeps the order, survives a restart', () async {
      final db = memoryDb();
      final repo = LocalActivityRepository(db);
      final seen = <int>[];
      repo.changes.listen((l) => seen.add(l.length));
      final a = ev(ActivityType.quiz, label: 'hello');
      final b = ev(ActivityType.practice, label: 'hello', prob: .8);
      await repo.append(a);
      await repo.append(b);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [1, 2]);
      final again = LocalActivityRepository(
        db,
        initial: (await reload(db)).activity,
      );
      expect(
        [for (final e in again.events) e.toJson()],
        [a.toJson(), b.toJson()],
      );
      await repo.dispose();
      await again.dispose();
    });

    test("entries this version can't read are kept (never dropped), not "
        'counted', () async {
      final db = memoryDb();
      final newer = {...ev(ActivityType.quiz).toJson(), 'v': 2};
      final repo = LocalActivityRepository(
        db,
        initial: [
          (id: newer['id']! as String, json: jsonEncode(newer)),
          (
            id: 'y',
            json: jsonEncode(ev(ActivityType.quiz, label: 'yes').toJson()),
          ),
        ],
      );
      expect(repo.events.single.label, 'yes');
      await repo.append(ev(ActivityType.quiz, label: 'no'));
      final stored = jsonDecode(
        repo.export()[LocalActivityRepository.kEvents]! as String,
      ) as List<Object?>;
      expect(stored, hasLength(3));
      expect(stored.first, newer);
      await repo.dispose();
    });

    test('an event id already stored is kept once', () async {
      final db = memoryDb();
      final repo = LocalActivityRepository(db);
      final a = ev(ActivityType.quiz, label: 'hello');
      await repo.append(a);
      await repo.append(a);
      expect(await db.select(db.activityEntries).get(), hasLength(1));
      await repo.dispose();
    });

    test('export keeps its step 8 shape, with the values kept aside', () async {
      final repo = LocalActivityRepository(
        memoryDb(),
        broken: const [
          KeptValue(key: 'learn.activity.broken', value: 'x', reason: 'r'),
        ],
      );
      await repo.append(ev(ActivityType.quiz));
      final out = repo.export();
      expect(out.keys.toSet(), {
        LocalActivityRepository.kVersion,
        LocalActivityRepository.kEvents,
        LocalActivityRepository.kBroken,
      });
      expect(out[LocalActivityRepository.kBroken], 'x');
      await repo.dispose();
    });
  });

  group('device id (Phase 0 deviceId)', () {
    test('made once (128 random bits), then the same', () {
      final kv = MemoryKeyValueStore();
      final id = DeviceId.of(kv, random: Random(1));
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(DeviceId.of(kv), id);
      expect(DeviceId.of(MemoryKeyValueStore()), isNot(id));
    });
  });
}
