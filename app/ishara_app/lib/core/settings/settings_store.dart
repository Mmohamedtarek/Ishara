import 'package:flutter/material.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

/// The app's settings on the phone (S6-2): display, accessibility, avatar
/// and developer mode, in one versioned schema.
///
/// **Migration (step 10):** the database reads [export] (every value by
/// name) and calls [clear]; the database step adds the migration test. Keys
/// never change meaning; a new meaning gets a new key and a higher
/// [schemaVersion].
class SettingsStore {
  new(this._kv);

  final KeyValueStore _kv;

  static const schemaVersion = 1;

  static const kVersion = 'settings.version';
  static const kLanguage = 'settings.language';
  static const kTheme = 'settings.theme';
  static const kBigText = 'settings.bigText';
  static const kHighContrast = 'settings.highContrast';
  static const kVibrate = 'settings.vibrate';
  static const kSubtitles = 'settings.subtitles';
  static const kSignSpeed = 'settings.signSpeed';
  static const kCharacter = 'settings.character';
  static const kDeveloper = 'settings.developer';

  static const List<String> _all = [
    kVersion,
    kLanguage,
    kTheme,
    kBigText,
    kHighContrast,
    kVibrate,
    kSubtitles,
    kSignSpeed,
    kCharacter,
    kDeveloper,
  ];

  String? getString(String key) => _kv.getString(key);
  bool? getBool(String key) => _kv.getBool(key);

  /// The saved theme (System when none, Q-D3).
  ThemeMode get themeMode =>
      ThemeMode.values.asNameMap()[_kv.getString(kTheme)] ?? ThemeMode.system;

  /// Speeds are stored as tenths (5, 10, 15): the store keeps whole numbers.
  double? get signSpeed => switch (_kv.getInt(kSignSpeed)) {
    final int t => t / 10,
    _ => null,
  };

  Future<void> _stamp() => _kv.setInt(kVersion, schemaVersion);

  Future<void> setString(String key, String value) async {
    await _stamp();
    await _kv.setString(key, value);
  }

  Future<void> setBool(String key, {required bool value}) async {
    await _stamp();
    await _kv.setBool(key, value: value);
  }

  Future<void> setSignSpeed(double speed) async {
    await _stamp();
    await _kv.setInt(kSignSpeed, (speed * 10).round());
  }

  /// Every stored value by key, for the database migration.
  Map<String, Object> export() => {
    for (final k in _all)
      if (_kv.getString(k) case final String v)
        k: v
      else if (_kv.getBool(k) case final bool v)
        k: v
      else if (_kv.getInt(k) case final int v)
        k: v,
  };

  /// Removes every value (after a successful migration).
  Future<void> clear() async {
    for (final k in _all) {
      await _kv.remove(k);
    }
  }
}
