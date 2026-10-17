import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:meta/meta.dart';

/// What one part of the migration did (for the log: counts only, never
/// values).
/// `stored`: old values now in their tables (copied now, or found stored
/// when `earlier`); `kept`: kept aside; `removed`: old keys removed;
/// `earlier`: the part was copied by an earlier start.
typedef PartReport = ({int stored, int kept, int removed, bool earlier});

/// Moves the old key-value store into the database, once (S6-2, S7-1,
/// step 10a). Runs at every start before anything reads the data; with
/// nothing left in the old store it does nothing.
///
/// Each part ([LegacyPart]) goes in its own transaction: its rows are
/// written, read back and compared with the old values (an old value that
/// can't be stored as it was is kept aside in `kept_values`), and a marker
/// is written; only after that commit are the part's old keys removed.
///
/// Killed halfway: before a commit nothing of that part is stored and its
/// keys are still there, so the next start copies it again; after the
/// commit the marker says it is done, so the next start only removes the
/// keys that are left (after checking they match what was stored). Nothing
/// is lost or stored twice.
class KvMigration {
  new(this._kv, this._db, {Random? random, this.onStep})
    : _random = random ?? Random.secure();

  final KeyValueStore _kv;
  final AppDatabase _db;
  final Random _random;

  /// Called at each point where the app could be killed (tests throw from
  /// it): `copying:<part>` inside the transaction, `copied:<part>` after
  /// its commit, `removed:<key>` after each old key is removed.
  @visibleForTesting
  final Future<void> Function(String point)? onStep;

  static final _log = Log('storage');

  /// The parts [run] couldn't move (left in the old store for the next
  /// start; this session reads them from there, see `openStorage`).
  final failed = <LegacyPart>{};

  static String markerKey(LegacyPart part) => 'kv.migrated.${part.name}';

  Future<void> _step(String point) async => await onStep?.call(point);

  int get _now => clock.now().microsecondsSinceEpoch;

  /// Migrates every part. A part that fails is logged and left in the old
  /// store (the next start tries again); it never stops the app.
  Future<Map<LegacyPart, PartReport>> run() async {
    final data = LegacyData.read(_kv, random: _random);
    final report = <LegacyPart, PartReport>{};
    if (data.isEmpty) return report;
    for (final part in LegacyPart.values) {
      final keys = data.keys[part]!;
      if (keys.isEmpty) continue;
      try {
        final marker = await (_db.select(
          _db.meta,
        )..where((t) => t.key.equals(markerKey(part)))).getSingleOrNull();
        final earlier = marker != null;
        final (stored, kept) = await _db.transaction(() async {
          final r = await _reconcile(part, data, insert: !earlier);
          if (!earlier) {
            await _step('copying:${part.name}');
            await _db
                .into(_db.meta)
                .insert(
                  MetaCompanion.insert(
                    key: markerKey(part),
                    value: jsonEncode({
                      'atUs': _now,
                      'stored': r.$1,
                      'kept': r.$2,
                    }),
                  ),
                );
          }
          return r;
        });
        await _step('copied:${part.name}');
        var removed = 0;
        for (final k in keys) {
          await _kv.remove(k);
          removed++;
          await _step('removed:$k');
        }
        report[part] = (
          stored: stored,
          kept: kept,
          removed: removed,
          earlier: earlier,
        );
        _log.info('kv_migrated', {
          'part': part.name,
          'stored': stored,
          'kept': kept,
          'removed': removed,
          'earlier': earlier,
        });
      } on Object catch (e) {
        failed.add(part);
        _log.warn('kv_migration_failed', {
          'part': part.name,
          'error': e.runtimeType.toString(),
        });
        if (e is KvMigrationKilled) rethrow;
      }
    }
    return report;
  }

  Future<void> _keep(KeptValue k) => _db
      .into(_db.keptValues)
      .insert(
        KeptValuesCompanion.insert(
          key: k.key,
          value: k.value,
          reason: k.reason,
          keptAtUs: _now,
        ),
      );

