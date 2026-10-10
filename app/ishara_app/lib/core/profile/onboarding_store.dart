import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:meta/meta.dart';

/// Who uses this phone (Setup › "Who uses this phone?"). It decides what
/// comes first on Talk (Q-D4).
enum UserRole {
  /// "I sign": the glove text first.
  sign,

  /// "I speak": face-to-face, the mic card first.
  speak,
}

/// The paired glove, so the app can reconnect to it after a restart.
@immutable
class PairedGlove {
  const new({required this.id, required this.name});

  /// Transport id (BLE address / iOS identifier).
  final String id;

  /// `Ishara-XXXX`.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is PairedGlove && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// What onboarding saves on the phone (S6-2), in one versioned schema.
///
/// **Migration (S6-2):** when the local database replaces this store, it
/// reads [export] (every value below, by name) and writes it into its own
/// tables, then calls [clear]; nothing is lost. The database step adds the
/// migration test. Keys never change meaning; a new meaning gets a new key
/// and a higher [schemaVersion].
class OnboardingStore {
  new(this._kv);

  final KeyValueStore _kv;

  static const schemaVersion = 1;

  // Keys (the shared_preferences store prefixes them with `ishara.`).
  static const kVersion = 'onboarding.version';
  static const kRole = 'setup.role';
  static const kSpoken = 'setup.spoken';
  static const kSignLanguage = 'setup.signLanguage';
  static const kGloveId = 'glove.id';
  static const kGloveName = 'glove.name';
  static const kDone = 'onboarding.done';

  static const List<String> _all = [
    kVersion,
    kRole,
    kSpoken,
    kSignLanguage,
    kGloveId,
    kGloveName,
    kDone,
  ];

  UserRole get role => switch (_kv.getString(kRole)) {
    'speak' => UserRole.speak,
    _ => UserRole.sign,
  };

  /// The voice. Arabic by default (prototype `voice:'ar'`).
  SpokenLanguage get spoken => switch (_kv.getString(kSpoken)) {
    'en' => SpokenLanguage.en,
    _ => SpokenLanguage.ar,
  };

  /// The stored sign-language id, as saved (`asl`); the packs layer resolves
  /// it (a stored `arsl` falls back to ASL, sign rule 8).
  String? get signLanguageId => _kv.getString(kSignLanguage);

  PairedGlove? get glove {
    final id = _kv.getString(kGloveId);
    final name = _kv.getString(kGloveName);
    if (id == null || name == null) return null;
    return PairedGlove(id: id, name: name);
  }

  /// Onboarding finished: the app starts on Talk.
  bool get done => _kv.getBool(kDone) ?? false;

  Future<void> _stamp() => _kv.setInt(kVersion, schemaVersion);

  Future<void> saveRole(UserRole role) async {
    await _stamp();
    await _kv.setString(kRole, role.name);
  }

  Future<void> saveSpoken(SpokenLanguage spoken) async {
    await _stamp();
    await _kv.setString(kSpoken, spoken.name);
  }

  Future<void> saveSignLanguageId(String id) async {
    await _stamp();
    await _kv.setString(kSignLanguage, id);
  }

  Future<void> saveGlove(PairedGlove glove) async {
    await _stamp();
    await _kv.setString(kGloveId, glove.id);
    await _kv.setString(kGloveName, glove.name);
  }

  Future<void> forgetGlove() async {
    await _kv.remove(kGloveId);
    await _kv.remove(kGloveName);
  }

  Future<void> saveDone({required bool done}) async {
    await _stamp();
    await _kv.setBool(kDone, value: done);
  }

  /// Every stored value by key, for the database migration (S6-2).
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
