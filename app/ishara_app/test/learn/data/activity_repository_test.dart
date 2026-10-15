import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/device/device_id.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';

import '../domain/learn_domain_test_support.dart';

void main() {
  group('the activity log on the phone (append-only, versioned)', () {
    test('appends, keeps the order, survives a restart', () async {
      final kv = MemoryKeyValueStore();
      final repo = LocalActivityRepository(kv);
      final seen = <int>[];
      repo.changes.listen((l) => seen.add(l.length));
      final a = ev(ActivityType.quiz, label: 'hello');
      final b = ev(ActivityType.practice, label: 'hello', prob: .8);
      await repo.append(a);
      await repo.append(b);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [1, 2]);
      expect(kv.getInt(LocalActivityRepository.kVersion), 1);
      final again = LocalActivityRepository(kv);
      expect(
        [for (final e in again.events) e.toJson()],
        [a.toJson(), b.toJson()],
      );
      await repo.dispose();
      await again.dispose();
    });

    test("entries this version can't read are kept (never dropped), not "
        'counted', () async {
      final newer = {...ev(ActivityType.quiz).toJson(), 'v': 2};
      final kv = MemoryKeyValueStore({
        LocalActivityRepository.kEvents: jsonEncode([
          newer,
          ev(ActivityType.quiz, label: 'yes').toJson(),
        ]),
      });
      final repo = LocalActivityRepository(kv);
      expect(repo.events.single.label, 'yes');
      await repo.append(ev(ActivityType.quiz, label: 'no'));
      final stored = jsonDecode(
        kv.getString(LocalActivityRepository.kEvents)!,
      ) as List<Object?>;
      expect(stored, hasLength(3));
      expect(stored.first, newer);
      await repo.dispose();
    });

    test('a damaged value is set aside, never overwritten', () async {
      final kv = MemoryKeyValueStore({
        LocalActivityRepository.kEvents: '{not json',
      });
      final repo = LocalActivityRepository(kv);
      await Future<void>.delayed(Duration.zero);
      expect(repo.events, isEmpty);
      expect(kv.getString(LocalActivityRepository.kBroken), '{not json');
      await repo.append(ev(ActivityType.quiz));
      expect(kv.getString(LocalActivityRepository.kBroken), '{not json');
      // also when the JSON is not a list
      final kv2 = MemoryKeyValueStore({LocalActivityRepository.kEvents: '{}'});
      LocalActivityRepository(kv2);
      await Future<void>.delayed(Duration.zero);
      expect(kv2.getString(LocalActivityRepository.kBroken), '{}');
      await repo.dispose();
    });

    test(
      'a second damaged value gets its own key (the first is kept)',
      () async {
        final kv = MemoryKeyValueStore({
          LocalActivityRepository.kEvents: 'bad 1',
        });
        LocalActivityRepository(kv);
        await Future<void>.delayed(Duration.zero);
        await kv.setString(LocalActivityRepository.kEvents, 'bad 2');
        final repo = LocalActivityRepository(kv);
        await Future<void>.delayed(Duration.zero);
        expect(kv.getString(LocalActivityRepository.kBroken), 'bad 1');
        expect(kv.getString('${LocalActivityRepository.kBroken}.2'), 'bad 2');
        expect(
          repo.export().keys,
          contains('${LocalActivityRepository.kBroken}.2'),
        );
        await repo.clear();
        expect(kv.keys, isEmpty);
      },
    );

    test('export for the step 10 database, then clear', () async {
      final kv = MemoryKeyValueStore({
        LocalActivityRepository.kBroken: 'x',
        'other': 'kept',
      });
      final repo = LocalActivityRepository(kv);
      await repo.append(ev(ActivityType.quiz));
      final out = repo.export();
      expect(out.keys.toSet(), {
        LocalActivityRepository.kVersion,
        LocalActivityRepository.kEvents,
        LocalActivityRepository.kBroken,
      });
      await repo.clear();
      expect(repo.events, isEmpty);
      expect(kv.keys, {'other'});
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
