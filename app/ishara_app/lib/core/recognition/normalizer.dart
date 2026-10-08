import 'dart:typed_data';

import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';

/// AI-SPEC §3. Same arithmetic as the reference `common.normalize`: computed
/// in float64, then stored as float32. No clipping, no rounding.
class Normalizer {
  new(GloveCalibration cal)
    : _open = cal.open,
      _bias = cal.gyroBiasRaw,
      _span = [
        for (var i = 0; i < 5; i++) _safeSpan(cal.fist[i] - cal.open[i]),
      ];

  /// `if |span| < 1: span = 1` (AI-SPEC §3).
  static double _safeSpan(double span) => span.abs() < 1 ? 1 : span;

  static const accLsbPerG = 8192.0;
  static const gyroLsbPerDps = 65.5;
  static const gyroFullScaleDps = 250.0;

  final List<double> _open;
  final List<double> _span;
  final List<double> _bias;

  /// Writes the normalized [raw] sample (11 values) into [out] at [offset].
  void normalizeInto(List<int> raw, Float32List out, int offset) {
    for (var i = 0; i < 5; i++) {
      out[offset + i] = (raw[i] - _open[i]) / _span[i];
    }
    for (var i = 5; i < 8; i++) {
      out[offset + i] = raw[i] / accLsbPerG;
    }
    for (var i = 8; i < AiSpec.channels; i++) {
      out[offset + i] =
          (raw[i] - _bias[i - 8]) / gyroLsbPerDps / gyroFullScaleDps;
    }
  }

  /// One normalized sample.
  Float32List normalize(List<int> raw) {
    final out = Float32List(AiSpec.channels);
    normalizeInto(raw, out, 0);
    return out;
  }
}
