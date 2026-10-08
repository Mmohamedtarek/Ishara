import 'dart:async';
import 'dart:isolate';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/ensemble.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';
import 'package:meta/meta.dart';

/// Output of the engine for one batch of samples (or one reset).
@immutable
class EngineOutput {
  const new(this.results, {required this.modelMicros});

  /// One result per sample (or reset) that produced a model run or a cancel.
  final List<FeedResult> results;

  /// Time spent in the models for this batch (performance budget: < 20 ms
  /// per run on a phone).
  final int modelMicros;
}

/// The recognizer engine stopped or hit an error.
final class RecognizerStoppedFailure extends Failure {
  const new(super.message, {super.cause});

  @override
  String get kind => 'recognizer_stopped';
}

/// Runs the [Recognizer]. The app uses [IsolateRecognizer] so recognition
/// never blocks the UI or the avatar; tests can use [InProcessRecognizer].
///
/// Resets (new calibration, cleared calibration, reset) emit the `cancel` of
/// a tentative word that was waiting, so the UI never keeps a stale one.
abstract interface class RecognizerEngine {
  Stream<EngineOutput> get outputs;

  /// Replaces the calibration and resets everything (AI-SPEC §2).
  void setCalibration(GloveCalibration cal);

  /// No calibration (a glove with `#CAL NONE`, or a different glove):
  /// samples are ignored until [setCalibration].
  void clearCalibration();

  /// Full reset (reconnect, link lost: AI-SPEC §5).
  void reset();

  /// Samples in arrival order. Ignored until a calibration is set.
  void feed(List<GloveSample> samples);

  Future<void> dispose();
}

/// Synchronous engine on the calling isolate.
class InProcessRecognizer implements RecognizerEngine {
  new(ModelBundle bundle) : _ensemble = bundle.buildEnsemble() {
    final sw = Stopwatch();
    _timer = sw;
    _recognizer = Recognizer(
      labels: bundle.labels,
      config: bundle.config,
      predict: (w) {
        sw.start();
        try {
          return _ensemble.predict(w);
        } finally {
          sw.stop();
        }
      },
    );
  }

  final Ensemble _ensemble;
  late final Recognizer _recognizer;
  late final Stopwatch _timer;
  final _out = StreamController<EngineOutput>.broadcast(sync: true);
  bool _closed = false;

  @override
  Stream<EngineOutput> get outputs => _out.stream;

  void _emitReset(FeedResult r) {
    if (!identical(r, FeedResult.empty) && !_out.isClosed) {
      _out.add(EngineOutput([r], modelMicros: 0));
    }
  }

  @override
  void setCalibration(GloveCalibration cal) =>
      _emitReset(_recognizer.setCalibration(cal));

  @override
  void clearCalibration() => _emitReset(_recognizer.clearCalibration());

  @override
  void reset() => _emitReset(_recognizer.reset());

  @override
  void feed(List<GloveSample> samples) {
    if (_recognizer.calibration == null || _closed) return;
    _timer.reset();
    final results = <FeedResult>[];
    for (final s in samples) {
      final r = _recognizer.feed(s.seq, s.values);
      if (!identical(r, FeedResult.empty)) results.add(r);
    }
    if (results.isNotEmpty && !_out.isClosed) {
      _out.add(EngineOutput(results, modelMicros: _timer.elapsedMicroseconds));
    }
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _ensemble.close();
    await _out.close();
  }
}

/// The engine in a long-lived background isolate that owns the
/// interpreters. Messages are plain sendable objects.
class IsolateRecognizer implements RecognizerEngine {
  new _(this._isolate, this._toWorker, this._inbox);

  /// How long [dispose] waits for the worker to free its interpreters.
  static const closeTimeout = Duration(seconds: 2);

