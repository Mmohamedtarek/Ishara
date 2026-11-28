import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:ishara_app/core/sync/outbox.dart';
import 'package:ishara_app/core/sync/settings_doc.dart';

/// The named values in the database's `prefs` table (step 10a). All of them
/// are read at start; a write changes the value at once and is stored in
/// the background of the returned future.
class DriftKeyValueStore implements KeyValueStore {
  new _(this._db, this._v, this._t);

  /// Reads every value. A row whose value can't be decoded is skipped (it
  /// stays in the table untouched).
  static Future<DriftKeyValueStore> load(AppDatabase db) async {
    final rows = await db.select(db.prefs).get();
    return DriftKeyValueStore._(
      db,
      {
        for (final r in rows)
          if (decode(r.value) case final Object v) r.key: v,
      },
      {for (final r in rows) r.key: r.updatedAtUs},
    );
  }

  final AppDatabase _db;
  final Map<String, Object> _v;

  /// Each value's `updatedAtUs`.
  final Map<String, int> _t;

  /// The JSON form a value is stored in.
  static String encode(Object value) => jsonEncode(value);

  /// A stored value, or null when it isn't one a key-value store can hold.
  static Object? decode(String text) {
    try {
      return switch (jsonDecode(text)) {
        final String v => v,
        final bool v => v,
        final int v => v,
        final double v => v,
        final List<Object?> v when v.every((e) => e is String) =>
          v.cast<String>().toList(),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  Future<void> _put(String key, Object value) {
    final at = clock.now().microsecondsSinceEpoch;
    _v[key] = value;
    _t[key] = at;
    return storeOrKeepGoing(
      () => _db.transaction(() async {
        await _db
            .into(_db.prefs)
            .insertOnConflictUpdate(
              PrefsCompanion.insert(
                key: key,
                value: encode(value),
                updatedAtUs: at,
              ),
            );
        // a synced value changed: the settings document goes up (10b)
        if (SettingsDoc.keys.contains(key)) {
          await enqueue(_db, Synced.settings, Synced.settingsDoc);
        }
      }),
    );
  }

  /// The settings document's time: its newest synced value's, or null when
  /// none is stored (last writer wins per document, Phase 0).
  DateTime? get settingsUpdatedAt {
    int? newest;
    for (final k in SettingsDoc.keys) {
      final t = _t[k];
      if (_v.containsKey(k) && t != null && (newest == null || t > newest)) {
        newest = t;
      }
    }
    return newest == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(newest, isUtc: true);
  }

  /// The account's settings (the sync): stored with the document's time so
  /// they aren't sent back, not queued.
  Future<void> applyRemote(Map<String, Object> values, DateTime at) async {
    final us = at.microsecondsSinceEpoch;
    for (final e in values.entries) {
      _v[e.key] = e.value;
      _t[e.key] = us;
    }
    await storeOrKeepGoing(
      () => _db.batch(
        (b) => b.insertAllOnConflictUpdate(_db.prefs, [
          for (final e in values.entries)
            PrefsCompanion.insert(
              key: e.key,
              value: encode(e.value),
              updatedAtUs: us,
            ),
        ]),
      ),
    );
  }

  /// Shows [values] this session without storing them, for keys with no
  /// value yet (an old-store part that couldn't move: `openStorage`). A
  /// value set later is stored as usual.
  void showUnstored(Map<String, Object> values) {
    for (final MapEntry(:key, :value) in values.entries) {
      _v.putIfAbsent(key, () => value);
    }
  }

  @override
  Object? read(String key) => _v[key];

  @override
  String? getString(String key) =>
      _v[key] is String ? _v[key]! as String : null;

  @override
  bool? getBool(String key) => _v[key] is bool ? _v[key]! as bool : null;

  @override
  int? getInt(String key) => _v[key] is int ? _v[key]! as int : null;

  @override
  Future<void> setString(String key, String value) => _put(key, value);

  @override
  Future<void> setBool(String key, {required bool value}) => _put(key, value);

  @override
  Future<void> setInt(String key, int value) => _put(key, value);

  @override
  Future<void> remove(String key) async {
    _v.remove(key);
    _t.remove(key);
    await storeOrKeepGoing(
      () => _db.transaction(() async {
        await (_db.delete(_db.prefs)..where((t) => t.key.equals(key))).go();
        if (SettingsDoc.keys.contains(key)) {
          await enqueue(_db, Synced.settings, Synced.settingsDoc);
        }
      }),
    );
  }

  /// Account deletion (Q-B1): every value goes.
  Future<void> clearAll() async {
    _v.clear();
    _t.clear();
    await storeOrKeepGoing(() => _db.delete(_db.prefs).go());
  }

  @override
  Set<String> get keys => _v.keys.toSet();
}
