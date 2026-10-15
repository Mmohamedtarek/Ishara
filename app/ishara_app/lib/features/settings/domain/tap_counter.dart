/// The hidden developer switch (S9-3): every [needed]-th consecutive tap
/// on About's version fires; the count starts again after that (and when
/// About is opened again: a new counter).
class TapCounter {
  new({this.needed = 7});

  final int needed;
  int _taps = 0;

  /// Taps so far toward the next switch.
  int get taps => _taps;

  /// One tap; true when it completes [needed] taps.
  bool tap() {
    _taps++;
    if (_taps < needed) return false;
    _taps = 0;
    return true;
  }
}