  /// Writes [part] ([insert]) and checks every old value is stored as it
  /// was, or keeps it aside. With [insert] false (copied by an earlier
  /// start) it only checks: an old value that isn't stored (changed since)
  /// is kept aside before its key goes. Returns (stored, kept aside).
  Future<(int, int)> _reconcile(
    LegacyPart part,
    LegacyData data, {
    required bool insert,
  }) async {
    final keep = <KeptValue>[];
    var stored = 0;
    final why = insert ? null : 'left in the old store after its copy';

    // Values the part keeps aside anyway (damage, unknown keys): stored
    // once; on a later start, only those not kept yet.
    final existing = await _db.select(_db.keptValues).get();
    bool isKept(KeptValue k) => existing.any(
      (r) => r.key == k.key && r.value == k.value && r.reason == k.reason,
    );
    for (final k in data.kept[part]!) {
      if (insert || !isKept(k)) await _keep(k);
    }

    switch (part) {
      case LegacyPart.prefs:
        if (insert) {
          await _db.batch(
            (b) => b.insertAll(_db.prefs, [
              for (final MapEntry(:key, :value) in data.prefs.entries)
                PrefsCompanion.insert(
                  key: key,
                  value: DriftKeyValueStore.encode(value),
                  updatedAtUs: _now,
                ),
            ], mode: InsertMode.insertOrIgnore),
          );
        }
        final rows = {
          for (final r in await _db.select(_db.prefs).get()) r.key: r.value,
        };
        for (final MapEntry(:key, :value) in data.prefs.entries) {
          final back = rows[key] == null
              ? null
              : DriftKeyValueStore.decode(rows[key]!);
          if (_same(back, value)) {
            stored++;
          } else {
            keep.add(
              KeptValue(
                key: key,
                value: jsonEncode(value),
                reason: why ?? 'a newer value is in the database',
              ),
            );
          }
        }
      case LegacyPart.talk:
        if (insert) {
          await _db.batch(
            (b) => b.insertAll(
              _db.messages,
              data.messages.map(LocalConversationRepository.row),
              mode: InsertMode.insertOrIgnore,
            ),
          );
        }
        // compared by content: ids are new on every read of the old store
        final rows = await _db.select(_db.messages).get();
        final left = [
          for (final r in rows)
            TalkMessage(
              side: MessageSide.values.byName(r.side),
              text: r.content,
              at: DateTime.parse(r.at),
              conversation: r.conversation,
            ),
        ];
        for (var i = 0; i < data.messages.length; i++) {
          final m = data.messages[i].message;
          if (left.remove(m)) {
            stored++;
          } else {
            keep.add(
              KeptValue(
                key: '${LegacyKeys.talkMessages}[$i]',
                value: jsonEncode(m.toJson()),
                reason: why ?? 'not stored',
              ),
            );
          }
        }
      case LegacyPart.phrases:
        if (insert) {
          await _db.batch(
            (b) => b.insertAll(_db.phrases, [
              for (final p in data.phrases) LocalSavedPhrasesRepository.row(p),
            ], mode: InsertMode.insertOrIgnore),
          );
        }
        final rows = {
          for (final r in await _db.select(_db.phrases).get()) r.id: r,
        };
        for (final (i, p) in data.phrases.indexed) {
          final row = rows[p.id];
          final back = row == null
              ? null
              : LocalSavedPhrasesRepository.fromRow(row);
          if (back != null &&
              jsonEncode(back.toJson()) == jsonEncode(p.toJson())) {
            stored++;
          } else {
            keep.add(
              KeptValue(
                key: '${LegacyKeys.phrases}[$i]',
                value: jsonEncode(p.toJson()),
                reason: why ?? 'another phrase has its id',
              ),
            );
          }
        }
      case LegacyPart.activity:
        if (insert) {
          await _db.batch(
            (b) => b.insertAll(_db.activityEntries, [
              for (final a in data.activity)
                ActivityEntriesCompanion.insert(id: a.id, json: a.json),
            ], mode: InsertMode.insertOrIgnore),
          );
        }
        final rows = {
          for (final r in await _db.select(_db.activityEntries).get())
            r.id: r.json,
        };
        for (final (i, a) in data.activity.indexed) {
          if (rows[a.id] == a.json) {
            stored++;
          } else {
            keep.add(
              KeptValue(
                key: '${LegacyKeys.activity}[$i]',
                value: a.json,
                reason: why ?? 'another entry has its id',
              ),
            );
          }
        }
      case LegacyPart.sos:
        // Contacts already in the database (added in a session where this
        // part had failed) stay first; the old ones join up to the limit.
        final before = await (_db.select(
          _db.contacts,
        )..orderBy([(t) => OrderingTerm(expression: t.position)])).get();
        final have = [
          for (final r in before)
            EmergencyContact(name: r.name, phone: r.phone),
        ];
        for (final (i, c) in data.contacts.indexed) {
          if (have.contains(c)) {
            stored++;
          } else if (insert && have.length < EmergencyContactsRepository.max) {
            await _db
                .into(_db.contacts)
                .insert(LocalEmergencyContactsRepository.row(have.length, c));
            have.add(c);
            stored++;
          } else {
            keep.add(
              KeptValue(
                key: '${LegacyKeys.contacts}[$i]',
                value: jsonEncode(c.toJson()),
                reason: why ?? 'over the limit with the contacts added since',
              ),
            );
          }
        }
      case LegacyPart.other:
        break;
    }
    for (final k in keep) {
      await _keep(k);
    }
    final keptHere = insert
        ? data.kept[part]!.length + keep.length
        : keep.length;
    return (stored, keptHere);
  }
}

/// Equal stored values: scalars, or lists of them.
bool _same(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}

/// Thrown by tests from [KvMigration.onStep] to stop the run like a kill.
class KvMigrationKilled implements Exception {
  const new(this.point);
  final String point;

  @override
  String toString() => 'killed at $point';
}
