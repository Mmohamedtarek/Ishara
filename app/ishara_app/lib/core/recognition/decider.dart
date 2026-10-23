import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:meta/meta.dart';

/// The 4 Decider events (AI-SPEC §5).
enum DeciderEventKind {
  /// Show the word and speak it.
  word,

  /// Show the word faded with "…", not spoken.
  tentative,

  /// The faded word becomes normal and is spoken now.
  confirm,

  /// Remove the faded word (it was not a sign).
  cancel,
}

@immutable
class DeciderEvent {
  const new(this.kind, this.label);

  final DeciderEventKind kind;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is DeciderEvent && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);

  @override
  String toString() => '${kind.name}($label)';
}

class _Run {
  String? label;
  int count = 0;

  void clear() {
    label = null;
    count = 0;
  }
}

/// AI-SPEC v3.3 §5, line by line (reference: `live.py` `Decider.step`).
///
/// Feed it the averaged model output of each run with [step]. The pseudo-code
/// counter [stepNo] starts at 1; the test files' 0-based step is
/// `stepNo - 1` (AI-SPEC §8).
class Decider {
  new(this.labels, this.config)
    : _activeSteps = config.activeSteps,
      _confirmSteps = config.confirmSteps;

  final Labels labels;
  final DeciderConfig config;
  final int _activeSteps;
  final int _confirmSteps;

  final List<Float64List> _recent = [];
  String? _lastSaid;
  int _restSeen = 0;
  int _stepNo = 0;
  int _activeUntil = -1;
  String? _pending;
  int _pendingUntil = -1;
  final Set<String> _blocked = {};
  final _runIdle = _Run();
  final _runTentative = _Run();
  final _runActive = _Run();

  // v3.3: how the pending word is doing (a word signed alone).
  int _pendingRest = 0;
  double _pendingPeak = 0;
  int _pendingRun = 0;
  int _pendingBest = 0;
  double _pendingNull = 1;

  /// Pseudo-code step counter (1 after the first run).
  int get stepNo => _stepNo;

  /// The tentative word waiting for confirmation, if any.
  String? get pending => _pending;

  /// Mean of the last `smooth` vectors after the latest [step] (the
  /// probabilities the decision was taken on), or null before the first run.
  Float64List? get smoothed => _smoothed;
  Float64List? _smoothed;

  List<DeciderEvent> step(Float64List p) {
    if (p.length != labels.length) {
      throw ArgumentError(
        'expected ${labels.length} probabilities, got ${p.length}',
      );
    }
    _stepNo += 1;
    final events = <DeciderEvent>[];
    final pending = _pending;
    if (pending != null && _stepNo > _pendingUntil) {
      events.add(DeciderEvent(DeciderEventKind.cancel, pending));
      _blocked.add(pending);
      _pending = null;
    }

    _recent.add(Float64List.fromList(p));
    if (_recent.length > config.smooth) _recent.removeAt(0);
    final avg = _mean(_recent);
    _smoothed = avg;
    var top = 0;
    for (var i = 1; i < avg.length; i++) {
      if (avg[i] > avg[top]) top = i; // first maximum, like numpy argmax
    }
    final label = labels.all[top];
    final conf = avg[top];
    var nullP = 0.0;
    for (final i in labels.nonWordIndexes) {
      nullP += avg[i];
    }

    if (_pending != null) {
      // v3.3: how the pending word is doing.
      final t = config.tentative;
      if (label == _pending) {
        _pendingPeak = math.max(_pendingPeak, conf);
        _pendingNull = math.min(_pendingNull, nullP);
        final thr = t.thresholdFor(label);
        _pendingRun = (conf >= thr && nullP <= t.maxNull) ? _pendingRun + 1 : 0;
        _pendingBest = math.max(_pendingBest, _pendingRun);
      } else {
        _pendingRun = 0;
      }
      _pendingRest = label == AiSpec.rest ? _pendingRest + 1 : 0;
    }

    if (!labels.isWord(label)) {
      final waiting = _pending;
      if (waiting != null &&
          config.confirmOnRest > 0 &&
          _pendingRest >= config.confirmOnRest &&
          _pendingPeak >= config.restConf &&
          _pendingBest >= config.restRun &&
          _pendingNull <= config.restNull) {
        // v3.3: a word signed alone.
        events.add(DeciderEvent(DeciderEventKind.confirm, waiting));
        _say(waiting);
        _pending = null;
        _pendingRest = 0;
      }
      _restSeen += 1;
      if (_restSeen >= 2) {
        _lastSaid = null;
        _blocked.clear();
      }
      _runIdle.clear();
      _runTentative.clear();
      _runActive.clear();
      return events;
    }
    _restSeen = 0;

    final full = _recent.length == config.smooth;
    final passedIdle = _update(_runIdle, config.idle, label, conf, nullP, full);
    final passedTentative = _update(
      _runTentative,
      config.tentative,
      label,
      conf,
      nullP,
      full,
    );
    final passedActive = _update(
      _runActive,
      config.active,
      label,
      conf,
      nullP,
      full,
    );
    final passedPair = switch (config.pairLevel) {
      DeciderLevel.idle => passedIdle,
      DeciderLevel.tentative => passedTentative,
      DeciderLevel.active => passedActive,
    };

    if (_stepNo <= _activeUntil) {
      if (passedActive && label != _lastSaid) {
        events.add(DeciderEvent(DeciderEventKind.word, label));
        _say(label);
      }
    } else if (_pending != null) {
      if (label == _pending) {
        if (passedIdle) {
          events.add(DeciderEvent(DeciderEventKind.confirm, label));
          _say(label);
          _pending = null;
        }
      } else if (passedPair && label != _lastSaid) {
        events
          ..add(DeciderEvent(DeciderEventKind.confirm, _pending!))
          ..add(DeciderEvent(DeciderEventKind.word, label));
        _say(label);
        _pending = null;
      }
    } else if (label != _lastSaid) {
      if (passedIdle) {
        events.add(DeciderEvent(DeciderEventKind.word, label));
        _say(label);
      } else if (passedTentative && !_blocked.contains(label)) {
        events.add(DeciderEvent(DeciderEventKind.tentative, label));
        _pending = label;
        _pendingUntil = _stepNo + _confirmSteps;
        _pendingRest = 0;
        _pendingPeak = conf;
        _pendingRun = 1;
        _pendingBest = 1;
        _pendingNull = nullP;
      }
    }
    return events;
  }

  bool _update(
    _Run run,
    LevelConfig level,
    String label,
    double conf,
    double nullP,
    bool full,
  ) {
    if (full && conf >= level.thresholdFor(label) && nullP <= level.maxNull) {
      run.count = run.label == label ? run.count + 1 : 1;
      run.label = label;
      return run.count >= level.hold;
    }
    run.clear();
    return false;
  }

  void _say(String label) {
    _lastSaid = label;
    _activeUntil = _stepNo + _activeSteps;
  }

  /// Element-wise mean in float64, summed in order like `np.mean(axis=0)`.
  static Float64List _mean(List<Float64List> rows) {
    final n = rows.first.length;
    final out = Float64List(n);
    for (final r in rows) {
      for (var i = 0; i < n; i++) {
        out[i] += r[i];
      }
    }
    for (var i = 0; i < n; i++) {
      out[i] /= rows.length;
    }
    return out;
  }
}
