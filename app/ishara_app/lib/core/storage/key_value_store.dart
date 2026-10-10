import 'package:shared_preferences/shared_preferences.dart';

/// A small key-value store on the phone (S6-2): the setup answers, the
/// paired glove and "onboarding done" until the local database arrives. The
/// database step migrates these values (see `OnboardingStore`).
///
/// Reads are synchronous (the values are loaded once at start).
abstract interface class KeyValueStore {
  String? getString(String key);
  bool? getBool(String key);
  int? getInt(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, {required bool value});
  Future<void> setInt(String key, int value);
  Future<void> remove(String key);

  /// Every key currently stored (for the migration and its test).
  Set<String> get keys;
}

/// In memory: tests, and the fallback when the phone store can't open.
class MemoryKeyValueStore implements KeyValueStore {
  new([Map<String, Object>? values]) : _v = {...?values};

  final Map<String, Object> _v;

  @override
  String? getString(String key) =>
      _v[key] is String ? _v[key]! as String : null;

  @override
  bool? getBool(String key) => _v[key] is bool ? _v[key]! as bool : null;

  @override
  int? getInt(String key) => _v[key] is int ? _v[key]! as int : null;

  @override
  Future<void> setString(String key, String value) async => _v[key] = value;

  @override
  Future<void> setBool(String key, {required bool value}) async =>
      _v[key] = value;

  @override
  Future<void> setInt(String key, int value) async => _v[key] = value;

  @override
  Future<void> remove(String key) async => _v.remove(key);

  @override
  Set<String> get keys => _v.keys.toSet();
}

/// On the phone: `shared_preferences` (BSD-3, Flutter team, no network).
/// Only keys under [prefix] are read or written.
class SharedPrefsKeyValueStore implements KeyValueStore {
  new _(this._p);

  static const prefix = 'ishara.';

  static Future<SharedPrefsKeyValueStore> open() async =>
      SharedPrefsKeyValueStore._(
        await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(),
        ),
      );

  final SharedPreferencesWithCache _p;

  static String _k(String key) => '$prefix$key';

  @override
  String? getString(String key) {
    final v = _p.get(_k(key));
    return v is String ? v : null;
  }

  @override
  bool? getBool(String key) {
    final v = _p.get(_k(key));
    return v is bool ? v : null;
  }

  @override
  int? getInt(String key) {
    final v = _p.get(_k(key));
    return v is int ? v : null;
  }

  @override
  Future<void> setString(String key, String value) =>
      _p.setString(_k(key), value);

  @override
  Future<void> setBool(String key, {required bool value}) =>
      _p.setBool(_k(key), value);

  @override
  Future<void> setInt(String key, int value) => _p.setInt(_k(key), value);

  @override
  Future<void> remove(String key) => _p.remove(_k(key));

  @override
  Set<String> get keys => {
    for (final k in _p.keys)
      if (k.startsWith(prefix)) k.substring(prefix.length),
  };
}
