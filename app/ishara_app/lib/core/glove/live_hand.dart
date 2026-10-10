import 'dart:math' as math;

import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/recognition/calibration.dart';

/// What the calibration screen (and later Learn's practice) shows live from
/// the raw samples: finger bend, "hold still" and wrist rotation.
///
/// Display only: recognition never uses these numbers (it normalizes with
/// the glove's `#CAL`, AI-SPEC §3). Each rule mirrors the firmware, so the
/// screen agrees with what the glove will decide:
/// - still: every gyro axis's standard deviation over the last 2 s is at most
///   3 °/s (`CAL_STILL_GYRO_STD_DPS`; `MOVED` otherwise);
/// - roll: the firmware's complementary filter (`ROLL_FILTER_ALPHA` 0.98 on
///   the gyro X axis, accel roll `atan2(ay, az)`), relative to the neutral
///   roll of the OPEN step; TURN needs 30° of range (`RANGE` otherwise);
/// - a finger whose open and fist values differ by less than 300 counts has
///   no bar (`#FLEX WEAK`, BLE-CONTRACT §6).
class LiveHand {
  /// Samples in the stillness window (2 s at 50 Hz, the length of a step).
  static const stillWindow = 100;
  static const stillLimitDps = 3.0;
  static const minRollRangeDeg = 30.0;
  static const weakSpan = 300;
  static const _gyroLsbPerDps = 65.5;
  static const _samplePeriodS = .02;
  static const _rollAlpha = .98;

  final _gyro = <List<int>>[];
  double? _roll;

  /// The latest raw values (11 channels), null before the first sample.
  List<int>? get latest => _latest;
  List<int>? _latest;

  // Open / fist reference per finger and the gyro bias / neutral roll, from
  // the glove's calibration or captured on the phone during this run.
  List<double>? _open;
  List<double>? _fist;
  List<double> _bias = const [0, 0, 0];
  double _neutral = 0;

  /// Uses a stored calibration (`#CAL`) for the bars and the rotation.
  void useCalibration(GloveCalibration c) {
    _open = c.open;
    _fist = c.fist;
    _bias = c.gyroBiasRaw;
    _neutral = c.rollNeutral;
  }

  /// Forgets the open / fist references (a new calibration run).
  void resetReferences() {
    _open = null;
    _fist = null;
  }

  void add(GloveSample s) {
    final v = s.values;
    _latest = v;
    _gyro.add([v[8], v[9], v[10]]);
    if (_gyro.length > stillWindow) _gyro.removeAt(0);
    final acc = accelRollDeg(v[6].toDouble(), v[7].toDouble());
    final r = _roll;
    if (r == null) {
      _roll = acc;
    } else {
      final rate = (v[8] - _bias[0]) / _gyroLsbPerDps;
      final predicted = r + rate * _samplePeriodS;
      _roll = wrap(predicted + (1 - _rollAlpha) * wrap(acc - predicted));
    }
  }

  /// Firmware `accelRollDeg`.
  static double accelRollDeg(double ay, double az) =>
      math.atan2(ay, az) * 180 / math.pi;

  /// Into (-180, 180].
  static double wrap(double deg) {
    var d = deg;
    while (d > 180) {
      d -= 360;
    }
    while (d <= -180) {
      d += 360;
    }
    return d;
  }

  /// Every gyro axis steady (null until there are 2 samples).
  bool? get still {
    if (_gyro.length < 2) return null;
    for (var axis = 0; axis < 3; axis++) {
      var sum = 0.0;
      var sq = 0.0;
      for (final g in _gyro) {
        sum += g[axis];
        sq += g[axis] * g[axis];
      }
      final mean = sum / _gyro.length;
      final variance = math.max(0, sq / _gyro.length - mean * mean);
      if (math.sqrt(variance) / _gyroLsbPerDps > stillLimitDps) return false;
    }
    return true;
  }

  /// Wrist rotation from the neutral roll, in degrees (null before the
  /// first sample).
  double? get rotation {
    final r = _roll;
    return r == null ? null : wrap(r - _neutral);
  }

  /// Bend of each finger, 0 = open … 1 = fist (clamped for display), or null
  /// for a finger without a usable reference. Null when there is no
  /// reference at all.
  List<double?>? get fingers {
    final o = _open;
    final f = _fist;
    final v = _latest;
    if (o == null || f == null || v == null) return null;
    return [
      for (var i = 0; i < 5; i++)
        if ((f[i] - o[i]).abs() < weakSpan)
          null
        else
          ((v[i] - o[i]) / (f[i] - o[i])).clamp(0.0, 1.0),
    ];
  }

  /// Fingers whose open / fist values differ by less than 300 counts.
  List<int> get weakFingers {
    final o = _open;
    final f = _fist;
    if (o == null || f == null) return const [];
    return [
      for (var i = 0; i < 5; i++)
        if ((f[i] - o[i]).abs() < weakSpan) i,
    ];
  }
}

/// The samples of one calibration step, collected on the phone while the
/// glove runs it, as the glove does (median flex per finger; OPEN also gives
/// the gyro bias and the neutral roll).
class StepCapture {
  new(this._hand);

  final LiveHand _hand;
  final _samples = <List<int>>[];

  void add(GloveSample s) => _samples.add(s.values);

  int get length => _samples.length;

  static double _median(List<double> xs) {
    final s = [...xs]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  List<double> _fingerMedians() => [
    for (var i = 0; i < 5; i++)
      _median([for (final v in _samples) v[i].toDouble()]),
  ];

  /// The OPEN step succeeded: its medians are the open reference; the mean
  /// gyro is the bias and the mean accel gives the neutral roll.
  void applyAsOpen() {
    if (_samples.isEmpty) return;
    _hand._open = _fingerMedians();
    double mean(int ch) =>
        _samples.fold<double>(0, (a, v) => a + v[ch]) / _samples.length;
    _hand
      .._bias = [mean(8), mean(9), mean(10)]
      .._neutral = LiveHand.accelRollDeg(mean(6), mean(7));
  }

  /// The FIST step succeeded: its medians are the fist reference.
  void applyAsFist() {
    if (_samples.isEmpty) return;
    _hand._fist = _fingerMedians();
  }
}
