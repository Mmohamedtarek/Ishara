import 'dart:async';
import 'dart:typed_data';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:meta/meta.dart';

/// A Decider event for the UI (AI-SPEC §5, §7).
@immutable
class RecognitionEvent {
  const new({
    required this.kind,
    required this.label,
    required this.step,
    required this.probability,
  });

  final DeciderEventKind kind;

  /// Model label (from `labels.txt`); the catalogue gives its words.
  final String label;

  /// 0-based model run since the last reset; -1 for a cancel caused by a
  /// reset (BLE gap, reconnect, new calibration, streaming stopped).
  final int step;

  /// Smoothed probability of [label] at that step (Learn match %, Q-L4);
  /// null for a reset cancel (no model run).
  final double? probability;

  /// `word` and `confirm` are spoken; `tentative` and `cancel` never are.
  bool get speaks =>
      kind == DeciderEventKind.word || kind == DeciderEventKind.confirm;
}

/// One model run, for screens that need every step (Learn practice).
@immutable
class RecognitionTick {
  const new({required this.step, required this.smoothed});

  final int step;

  /// Smoothed probabilities in label order.
  final Float64List smoothed;
}

/// Glove → recognizer → events. Knows nothing about which glove source is
/// active. Resets on (re)connect and on every new `#CAL` (AI-SPEC §2, §5).
class RecognitionService {
  new({required this._source, required this._engine, required this.labels}) {
    _subs
      ..add(_source.statusChanges.listen(_onStatus))
      ..add(_source.events.listen(_onEvent))
      ..add(_source.samples.listen(_engine.feed))
      ..add(_engine.outputs.listen(_onOutput, onError: _onEngineError));
    // The engine may have served another glove before: use this glove's
    // calibration or none at all.
    final cal = _source.status.calibration;
    if (cal != null) {
      _engine.setCalibration(cal);
    } else {
      _engine.clearCalibration();
    }
    _wasReady = _source.status.phase == GlovePhase.ready;
  }

  final GloveSource _source;
  final RecognizerEngine _engine;
  final Labels labels;
  final _log = Log('recognition');
  final List<StreamSubscription<Object?>> _subs = [];
  final _events = StreamController<RecognitionEvent>.broadcast(sync: true);
  final _ticks = StreamController<RecognitionTick>.broadcast(sync: true);
  final _errors = StreamController<Failure>.broadcast(sync: true);
  bool _wasReady = false;
  int _slowRuns = 0;

  /// Decider events, in order.
  Stream<RecognitionEvent> get events => _events.stream;

  /// Every model run.
  Stream<RecognitionTick> get ticks => _ticks.stream;

  /// Recognizer failures (the UI shows that recognition stopped).
  Stream<Failure> get errors => _errors.stream;

  /// Batches whose model time exceeded the 20 ms budget.
  int get slowRuns => _slowRuns;

  void _onStatus(GloveStatus s) {
    final ready = s.phase == GlovePhase.ready;
    if (ready && !_wasReady) {
      // A new connection: everything starts again (AI-SPEC §5), with this
      // glove's calibration, or none (`#CAL NONE`: no recognition until the
      // user calibrates; another glove's numbers are never used).
      final cal = s.calibration;
      if (cal != null) {
        _engine.setCalibration(cal); // also resets
      } else {
        _engine.clearCalibration();
      }
    } else if (!ready && _wasReady) {
      // Streaming stopped (disconnect, link lost, MTU): a waiting tentative
      // word can never be confirmed now, so it is cancelled.
      _engine.reset();
    }
    _wasReady = ready;
  }

  void _onEvent(GloveEvent e) {
    if (e is CalibrationEvent) _engine.setCalibration(e.calibration);
  }

  void _onOutput(EngineOutput o) {
    final runs = o.results.fold(0, (n, r) => n + r.steps.length);
    if (runs > 0 && o.modelMicros > 20000 * runs) _slowRuns++;
    for (final r in o.results) {
      final cancel = r.resetCancel;
      if (cancel != null) {
        _events.add(
          RecognitionEvent(
            kind: cancel.kind,
            label: cancel.label,
            step: -1,
            probability: null,
          ),
        );
      }
      for (final s in r.steps) {
        _ticks.add(RecognitionTick(step: s.step, smoothed: s.smoothed));
        for (final e in s.events) {
          final i = labels.indexOf(e.label)!;
          _events.add(
            RecognitionEvent(
              kind: e.kind,
              label: e.label,
              step: s.step,
              probability: s.smoothed[i],
            ),
          );
        }
      }
    }
  }

  void _onEngineError(Object e, StackTrace st) {
    final f = e is Failure
        ? e
        : UnexpectedFailure('$e', cause: e, stackTrace: st);
    _log.failure('engine_error', f);
    if (!_errors.isClosed) _errors.add(f);
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _events.close();
    await _ticks.close();
    await _errors.close();
  }
}
