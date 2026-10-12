import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_events.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/logging/log.dart';

/// How a sentence ended.
enum SequenceOutcome {
  /// Every segment was shown.
  completed,

  /// The avatar ended a sign early (it was paused or its page reloaded):
  /// nobody saw the rest, so the sentence stops there.
  interrupted,

  /// [SignSequencer.cancel] or a newer sentence.
  cancelled,
}

/// Plays a heard sentence on the avatar, one [SignSegment] after the other
/// (sign rule 7): a segment with a sign plays it, a segment without one
/// keeps the ready pose ([AvatarController.noSign]) while the caption shows
/// the words. Each segment waits for its `signEnded`, at most its length
/// plus [margin], so a lost event never blocks the sentence.
///
/// When the avatar isn't on screen and ready (loading, failed, or no
/// WebView), nothing is sent to it (a queued sign would play later, out of
/// step with the caption); each segment's caption then lasts the time the
/// avatar would have taken.
class SignSequencer {
  new(this._avatar, {this.margin = const Duration(milliseconds: 1500)}) {
    _sub = _avatar.events.listen(_onEvent);
  }

  final AvatarController _avatar;

  /// The avatar this sequencer drives.
  AvatarController get avatar => _avatar;

  /// Extra wait past a sign's length before giving up on its `signEnded`
  /// (Q10).
  final Duration margin;

  static final _log = Log('sequencer');

  late final StreamSubscription<AvatarEvent> _sub;
  int _generation = 0;
  int? _waitingId;
  Completer<bool>? _ended;
  Timer? _timer;

  /// The index of the segment shown now, or null between sentences.
  final ValueNotifier<int?> current = ValueNotifier(null);

  /// The engine's "no sign" slot (`engine.js` noSign: max(360, 520 / speed)
  /// ms).
  static Duration noSignDuration(double speed) => Duration(
    milliseconds: (520 / AvatarLibrary.clampSpeed(speed))
        .clamp(360, double.infinity)
        .round(),
  );

  /// Plays [segments] in order at [speed]. A newer [play] or [cancel] ends
  /// this one ([SequenceOutcome.cancelled]).
  Future<SequenceOutcome> play(
    List<SignSegment> segments, {
    double speed = 1,
  }) async {
    final gen = _interrupt();
    try {
      for (var i = 0; i < segments.length; i++) {
        if (gen != _generation) return SequenceOutcome.cancelled;
        current.value = i;
        final label = segments[i].label;
        final length = label == null
            ? noSignDuration(speed)
            : _avatar.library.duration(label, speed: speed);
        final shown = _avatar.status.value == AvatarStatus.ready
            ? await _playOnAvatar(label, speed, length + margin)
            : await _wait(length);
        if (gen != _generation) return SequenceOutcome.cancelled;
        if (!shown) return SequenceOutcome.interrupted;
      }
      return SequenceOutcome.completed;
    } finally {
      if (gen == _generation) current.value = null;
    }
  }

  /// Stops the sentence and the avatar's current sign.
  void cancel() {
    final playing = _waitingId != null;
    _interrupt();
    current.value = null;
    if (playing) _avatar.stop();
  }

  int _interrupt() {
    _timer?.cancel();
    _waitingId = null;
    final ended = _ended;
    _ended = null;
    if (ended != null && !ended.isCompleted) ended.complete(true);
    return ++_generation;
  }

  /// true when the sign ended normally (or its event never came).
  Future<bool> _playOnAvatar(String? label, double speed, Duration timeout) {
    final ended = _ended = Completer<bool>();
    final id = label == null
        ? _avatar.noSign(speed: speed)
        : _avatar.play(label, speed: speed);
    _waitingId = id;
    _timer = Timer(timeout, () {
      if (ended.isCompleted) return;
      _log.warn('sign_timeout', {'label': label, 'ms': timeout.inMilliseconds});
      _waitingId = null;
      _avatar.stop();
      ended.complete(true);
    });
    return ended.future;
  }

  Future<bool> _wait(Duration d) {
    final ended = _ended = Completer<bool>();
    _timer = Timer(d, () {
      if (!ended.isCompleted) ended.complete(true);
    });
    return ended.future;
  }

  void _onEvent(AvatarEvent e) {
    if (e case SignEnded(:final id, :final interrupted)
        when id != null && id == _waitingId) {
      _timer?.cancel();
      _waitingId = null;
      final ended = _ended;
      if (ended != null && !ended.isCompleted) ended.complete(!interrupted);
    }
  }

  Future<void> dispose() async {
    _interrupt();
    await _sub.cancel();
    current.dispose();
  }
}
