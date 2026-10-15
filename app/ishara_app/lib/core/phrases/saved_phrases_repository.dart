import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:meta/meta.dart';

/// A starred sentence (Q-B4): it syncs after step 10 (Phase 0 model
/// `users/{uid}/phrases/{phraseId}`: text, lang, createdAt, updatedAt,
/// deleted). Unstarring keeps a tombstone, so a phrase removed offline isn't
/// brought back by the sync.
@immutable
class SavedPhrase {
  const new({
    required this.id,
    required this.text,
    required this.lang,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String text;

  /// `en` or `ar`: the language the text is in.
  final String lang;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  SavedPhrase copyWith({required bool deleted, required DateTime at}) =>
      SavedPhrase(
        id: id,
        text: text,
        lang: lang,
        createdAt: createdAt,
        updatedAt: at,
        deleted: deleted,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    'lang': lang,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };

  static SavedPhrase? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final text = j['text'];
    final lang = j['lang'];
    final created = j['createdAt'] is String
        ? DateTime.tryParse(j['createdAt'] as String)
        : null;
    final updated = j['updatedAt'] is String
        ? DateTime.tryParse(j['updatedAt'] as String)
        : null;
    final deleted = j['deleted'];
    if (id is! String ||
        text is! String ||
        (lang != 'en' && lang != 'ar') ||
        created == null ||
        updated == null ||
        deleted is! bool) {
      return null;
    }
    return SavedPhrase(
      id: id,
      text: text,
      lang: lang! as String,
      createdAt: created,
      updatedAt: updated,
      deleted: deleted,
    );
  }
}

/// The language of a sentence: Arabic when it has an Arabic letter.
String phraseLanguage(String text) =>
    RegExp('[؀-ۿ]').hasMatch(text) ? 'ar' : 'en';

/// Starred sentences (History › Starred).
abstract interface class SavedPhrasesRepository {
  /// Live phrases (not deleted), newest first.
  List<SavedPhrase> get phrases;

  /// [phrases] after each change.
  Stream<List<SavedPhrase>> get changes;

  /// The live phrase with exactly this text, if any.
  SavedPhrase? find(String text);

  /// Stars [text] (a live phrase with it is kept as it is).
  Future<void> star(String text);

  /// Unstars [text] (a tombstone stays for the sync).
  Future<void> unstar(String text);

  /// Every stored value by key (Privacy › Export, step 10).
  Map<String, Object> export();
}

/// The phrases in the phone's key-value store (S6-2 pattern), one
/// versioned JSON list, tombstones included.
///
/// **Migration and sync (step 10):** the database reads [export] and calls
/// [clear]; the sync uploads every entry (last writer wins by `updatedAt`).
class LocalSavedPhrasesRepository implements SavedPhrasesRepository {
  new(this._kv, {DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure(),
      _all = _load(_kv);

  final KeyValueStore _kv;
  final DateTime Function() _now;
  final Random _random;
  final List<SavedPhrase> _all;
  final _changes = StreamController<List<SavedPhrase>>.broadcast();

  static const schemaVersion = 1;
  static const kVersion = 'phrases.version';
  static const kPhrases = 'phrases.all';
  static final _log = Log('phrases');

  static List<SavedPhrase> _load(KeyValueStore kv) {
    final raw = kv.getString(kPhrases);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) throw const FormatException('not a list');
      return [for (final j in list) ?SavedPhrase.fromJson(j)];
    } on FormatException catch (e) {
      _log.warn('load_failed', {'error': e.message});
      return [];
    }
  }

  @override
  List<SavedPhrase> get phrases => List.unmodifiable(
    _all.where((p) => !p.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
  );

  @override
  Stream<List<SavedPhrase>> get changes => _changes.stream;

  @override
  SavedPhrase? find(String text) {
    final t = text.trim();
    for (final p in _all) {
      if (!p.deleted && p.text == t) return p;
    }
    return null;
  }

  @override
  Future<void> star(String text) async {
    final t = text.trim();
    if (t.isEmpty || find(t) != null) return;
    final now = _now();
    final i = _all.indexWhere((p) => p.text == t);
    if (i >= 0) {
      // a tombstone comes back to life (same id: one document to sync)
      _all[i] = _all[i].copyWith(deleted: false, at: now);
    } else {
      _all.add(
        SavedPhrase(
          id: [
            for (var i = 0; i < 10; i++)
              _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ].join(),
          text: t,
          lang: phraseLanguage(t),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _save();
  }

  @override
  Future<void> unstar(String text) async {
    final t = text.trim();
    final i = _all.indexWhere((p) => !p.deleted && p.text == t);
    if (i < 0) return;
    _all[i] = _all[i].copyWith(deleted: true, at: _now());
    await _save();
  }

  Future<void> _save() async {
    _changes.add(phrases);
    await _kv.setInt(kVersion, schemaVersion);
    await _kv.setString(
      kPhrases,
      jsonEncode([for (final p in _all) p.toJson()]),
    );
  }

  @override
  Map<String, Object> export() => {
    if (_kv.getInt(kVersion) case final int v) kVersion: v,
    if (_kv.getString(kPhrases) case final String v) kPhrases: v,
  };

  /// Removes every value (after a successful migration).
  Future<void> clear() async {
    _all.clear();
    _changes.add(phrases);
    await _kv.remove(kVersion);
    await _kv.remove(kPhrases);
  }

  Future<void> dispose() => _changes.close();
}
