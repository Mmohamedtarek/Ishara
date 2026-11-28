/// `users/{uid}/settings/app` (Phase 0) ↔ the phone's named values. Only
/// these sync; developer mode, the paired glove, onboarding and the Talk
/// flags stay on the phone. Each field is sent only with a value the
/// security rules accept (`firebase/firestore.rules`).
abstract final class SettingsDoc {
  /// remote field → (phone key, allowed phone values or null = any text)
  static const _fields = <String, (String, Set<Object>?)>{
    'uiLang': ('settings.language', {'en', 'ar'}),
    'theme': ('settings.theme', {'system', 'light', 'dark'}),
    // ArSL is never active in v1 (sign rule 8): only ASL syncs
    'signLanguage': ('setup.signLanguage', {'asl'}),
    'spokenLanguage': ('setup.spoken', {'en', 'ar'}),
    'who': ('setup.role', {'sign', 'speak'}),
    'avatarId': ('settings.character', null),
    // tenths on the phone (5, 10, 15), 0.5 / 1 / 1.5 in the account
    'signSpeed': ('settings.signSpeed', {5, 10, 15}),
    'subtitles': ('settings.subtitles', {true, false}),
    'bigText': ('settings.bigText', {true, false}),
    'highContrast': ('settings.highContrast', {true, false}),
    'vibrate': ('settings.vibrate', {true, false}),
  };

  /// The phone keys that sync.
  static final Set<String> keys = {for (final f in _fields.values) f.$1};

  static bool _ok(Object? v, Set<Object>? allowed) =>
      v != null &&
      (allowed == null
          ? v is String && v.isNotEmpty && v.length <= 40
          : allowed.contains(v));

  /// The document for the phone's [values] (by phone key), at [updatedAt].
  static Map<String, Object?> toRemote(
    Object? Function(String key) values,
    DateTime updatedAt,
  ) => {
    'updatedAt': updatedAt.toUtc(),
    for (final MapEntry(key: field, value: (key, allowed)) in _fields.entries)
      if (values(key) case final v? when _ok(v, allowed))
        field: field == 'signSpeed' ? (v as int) / 10 : v,
  };

  /// The phone's values (by phone key) in a [doc]; fields with a value the
  /// app doesn't know are left out.
  static Map<String, Object> fromRemote(Map<String, Object?> doc) {
    final out = <String, Object>{};
    for (final MapEntry(key: field, value: (key, allowed)) in _fields.entries) {
      var v = doc[field];
      if (field == 'signSpeed') v = v is num ? (v * 10).round() : null;
      if (_ok(v, allowed)) out[key] = v!;
    }
    return out;
  }
}
