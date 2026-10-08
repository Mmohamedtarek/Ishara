/// Normalizes words for speech → sign matching (prompt, sign rule 7).
///
/// Exact matching happens on the result; nothing here is fuzzy. It folds:
/// * case (`Hello` → `hello`);
/// * Arabic diacritics and tatweel (`شكراً` → `شكرا`);
/// * hamza / alef forms (`أ إ آ ٱ` → `ا`, `ؤ` → `و`, `ئ` → `ي`);
/// * `ة` → `ه` and `ى` → `ي`;
/// * apostrophes are removed (`i'm` → `im`, so it can't become `i` + `m`);
/// * any other punctuation separates words; spaces are collapsed.
///
/// Characters are written as code points: combining marks are invisible in
/// source and easy to get wrong in review.
abstract final class WordNormalizer {
  /// Dropped: Arabic marks U+0610-061A, harakat and tanween U+064B-065F,
  /// superscript alef U+0670, Quranic marks U+06D6-06ED, tatweel U+0640.
  static const _dropRanges = [
    (0x0610, 0x061A),
    (0x064B, 0x065F),
    (0x0670, 0x0670),
    (0x06D6, 0x06ED),
    (0x0640, 0x0640),
  ];

  /// Removed without splitting words: ' ’ ʼ `.
  static const _apostrophes = {0x0027, 0x2019, 0x02BC, 0x0060};

  static const _fold = {
    0x0623: 0x0627, // أ → ا
    0x0625: 0x0627, // إ → ا
    0x0622: 0x0627, // آ → ا
    0x0671: 0x0627, // ٱ → ا
    0x0624: 0x0648, // ؤ → و
    0x0626: 0x064A, // ئ → ي
    0x0629: 0x0647, // ة → ه
    0x0649: 0x064A, // ى → ي
  };

  static final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static bool _dropped(int r) {
    for (final (a, b) in _dropRanges) {
      if (r >= a && r <= b) return true;
    }
    return _apostrophes.contains(r);
  }

  /// The normalized form of [text] (words separated by single spaces).
  static String normalize(String text) {
    final out = <int>[];
    for (final r in text.toLowerCase().runes) {
      if (_dropped(r)) continue;
      out.add(_fold[r] ?? r);
    }
    return String.fromCharCodes(out).replaceAll(_separators, ' ').trim();
  }
}