  /// Spawns the worker and loads the models in it. Throws the worker's
  /// [Failure] if the models can't be loaded, or [RecognizerStoppedFailure]
  /// if the worker dies or fails before it is ready (never hangs).
  static Future<IsolateRecognizer> spawn(ModelBundle bundle) async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      (inbox.sendPort, bundle),
      debugName: 'ishara-recognizer',
      paused: true,
      errorsAreFatal: false,
    );
    // Uncaught errors and the exit come to the same port as messages.
    isolate
      ..addErrorListener(inbox.sendPort)
      ..addOnExitListener(inbox.sendPort, response: _exited)
      ..resume(isolate.pauseCapability!);
    final events = inbox.asBroadcastStream();
    final first = await events.first;
    if (first is! SendPort) {
      isolate.kill();
      inbox.close();
      throw switch (first) {
        final Failure f => f,
        _exited => const RecognizerStoppedFailure(
          'worker exited while starting',
        ),
        _ => RecognizerStoppedFailure('worker failed while starting: $first'),
      };
    }
    final engine = IsolateRecognizer._(isolate, first, inbox);
    engine._sub = events.listen(engine._onMessage);
    return engine;
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _inbox;
  late final StreamSubscription<Object?> _sub;
  final _out = StreamController<EngineOutput>.broadcast();
  final _closedAck = Completer<void>();
  bool _alive = true;

  void _onMessage(Object? m) {
    switch (m) {
      case final EngineOutput o:
        if (!_out.isClosed) _out.add(o);
      case final Failure f:
        if (!_out.isClosed) _out.addError(f);
      case _Control.closed:
        if (!_closedAck.isCompleted) _closedAck.complete();
      case _exited:
        _alive = false;
        if (!_closedAck.isCompleted) _closedAck.complete();
        if (!_out.isClosed) {
          _out.addError(const RecognizerStoppedFailure('worker exited'));
        }
      case [final Object? error, final Object? stack]:
        // An uncaught error in the worker; it keeps running
        // (errorsAreFatal: false).
        if (!_out.isClosed) {
          _out.addError(
            RecognizerStoppedFailure('worker error: $error', cause: stack),
          );
        }
    }
  }

  @override
  Stream<EngineOutput> get outputs => _out.stream;

  void _send(Object message) {
    if (_alive) _toWorker.send(message);
  }

  @override
  void setCalibration(GloveCalibration cal) => _send(cal);

  @override
  void clearCalibration() => _send(_Control.clearCalibration);

  @override
  void reset() => _send(_Control.reset);

  @override
  void feed(List<GloveSample> samples) => _send(samples);

  @override
  Future<void> dispose() async {
    if (_alive) {
      _toWorker.send(_Control.close);
      // Let the worker free its native interpreters before it is killed.
      await _closedAck.future.timeout(closeTimeout, onTimeout: () {});
    }
    _alive = false;
    await _sub.cancel();
    _inbox.close();
    _isolate.kill(priority: Isolate.immediate);
    await _out.close();
  }
}

/// Control messages between the app and the worker.
enum _Control { reset, clearCalibration, close, closed }

/// The isolate's exit notice (must be a primitive value).
const _exited = 'ishara-recognizer-exited';

void _workerMain((SendPort, ModelBundle) args) {
  final (toMain, bundle) = args;
  final InProcessRecognizer engine;
  try {
    engine = InProcessRecognizer(bundle);
  } on Failure catch (f) {
    toMain.send(f);
    return;
  } on Object catch (e) {
    toMain.send(UnexpectedFailure('cannot start recognizer: $e'));
    return;
  }
  final inbox = ReceivePort();
  engine.outputs.listen(toMain.send);
  inbox.listen((m) async {
    // Every error is reported and the worker keeps serving: a dead worker
    // would silently stop recognition.
    try {
      switch (m) {
        case final GloveCalibration cal:
          engine.setCalibration(cal);
        case _Control.clearCalibration:
          engine.clearCalibration();
        case _Control.reset:
          engine.reset();
        case final List<GloveSample> samples:
          engine.feed(samples);
        case _Control.close:
          await engine.dispose();
          inbox.close();
          toMain.send(_Control.closed);
      }
    } on Failure catch (f) {
      toMain.send(f);
    } on Object catch (e) {
      toMain.send(UnexpectedFailure('recognizer: $e'));
    }
  });
  toMain.send(inbox.sendPort);
}
