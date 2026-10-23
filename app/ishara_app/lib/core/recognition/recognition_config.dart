import 'dart:convert';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';

/// Constants fixed by AI-SPEC v3.3 (not by the model files).
abstract final class AiSpec {
  /// Samples per second (§4: one run every 0.2 s = 10 samples).
  static const sampleRateHz = 50;

  /// Samples in the window (§4: 2 s).
  static const window = 100;

  /// A model run happens when the sample count is a multiple of this (§4).
  static const step = 10;

  /// Raw values per sample (§1).
  static const channels = 11;

  /// The hand at rest (§4); a word signed alone is confirmed after `rest`
  /// steps (§5, v3.3).
  static const rest = 'rest';

  /// Labels that are never shown or spoken (§4).
  static const Set<String> nonWords = {rest, 'other'};

  /// BLE gap rule (§4): up to this many missing samples are filled in.
  static const maxFilledGap = 5;

  /// Glove restart (§4, v3.3): up to this many samples in a row may be
  /// dropped (duplicate or older `seq`); the next one is a real gap.
  static const maxDroppedInARow = 10;
}

/// The three Decider levels (AI-SPEC §5), also the values of `pair_level`.
enum DeciderLevel { idle, tentative, active }

/// The model's output labels, in `model/labels.txt` order.
@immutable
class Labels {
  new _(this.all)
    : _index = {for (var i = 0; i < all.length; i++) all[i]: i},
      nonWordIndexes = [
        for (var i = 0; i < all.length; i++)
          if (AiSpec.nonWords.contains(all[i])) i,
      ];

  /// Parses `labels.txt`: one label per line (blank lines ignored, as the
  /// reference `split()` does).
  factory parse(String text) {
    final all = text.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (all.isEmpty) {
      throw const ParseFailure('labels.txt is empty', source: 'labels.txt');
    }
    if (all.toSet().length != all.length) {
      throw const ParseFailure(
        'labels.txt repeats a label',
        source: 'labels.txt',
      );
    }
    for (final w in AiSpec.nonWords) {
      if (!all.contains(w)) {
        throw ParseFailure('labels.txt has no "$w"', source: 'labels.txt');
      }
    }
    return Labels._(List.unmodifiable(all));
  }

  final List<String> all;
  final Map<String, int> _index;

  /// Indexes of `rest` and `other`, in label order.
  final List<int> nonWordIndexes;

  int get length => all.length;

  /// The signs (every label except the non-words), in label order.
  List<String> get signs => [
    for (final l in all)
      if (!AiSpec.nonWords.contains(l)) l,
  ];

  int? indexOf(String label) => _index[label];

  bool isWord(String label) => !AiSpec.nonWords.contains(label);
}

/// One decision level of the Decider (`idle`, `tentative` or `active`).
@immutable
class LevelConfig {
  const new({
    required this.confidence,
    required this.hold,
    required this.maxNull,
    this.perClass = const {},
  });

  factory fromJson(Map<String, Object?> j, String name) {
    double num_(String k) {
      final v = j[k];
      if (v is num) return v.toDouble();
      throw ParseFailure('$name.$k must be a number', source: 'decider.json');
    }

    final hold = j['hold'];
    if (hold is! int || hold < 1) {
      throw ParseFailure(
        '$name.hold must be an int >= 1',
        source: 'decider.json',
      );
    }
    final pc = j['per_class'] ?? const <String, Object?>{};
    if (pc is! Map<String, Object?>) {
      throw ParseFailure(
        '$name.per_class must be an object',
        source: 'decider.json',
      );
    }
    return LevelConfig(
      confidence: num_('confidence'),
      hold: hold,
      maxNull: num_('max_null'),
      perClass: {
        for (final e in pc.entries)
          e.key: switch (e.value) {
            final num n => n.toDouble(),
            _ => throw ParseFailure(
              '$name.per_class.${e.key} must be a number',
              source: 'decider.json',
            ),
          },
      },
    );
  }

  final double confidence;
  final int hold;
  final double maxNull;
  final Map<String, double> perClass;

  double thresholdFor(String label) => perClass[label] ?? confidence;
}

/// `model/decider.json` -> object `"cnn"` (AI-SPEC v3.3 §5).
///
/// Only the keys of the spec are read; `confirm_rf` is always false in the app
/// and ignored. The v3.3 keys (`pair_level`, `confirm_on_rest`, `rest_conf`,
/// `rest_run`, `rest_null`) are optional: their defaults give exactly the
/// v3.2.1 behaviour, so an older `decider.json` still works.
@immutable
class DeciderConfig {
  const new({
    required this.smooth,
    required this.activeSeconds,
    required this.confirmSeconds,
    required this.models,
    required this.idle,
    required this.tentative,
    required this.active,
    this.pairLevel = DeciderLevel.active,
    this.confirmOnRest = 0,
    this.restConf = 0,
    this.restRun = 0,
    this.restNull = 1,
  });

