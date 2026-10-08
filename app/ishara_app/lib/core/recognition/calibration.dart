import 'dart:convert';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';

/// The glove calibration from a `#CAL {json}` line (AI-SPEC §2, BLE §6).
///
/// The JSON always has `v`, `open`, `fist`, `gyro_bias_raw`, `roll_neutral`,
/// `roll_min`, `roll_max`; other fields (`fw`, `gravity`, camelCase copies)
/// are ignored. The original JSON is kept so it can be stored as is.
@immutable
class GloveCalibration {
  const new({
    required this.version,
    required this.open,
    required this.fist,
    required this.gyroBiasRaw,
    required this.rollNeutral,
    required this.rollMin,
    required this.rollMax,
    required this.json,
  });

  /// Parses the JSON part of a `#CAL` line.
  factory parse(String jsonText) {
    final Object? root;
    try {
      root = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw ParseFailure('#CAL is not JSON', source: '#CAL', cause: e);
    }
    if (root is! Map<String, Object?>) {
      throw const ParseFailure('#CAL is not an object', source: '#CAL');
    }
    final m = root;
    List<double> nums(String k, int n) {
      final v = m[k];
      if (v is List<Object?> && v.length == n && v.every((e) => e is num)) {
        return List.unmodifiable(v.cast<num>().map((e) => e.toDouble()));
      }
      throw ParseFailure('#CAL "$k" must be $n numbers', source: '#CAL');
    }

    double num_(String k) => switch (m[k]) {
      final num n => n.toDouble(),
      _ => throw ParseFailure('#CAL "$k" must be a number', source: '#CAL'),
    };
    final v = m['v'];
    if (v is! int) {
      throw const ParseFailure('#CAL "v" must be an int', source: '#CAL');
    }
    return GloveCalibration(
      version: v,
      open: nums('open', 5),
      fist: nums('fist', 5),
      gyroBiasRaw: nums('gyro_bias_raw', 3),
      rollNeutral: num_('roll_neutral'),
      rollMin: num_('roll_min'),
      rollMax: num_('roll_max'),
      json: jsonText,
    );
  }

  final int version;
  final List<double> open;
  final List<double> fist;
  final List<double> gyroBiasRaw;
  final double rollNeutral;
  final double rollMin;
  final double rollMax;

  /// The JSON exactly as received (stored per user, AI-SPEC §2).
  final String json;

  @override
  bool operator ==(Object other) =>
      other is GloveCalibration && other.json == json;

  @override
  int get hashCode => json.hashCode;
}
