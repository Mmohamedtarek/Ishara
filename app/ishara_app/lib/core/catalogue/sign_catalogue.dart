import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ishara_app/core/catalogue/word_normalizer.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';

part 'sign_catalogue.freezed.dart';

/// The spoken language (voice and speech-to-text), chosen separately from
/// the sign language.
enum SpokenLanguage { en, ar }

/// One sign's words in one spoken language.
@freezed
abstract class SignWords with _$SignWords {
  const factory({
    /// Display text (Learn tiles, captions).
    required String word,

    /// Text-to-speech text.
    required String spoken,

    /// What speech-to-text may produce for this sign (single words or
    /// phrases), matched exactly after [WordNormalizer.normalize].
    required List<String> variants,
  }) = _SignWords;
}

/// One entry of `signs.json`.
@freezed
abstract class CatalogueSign with _$CatalogueSign {
  const factory({
    required String label,
    required String category,

    /// The glove model recognizes it (it is in `labels.txt`).
    required bool glove,

    /// The avatar can perform it.
    required bool avatar,

    /// Its form was checked against an ASL reference.
    required bool verified,

    /// The Learn tile icon (a prototype icon name).
    required String icon,
    required Map<SpokenLanguage, SignWords> words,
    required String description,

    /// Fields whose text is still a draft (not approved by the user).
    @Default(<String>{}) Set<String> draft,
  }) = _CatalogueSign;
  const new _();

  SignWords wordsIn(SpokenLanguage l) => words[l]!;

  /// Whether [variant] of [l] is still a draft: `<lang>.variants` marks the
  /// whole list, `<lang>.variants:<word>` one variant.
  bool isDraftVariant(SpokenLanguage l, String variant) =>
      draft.contains('${l.name}.variants') ||
      draft.contains('${l.name}.variants:$variant');
}

/// One Learn module (Q-L1): its signs, in order. A watch-only module has
/// pick-the-meaning steps only.
@immutable
class CatalogueModule {
  const new({required this.id, required this.signs, this.watchOnly = false});

  final String id;
  final List<String> signs;
  final bool watchOnly;
}

/// The sign catalogue of one sign language: the only word list in the app.
/// Learn, Talk, the avatar mapping and speech all read from it.
class SignCatalogue {
  new _(
    this.language,
    this.signs,
    this._phrases,
    this.maxPhraseWords,
    this.modules,
  ) : _byLabel = {for (final s in signs) s.label: s};

  /// Parses and checks `signs.json` against the model's [labels]:
  /// * every sign label of the model has exactly one entry, with
  ///   `glove: true`; no entry claims `glove: true` without being a model
  ///   label; `rest` / `other` never appear;
  /// * every entry has words for every spoken language;
  /// * no normalized variant leads to two different signs;
  /// * `learn.modules`: unique ids, at least one sign each, only signs of
  ///   this catalogue, no sign in two modules.
  factory parse(String jsonText, {required Labels labels}) {
    final Object? root;
    try {
      root = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw ParseFailure(
        'signs.json is not JSON',
        source: 'signs.json',
        cause: e,
      );
    }
    if (root is! Map<String, Object?>) {
      throw const ParseFailure(
        'signs.json is not an object',
        source: 'signs.json',
      );
    }
    final language = switch (root['language']) {
      final String v => SignLanguage.tryParse(v),
      _ => null,
    };
    if (language == null) {
      throw const ParseFailure(
        'signs.json: unknown "language"',
        source: 'signs.json',
      );
    }
    final raw = root['signs'];
    if (raw is! List<Object?>) {
      throw const ParseFailure(
        'signs.json: "signs" must be a list',
        source: 'signs.json',
      );
    }
    final signs = [for (final (i, s) in raw.indexed) _parseSign(s, i)];

    final seen = <String>{};
    for (final s in signs) {
      if (!seen.add(s.label)) {
        throw ParseFailure(
          'signs.json repeats "${s.label}"',
          source: 'signs.json',
        );
      }
      if (!labels.isWord(s.label)) {
        throw ParseFailure('"${s.label}" is not a sign', source: 'signs.json');
      }
      final inModel = labels.indexOf(s.label) != null;
      if (s.glove != inModel) {
        throw ParseFailure(
          '"${s.label}": glove is ${s.glove} but the model '
          '${inModel ? 'has' : 'lacks'} it',
          source: 'signs.json',
        );
      }
    }
    for (final l in labels.signs) {
      if (!seen.contains(l)) {
        throw ParseFailure(
          'model label "$l" has no entry',
          source: 'signs.json',
        );
      }
    }

    final phrases = <SpokenLanguage, Map<String, String>>{};
    var maxWords = 1;
    for (final lang in SpokenLanguage.values) {
      final map = phrases[lang] = {};
      for (final s in signs) {
        for (final v in s.wordsIn(lang).variants) {
          // Unapproved mappings never reach speech → sign ("ask, don't
          // guess"): skip variants still marked as drafts.
          if (s.isDraftVariant(lang, v)) continue;
          final key = WordNormalizer.normalize(v);
          if (key.isEmpty) {
            throw ParseFailure(
              '"${s.label}": empty variant',
              source: 'signs.json',
            );
          }
          final other = map[key];
          if (other != null && other != s.label) {
            throw ParseFailure(
              '"$v" (${lang.name}) leads to both "$other" and "${s.label}"',
              source: 'signs.json',
            );
          }
          map[key] = s.label;
          final n = key.split(' ').length;
          if (n > maxWords) maxWords = n;
        }
      }
    }
    return SignCatalogue._(
      language,
      List.unmodifiable(signs),
      phrases,
      maxWords,
      _parseModules(root['learn'], seen),
    );
  }

