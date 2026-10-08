import 'dart:typed_data';

import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/normalizer.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:meta/meta.dart';

/// What one model run produced.
@immutable
class RecognitionStep {
  const new({
    required this.step,
    required this.sampleCount,
    required this.smoothed,
    required this.events,
  });

  /// 0-based model run index since the last reset (as in the test files).
  final int step;

  /// Samples counted since the last reset when the run happened.
  final int sampleCount;

  /// The Decider's smoothed probabilities (mean of the last `smooth` runs),
  /// in label order. Used for the Learn match % (Q-L4).
  final Float64List smoothed;

  /// Events of this run, in order.
  final List<DeciderEvent> events;
}

/// Everything one fed sample produced.
@immutable
class FeedResult {
  const new({this.steps = const [], this.resetCancel});

  static const empty = FeedResult();

  /// Model runs triggered by this sample (more than one if a gap was filled).
  final List<RecognitionStep> steps;

  /// `cancel` of a pending tentative word because the state was reset: a
  /// real BLE gap (AI-SPEC §4), a reconnect or a new calibration.
  final DeciderEvent? resetCancel;

  /// All events in order (gap cancel first).
  List<DeciderEvent> get events => [
    ?resetCancel,
    for (final s in steps) ...s.events,
  ];
}

/// The model part of the pipeline, injectable for tests.
typedef PredictFn = Float64List Function(Float32List window);

/// The full pipeline of AI-SPEC v3.2.1 for one stream of samples:
/// gap rule (§4) → normalize (§3) → 2 s window (§4) → model every 10 samples
/// (§4) → Decider (§5). Synchronous; the app runs it in an isolate.
class Recognizer {
  new({
    required this.labels,
    required this.config,
    required this._predict,
    GloveCalibration? calibration,
  }) {
    config.validateAgainst(labels);
    _decider = Decider(labels, config);
    if (calibration != null) setCalibration(calibration);
  }

  final Labels labels;
  final DeciderConfig config;
  final PredictFn _predict;

  Normalizer? _normalizer;
  GloveCalibration? _calibration;

  /// Ring buffer of the last [AiSpec.window] normalized samples.
  final Float32List _ring = Float32List(AiSpec.window * AiSpec.channels);
  int _filled = 0;
  int _head = 0; // index of the oldest sample when full
  int _count = 0;
  late Decider _decider;

  int? _expected;
  List<int>? _last;

  GloveCalibration? get calibration => _calibration;

  /// A new calibration replaces the old one and resets everything (§2, §5).
  /// Returns the `cancel` of a tentative word that was waiting, if any.
  FeedResult setCalibration(GloveCalibration cal) {
    _calibration = cal;
    _normalizer = Normalizer(cal);
    return reset();
  }

  /// Forgets the calibration (a glove with `#CAL NONE`, or another glove):
  /// samples are refused until a new `#CAL`, so another glove's numbers are
  /// never used. Returns the `cancel` of a waiting tentative word, if any.
  FeedResult clearCalibration() {
    _calibration = null;
    _normalizer = null;
    return reset();
  }

  /// Full reset (reconnect or new `#CAL`, AI-SPEC §5): window, counter,
  /// Decider and the BLE sequence; the next sample is accepted as is.
  /// A tentative word that was waiting is cancelled (returned), so the UI
  /// never keeps a faded word that can no longer be confirmed.
  FeedResult reset() {
    final pending = _decider.pending;
    _resetWindow();
    _expected = null;
    _last = null;
    return pending == null
        ? FeedResult.empty
        : FeedResult(
            resetCancel: DeciderEvent(DeciderEventKind.cancel, pending),
          );
  }

  void _resetWindow() {
    _filled = 0;
    _head = 0;
    _count = 0;
    _decider = Decider(labels, config);
  }

  /// Feeds one sample: [seq] (uint16, wraps 65535 → 0) and 11 raw values.
  FeedResult feed(int seq, List<int> raw) {
    if (_normalizer == null) {
      throw StateError('no calibration: recognition needs #CAL first');
    }
    if (raw.length != AiSpec.channels) {
      throw ArgumentError(
        'a sample has ${AiSpec.channels} values, got ${raw.length}',
      );
    }
    final steps = <RecognitionStep>[];
    DeciderEvent? resetCancel;
    final expected = _expected;
    if (expected != null) {
      final gap = (seq - expected) % 65536;
      if (gap >= 32768) return FeedResult.empty; // duplicate or older: drop
      if (gap >= 1 && gap <= AiSpec.maxFilledGap) {
        for (var i = 0; i < gap; i++) {
          _push(_last!, steps);
        }
      } else if (gap > AiSpec.maxFilledGap) {
        final pending = _decider.pending;
        if (pending != null) {
          resetCancel = DeciderEvent(DeciderEventKind.cancel, pending);
        }
        _resetWindow();
      }
    }
    final copy = List<int>.unmodifiable(raw);
    _push(copy, steps);
    _last = copy;
    _expected = (seq + 1) % 65536;
    if (steps.isEmpty && resetCancel == null) return FeedResult.empty;
    return FeedResult(steps: steps, resetCancel: resetCancel);
  }

  void _push(List<int> raw, List<RecognitionStep> steps) {
    final slot = _filled < AiSpec.window ? _filled : _head;
    _normalizer!.normalizeInto(raw, _ring, slot * AiSpec.channels);
    if (_filled < AiSpec.window) {
      _filled++;
    } else {
      _head = (_head + 1) % AiSpec.window;
    }
    _count++;
    if (_filled == AiSpec.window && _count % AiSpec.step == 0) {
      final events = _decider.step(_predict(_window()));
      steps.add(
        RecognitionStep(
          step: _decider.stepNo - 1,
          sampleCount: _count,
          smoothed: _decider.smoothed!,
          events: List.unmodifiable(events),
        ),
      );
    }
  }

  /// The window in time order (oldest first), as the model expects.
  Float32List _window() {
    const n = AiSpec.window * AiSpec.channels;
    if (_head == 0) return Float32List.fromList(_ring);
    final out = Float32List(n);
    final split = _head * AiSpec.channels;
    out
      ..setRange(0, n - split, _ring, split)
      ..setRange(n - split, n, _ring);
    return out;
  }
}