  factory parse(String jsonText) {
    final Object? root;
    try {
      root = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw ParseFailure(
        'decider.json is not JSON',
        source: 'decider.json',
        cause: e,
      );
    }
    final cnn = root is Map<String, Object?> ? root['cnn'] : null;
    if (cnn is! Map<String, Object?>) {
      throw const ParseFailure(
        'decider.json has no "cnn" object',
        source: 'decider.json',
      );
    }
    return DeciderConfig.fromJson(cnn);
  }

  factory fromJson(Map<String, Object?> j) {
    Map<String, Object?> level(String k) => switch (j[k]) {
      final Map<String, Object?> m => m,
      _ => throw ParseFailure('"$k" level is missing', source: 'decider.json'),
    };
    final smooth = j['smooth'];
    if (smooth is! int || smooth < 1) {
      throw const ParseFailure(
        'smooth must be an int >= 1',
        source: 'decider.json',
      );
    }
    final models = j['models'];
    if (models is! List || models.isEmpty || models.any((m) => m is! String)) {
      throw const ParseFailure(
        'models must list the model files',
        source: 'decider.json',
      );
    }
    double seconds(String k) => switch (j[k]) {
      final num n when n >= 0 => n.toDouble(),
      _ => throw ParseFailure(
        '$k must be a number >= 0',
        source: 'decider.json',
      ),
    };
    // v3.3 keys: absent = the v3.2.1 default.
    final pairLevel = switch (j['pair_level']) {
      null => DeciderLevel.active,
      'idle' => DeciderLevel.idle,
      'tentative' => DeciderLevel.tentative,
      'active' => DeciderLevel.active,
      _ => throw const ParseFailure(
        'pair_level must be "idle", "tentative" or "active"',
        source: 'decider.json',
      ),
    };
    int count(String k) => switch (j[k]) {
      null => 0,
      final int n when n >= 0 => n,
      _ => throw ParseFailure('$k must be an int >= 0', source: 'decider.json'),
    };
    double number(String k, double byDefault) => switch (j[k]) {
      null => byDefault,
      final num n => n.toDouble(),
      _ => throw ParseFailure('$k must be a number', source: 'decider.json'),
    };
    return DeciderConfig(
      smooth: smooth,
      activeSeconds: seconds('active_s'),
      confirmSeconds: seconds('confirm_s'),
      models: List.unmodifiable(models.cast<String>()),
      idle: LevelConfig.fromJson(level('idle'), 'idle'),
      tentative: LevelConfig.fromJson(level('tentative'), 'tentative'),
      active: LevelConfig.fromJson(level('active'), 'active'),
      pairLevel: pairLevel,
      confirmOnRest: count('confirm_on_rest'),
      restConf: number('rest_conf', 0),
      restRun: count('rest_run'),
      restNull: number('rest_null', 1),
    );
  }

  final int smooth;
  final double activeSeconds;
  final double confirmSeconds;

  /// Model files to average, in order (AI-SPEC §4).
  final List<String> models;
  final LevelConfig idle;
  final LevelConfig tentative;
  final LevelConfig active;

  /// `pair_level`: the level a second word must pass to confirm a pending
  /// tentative word. Default `active` (v3.2.1).
  final DeciderLevel pairLevel;

  /// `confirm_on_rest`: a word signed alone is confirmed after this many
  /// `rest` steps in a row. 0 = off (default).
  final int confirmOnRest;

  /// `rest_conf`: the pending word's highest `conf` must reach this.
  /// Default 0.
  final double restConf;

  /// `rest_run`: the pending word must have passed the tentative level this
  /// many steps in a row at some point. Default 0.
  final int restRun;

  /// `rest_null`: at some step where the pending word was the top label,
  /// `null` was this low or lower. Default 1.
  final double restNull;

  /// Model runs per second (AI-SPEC §5: one run = 0.2 s).
  static const double runsPerSecond = AiSpec.sampleRateHz / AiSpec.step;

  /// `active_s` in model runs, rounded like `live.py` (Python `round`).
  int get activeSteps => roundHalfEven(activeSeconds * runsPerSecond);

  /// `confirm_s` in model runs, rounded like `live.py` (Python `round`).
  int get confirmSteps => roundHalfEven(confirmSeconds * runsPerSecond);

  /// Checks that every `per_class` label exists in [labels].
  void validateAgainst(Labels labels) {
    for (final (name, l) in [
      ('idle', idle),
      ('tentative', tentative),
      ('active', active),
    ]) {
      for (final label in l.perClass.keys) {
        if (labels.indexOf(label) == null) {
          throw ParseFailure(
            '$name.per_class names unknown label "$label"',
            source: 'decider.json',
          );
        }
      }
    }
  }
}

/// Python 3 `round(x)`: halves go to the even neighbour (C7). Dart's
/// `round()` sends halves away from zero, which differs for 12.5 and the like.
int roundHalfEven(double x) {
  final f = x.floorToDouble();
  final diff = x - f;
  if (diff < .5) return f.toInt();
  if (diff > .5) return f.toInt() + 1;
  final fi = f.toInt();
  return fi.isEven ? fi : fi + 1;
}