  static List<CatalogueModule> _parseModules(
    Object? learn,
    Set<String> labels,
  ) {
    Never fail(String why) =>
        throw ParseFailure('signs.json: learn.$why', source: 'signs.json');
    if (learn is! Map<String, Object?>) fail('learn must be an object');
    final raw = learn['modules'];
    if (raw is! List<Object?> || raw.isEmpty) fail('modules must be a list');
    final ids = <String>{};
    final used = <String>{};
    final modules = <CatalogueModule>[];
    for (final (i, m) in raw.indexed) {
      if (m is! Map<String, Object?>) fail('modules[$i] is not an object');
      final id = m['id'];
      if (id is! String || id.trim().isEmpty) fail('modules[$i]: no id');
      if (!ids.add(id)) fail('module "$id" repeats');
      final signs = m['signs'];
      if (signs is! List<Object?> ||
          signs.isEmpty ||
          signs.any((s) => s is! String)) {
        fail('module "$id": signs must list labels');
      }
      for (final s in signs.cast<String>()) {
        if (!labels.contains(s)) fail('module "$id": no sign "$s"');
        if (!used.add(s)) fail('"$s" is in two modules');
      }
      final watchOnly = m['watchOnly'] ?? false;
      if (watchOnly is! bool) fail('module "$id": watchOnly is not a bool');
      modules.add(
        CatalogueModule(
          id: id,
          signs: List.unmodifiable(signs.cast<String>()),
          watchOnly: watchOnly,
        ),
      );
    }
    return List.unmodifiable(modules);
  }

  static CatalogueSign _parseSign(Object? s, int i) {
    if (s is! Map<String, Object?>) {
      throw ParseFailure('sign $i is not an object', source: 'signs.json');
    }
    String str(String k) => switch (s[k]) {
      final String v when v.trim().isNotEmpty => v,
      _ => throw ParseFailure(
        'sign $i: "$k" must be text',
        source: 'signs.json',
      ),
    };
    bool flag(String k) => switch (s[k]) {
      final bool v => v,
      _ => throw ParseFailure(
        'sign $i: "$k" must be true/false',
        source: 'signs.json',
      ),
    };
    SignWords words(SpokenLanguage lang) {
      final w = s[lang.name];
      if (w is! Map<String, Object?>) {
        throw ParseFailure(
          'sign $i: no "${lang.name}" words',
          source: 'signs.json',
        );
      }
      String wstr(String k) => switch (w[k]) {
        final String v when v.trim().isNotEmpty => v,
        _ => throw ParseFailure(
          'sign $i: ${lang.name}.$k must be text',
          source: 'signs.json',
        ),
      };
      final variants = w['variants'];
      if (variants is! List<Object?> ||
          variants.isEmpty ||
          variants.any((v) => v is! String)) {
        throw ParseFailure(
          'sign $i: ${lang.name}.variants must list words',
          source: 'signs.json',
        );
      }
      return SignWords(
        word: wstr('word'),
        spoken: wstr('spoken'),
        variants: List.unmodifiable(variants.cast<String>()),
      );
    }

    final draft = s['draft'];
    return CatalogueSign(
      label: str('label'),
      category: str('category'),
      glove: flag('glove'),
      avatar: flag('avatar'),
      verified: flag('verified'),
      icon: str('icon'),
      words: {for (final l in SpokenLanguage.values) l: words(l)},
      description: str('description'),
      draft: draft is List<Object?>
          ? draft.whereType<String>().toSet()
          : const {},
    );
  }

  final SignLanguage language;
  final List<CatalogueSign> signs;
  final Map<String, CatalogueSign> _byLabel;
  final Map<SpokenLanguage, Map<String, String>> _phrases;

  /// Longest variant, in words.
  final int maxPhraseWords;

  /// The Learn modules, in order (Q-L1).
  final List<CatalogueModule> modules;

  CatalogueSign? byLabel(String label) => _byLabel[label];

  /// Signs the glove recognizes: the only ones a Learn practice step may
  /// ask for (sign rule 3).
  List<CatalogueSign> get gloveSigns => [
    for (final s in signs)
      if (s.glove) s,
  ];

  /// Signs the avatar can perform.
  List<CatalogueSign> get avatarSigns => [
    for (final s in signs)
      if (s.avatar) s,
  ];

  /// The sign for a normalized word or phrase, if any.
  String? labelFor(String normalized, SpokenLanguage lang) =>
      _phrases[lang]![normalized];

  /// Every normalized variant of [lang] and its sign.
  Map<String, String> phrases(SpokenLanguage lang) =>
      Map.unmodifiable(_phrases[lang]!);
}
