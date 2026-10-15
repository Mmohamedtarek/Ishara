/// A small deterministic random generator (mulberry32) with 32-bit math
/// written out, so a seed gives the same numbers on every platform and
/// Dart version (`dart:math` `Random(seed)` promises neither).
class SeededRandom {
  new(int seed) : _state = seed & _mask;

  static const _mask = 0xFFFFFFFF;
  int _state;

  /// A seed from text (FNV-1a, 32 bit), e.g. `daily:2026-10-14`.
  static int seedOf(String text) {
    var h = 0x811C9DC5;
    for (final unit in text.codeUnits) {
      h = _imul(h ^ unit, 0x01000193);
    }
    return h;
  }

  // Math.imul: the low 32 bits of a × b, without 64-bit overflow.
  static int _imul(int a, int b) {
    final al = a & 0xFFFF;
    final ah = (a >> 16) & 0xFFFF;
    final bl = b & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF;
    return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & _mask;
  }

  /// The next 32-bit value.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask;
    var t = _imul(_state ^ (_state >> 15), _state | 1);
    t = (t ^ (t + _imul(t ^ (t >> 7), t | 61))) & _mask;
    return (t ^ (t >> 14)) & _mask;
  }

  /// 0 ≤ n < [max].
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max');
    return nextUint32() * max >> 32;
  }

  /// Fisher–Yates, in place.
  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final x = items[i];
      items[i] = items[j];
      items[j] = x;
    }
  }
}
