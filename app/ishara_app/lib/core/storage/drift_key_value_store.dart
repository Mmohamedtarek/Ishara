import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

/// The named values in the database's `prefs` table (step 10a). All of them
/// are read at start; a write changes the value at once and is stored in
/// the background of the returned future.
class DriftKeyValueStore implements KeyValueStore {
  new _(this._db, this._v);

  /// Reads every value. A row whose value can't be decoded is skipped (it
  /// stays in the table untouched).
  static Future<DriftKeyValueStore> load(AppDatabase db) async {
    final rows = await db.select(db.prefs).get();
    return DriftKeyValueStore._(db, {
      for (final r in rows)
        if (decode(r.value) case final Object v) r.key: v,
    });
  }

  final AppDatabase _db;
  final Map<String, Object> _v;

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
    _v[key] = value;
    return _db
        .into(_db.prefs)
        .insertOnConflictUpdate(
          PrefsCompanion.insert(
            key: key,
            value: encode(value),
            updatedAtUs: clock.now().microsecondsSinceEpoch,
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
    await (_db.delete(_db.prefs)..where((t) => t.key.equals(key))).go();
  }

  @override
  Set<String> get keys => _v.keys.toSet();
}
