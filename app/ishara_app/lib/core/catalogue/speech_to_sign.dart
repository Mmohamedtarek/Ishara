import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/catalogue/word_normalizer.dart';
import 'package:meta/meta.dart';

/// A piece of a heard sentence: one or more original words and the sign
/// they map to, or null when there is no sign (the avatar stays in the
/// ready pose and the caption shows the words).
@immutable
class SignSegment {
  const new(this.words, this.label);

  /// The words as heard (for the caption).
  final List<String> words;

  /// The sign, or null.
  final String? label;

  String get text => words.join(' ');

  @override
  bool operator ==(Object other) =>
      other is SignSegment &&
      other.label == label &&
      other.words.length == words.length &&
      other.text == text;

  @override
  int get hashCode => Object.hash(text, label);

  @override
  String toString() => '"$text" → ${label ?? '-'}';
}

/// Speech → signs (sign rule 7): exact matches on normalized whole words,
/// longest phrase first ("thank you" is one sign, not two words). Never
/// fuzzy: a word that isn't in the catalogue gets no sign, and neither does
/// a sign the avatar can't perform (the avatar keeps its ready pose and the
/// caption shows the words).
abstract final class SpeechToSign {
  /// Splits after punctuation that is followed by a letter or digit, so
  /// "ab,cd" gives "ab," + "cd" (the punctuation stays with
  /// the word before it, for the caption). Never between digits: "1.5",
  /// "3:30" and "1,000" stay one word (no sign), so they can't become the
  /// signs for 1 and 5.
  static final _glued = RegExp(
    // punctuation, then a letter
    r"(?<=[^\p{L}\p{N}\s'’ʼ`])(?=\p{L})"
    // punctuation not right after a digit, then a digit
    r"|(?<!\p{N}[^\p{L}\p{N}\s'’ʼ`]*)(?<=[^\p{L}\p{N}\s'’ʼ`])(?=\p{N})",
    unicode: true,
  );

  /// A word ending with this ends a phrase: "Thank. You" is not "thank you".
  static final _sentenceEnd = RegExp(r'[.!?؟,،;؛:…]$');

  static List<SignSegment> match(
    String sentence,
    SignCatalogue catalogue,
    SpokenLanguage lang,
  ) {
    final words = [
      for (final w in sentence.split(RegExp(r'\s+')))
        if (w.isNotEmpty) ...w.split(_glued).where((p) => p.isNotEmpty),
    ];
    final norm = [for (final w in words) WordNormalizer.normalize(w)];
    final out = <SignSegment>[];
    var i = 0;
    while (i < words.length) {
      if (norm[i].isEmpty) {
        // Only punctuation: keep it in the caption, no sign.
        out.add(SignSegment([words[i]], null));
        i++;
        continue;
      }
      String? label;
      var took = 1;
      for (var n = catalogue.maxPhraseWords; n >= 1; n--) {
        if (i + n > words.length) continue;
        if (!_isPhrase(words, norm, i, n)) continue;
        final key = norm.sublist(i, i + n).join(' ');
        final hit = catalogue.labelFor(key, lang);
        if (hit != null) {
          label = catalogue.byLabel(hit)!.avatar ? hit : null;
          took = n;
          break;
        }
      }
      out.add(SignSegment(words.sublist(i, i + took), label));
      i += took;
    }
    return out;
  }

  /// For the debug speech log: each segment's words, their normalized form,
  /// the sign, and why there is none (`punctuation`, `noAvatar`: the
  /// catalogue has the word but the avatar can't sign it, `notInCatalogue`).
  static List<Map<String, Object?>> explain(
    List<SignSegment> segments,
    SignCatalogue catalogue,
    SpokenLanguage lang,
  ) => [
    for (final s in segments)
      {
        'words': s.text,
        'normalized': WordNormalizer.normalize(s.text),
        'sign': s.label,
        if (s.label == null)
          'why': switch (WordNormalizer.normalize(s.text)) {
            '' => 'punctuation',
            final n when catalogue.labelFor(n, lang) != null => 'noAvatar',
            _ => 'notInCatalogue',
          },
      },
  ];

  /// Words i..i+n-1 can form one phrase: none is punctuation only, and no
  /// word before the last ends a sentence or clause.
  static bool _isPhrase(List<String> words, List<String> norm, int i, int n) {
    for (var k = i; k < i + n; k++) {
      if (norm[k].isEmpty) return false;
      if (k < i + n - 1 && _sentenceEnd.hasMatch(words[k])) return false;
    }
    return true;
  }
}
