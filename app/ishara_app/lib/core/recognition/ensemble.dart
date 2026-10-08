import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';

/// One classifier: a normalized window (100 x 11 float32, oldest first) in,
/// one probability per label out (AI-SPEC §4).
abstract interface class ProbabilityModel {
  Float32List predict(Float32List window);
  void close();
}

/// A `.tflite` model run with the classic LiteRT interpreter on the CPU
/// (no GPU / NNAPI delegate), like the reference `tf.lite.Interpreter`.
class TfliteModel implements ProbabilityModel {
  new _(this._interpreter, this.name, this.outputs);

  /// Loads [bytes] and checks the tensor shapes against AI-SPEC §4.
  factory fromBytes(
    Uint8List bytes, {
    required String name,
    required int labels,
  }) {
    final Interpreter it;
    try {
      it = Interpreter.fromBuffer(
        bytes,
        options: InterpreterOptions()..threads = 1,
      );
    } on Object catch (e, st) {
      throw AssetFailure(
        'cannot load model',
        path: name,
        cause: e,
        stackTrace: st,
      );
    }
    final inShape = it.getInputTensors().single.shape;
    final outShape = it.getOutputTensors().single.shape;
    const want = [1, AiSpec.window, AiSpec.channels];
    if (inShape.length != 3 ||
        !_same(inShape, want) ||
        outShape.last != labels) {
      it.close();
      throw AssetFailure(
        'model shape $inShape -> $outShape, expected $want -> [1, $labels]',
        path: name,
      );
    }
    return TfliteModel._(it, name, labels);
  }

  final Interpreter _interpreter;
  final String name;
  final int outputs;

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Float32List predict(Float32List window) {
    final input = _interpreter.getInputTensors().single
      ..data = window.buffer.asUint8List(
        window.offsetInBytes,
        window.lengthInBytes,
      );
    assert(input.numElements() == window.length, 'window size');
    _interpreter.invoke();
    final out = _interpreter.getOutputTensors().single.data;
    return Float32List.fromList(
      out.buffer.asFloat32List(out.offsetInBytes, outputs),
    );
  }

  @override
  void close() => _interpreter.close();
}

/// Runs every model on the same window and averages their outputs
/// element-wise (AI-SPEC §4).
///
/// The average is computed in float32, in model order, like the reference
/// `np.mean(outs, axis=0)` on float32 outputs; the result is widened to
/// float64 for the Decider (`.astype(float)`).
class Ensemble {
  new(this.models) {
    if (models.isEmpty) throw ArgumentError('no models');
  }

  final List<ProbabilityModel> models;

  /// Each model's output, then their average.
  ({List<Float32List> each, Float64List average}) predictAll(
    Float32List window,
  ) {
    final each = [for (final m in models) m.predict(window)];
    return (each: each, average: average(each));
  }

  Float64List predict(Float32List window) => predictAll(window).average;

  /// float32 mean: sum in order with float32 rounding after each add, then
  /// divide in float32.
  static Float64List average(List<Float32List> outs) {
    final n = outs.first.length;
    final acc = Float32List(n);
    for (final o in outs) {
      if (o.length != n) throw ArgumentError('models disagree on output size');
      for (var i = 0; i < n; i++) {
        acc[i] += o[i]; // stored back as float32 = rounded each step
      }
    }
    final out = Float64List(n);
    final tmp = Float32List(1);
    for (var i = 0; i < n; i++) {
      tmp[0] = acc[i] / outs.length;
      out[i] = tmp[0];
    }
    return out;
  }

  void close() {
    for (final m in models) {
      m.close();
    }
  }
}
