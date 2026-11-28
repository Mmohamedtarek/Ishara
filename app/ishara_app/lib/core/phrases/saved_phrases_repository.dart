import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/hex_id.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:ishara_app/core/sync/outbox.dart';
import 'package:meta/meta.dart';

/// A starred sentence (Q-B4): it syncs (step 10b; Phase 0 model
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

  /// Every stored value by key (Privacy › Export).
  Map<String, Object> export();
}

/// The phrases in the phone's database (`phrases`, step 10a), tombstones
/// included; every row is read at start. The sync (step 10b) uploads every
/// change (last writer wins by `updatedAt`, id as tie-break).
class LocalSavedPhrasesRepository implements SavedPhrasesRepository {
  /// `initial`: every stored phrase (`LocalData`).
  new(
    this._db, {
    List<SavedPhrase> initial = const [],
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure(),
       _all = [...initial];

  final AppDatabase _db;
  final DateTime Function() _now;
  final Random _random;
  final List<SavedPhrase> _all;
  final _changes = StreamController<List<SavedPhrase>>.broadcast();

  /// The phrase JSON's shape in the export, unchanged since step 9.
  static const schemaVersion = 1;
  static const kVersion = 'phrases.version';
  static const kPhrases = 'phrases.all';

  /// The row for [p] (times in microseconds, UTC).
  static PhrasesCompanion row(SavedPhrase p) => PhrasesCompanion.insert(
    id: p.id,
    content: p.text,
    lang: p.lang,
    createdAtUs: p.createdAt.microsecondsSinceEpoch,
    updatedAtUs: p.updatedAt.microsecondsSinceEpoch,
    deleted: Value(p.deleted),
  );

  /// [row] read back.
  static SavedPhrase fromRow(PhraseRow r) => SavedPhrase(
    id: r.id,
    text: r.content,
    lang: r.lang,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(r.createdAtUs, isUtc: true),
    updatedAt: DateTime.fromMicrosecondsSinceEpoch(r.updatedAtUs, isUtc: true),
    deleted: r.deleted,
  );

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
    final SavedPhrase p;
    if (i >= 0) {
      // a tombstone comes back to life (same id: one document to sync)
      p = _all[i] = _all[i].copyWith(deleted: false, at: now);
    } else {
      p = SavedPhrase(
        id: hexId(_random, 10),
        text: t,
        lang: phraseLanguage(t),
        createdAt: now,
        updatedAt: now,
      );
      _all.add(p);
    }
    await _save(p);
  }

  @override
  Future<void> unstar(String text) async {
    final t = text.trim();
    final i = _all.indexWhere((p) => !p.deleted && p.text == t);
    if (i < 0) return;
    final p = _all[i] = _all[i].copyWith(deleted: true, at: _now());
    await _save(p);
  }

  Future<void> _save(SavedPhrase p) async {
    _changes.add(phrases);
    await storeOrKeepGoing(
      () => _db.transaction(() async {
        await _db.into(_db.phrases).insertOnConflictUpdate(row(p));
        // too long for the account: on this phone only
        if (Synced.phraseFits(p.text)) {
          await enqueue(_db, Synced.phrases, p.id);
        }
      }),
    );
  }

  /// Every stored phrase, tombstones included (the sync).
  List<SavedPhrase> get all => List.unmodifiable(_all);

  /// The phrase with [id], tombstone or not.
  SavedPhrase? byId(String id) {
    for (final p in _all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Phrases from the account (the sync): each replaces the local one with
  /// its id when it is newer (last writer wins by `updatedAt`; equal times:
  /// the larger content wins, the same on every phone). Not queued again.
  /// Then two live phrases with the same text keep one: the larger id
  /// becomes a tombstone (queued), the same on every phone.
  Future<void> applyRemote(Iterable<SavedPhrase> remote) async {
    final changed = <SavedPhrase>[];
    for (final r in remote) {
      final i = _all.indexWhere((p) => p.id == r.id);
      if (i < 0) {
        _all.add(r);
        changed.add(r);
      } else if (newer(r, _all[i])) {
        _all[i] = r;
        changed.add(r);
      }
    }
    final dupes = <SavedPhrase>[];
    final live = <String, SavedPhrase>{};
    for (final p in [..._all]..sort((a, b) => a.id.compareTo(b.id))) {
      if (p.deleted) continue;
      if (live.containsKey(p.text)) {
        final dead = p.copyWith(deleted: true, at: _now());
        _all[_all.indexWhere((q) => q.id == p.id)] = dead;
        dupes.add(dead);
      } else {
        live[p.text] = p;
      }
    }
    if (changed.isEmpty && dupes.isEmpty) return;
    _changes.add(phrases);
    await storeOrKeepGoing(
      () => _db.transaction(() async {
        for (final p in changed) {
          await _db.into(_db.phrases).insertOnConflictUpdate(row(p));
        }
        for (final p in dupes) {
          await _db.into(_db.phrases).insertOnConflictUpdate(row(p));
          if (Synced.phraseFits(p.text)) {
            await enqueue(_db, Synced.phrases, p.id);
          }
        }
      }),
    );
  }

  /// Whether [a] wins over [b] (the same phrase id).
  static bool newer(SavedPhrase a, SavedPhrase b) {
    final c = a.updatedAt.compareTo(b.updatedAt);
    if (c != 0) return c > 0;
    return jsonEncode(a.toJson()).compareTo(jsonEncode(b.toJson())) > 0;
  }

  /// Sign-out (S10-6): the account's phrases leave the phone.
  Future<void> clearAll() async {
    _all.clear();
    _changes.add(phrases);
    await storeOrKeepGoing(() => _db.delete(_db.phrases).go());
  }

  /// The same shape as before step 10 (Privacy › Export keeps its format;
  /// nothing stored, nothing exported).
  @override
  Map<String, Object> export() => {
    if (_all.isNotEmpty) ...{
      kVersion: schemaVersion,
      kPhrases: jsonEncode([for (final p in _all) p.toJson()]),
    },
  };

  Future<void> dispose() => _changes.close();
}
