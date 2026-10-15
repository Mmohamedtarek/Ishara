import 'package:ishara_app/features/learn/domain/learn_rules.dart';

/// Where a practice step is.
enum PracticePhase {
  /// Waiting for "Sign now" (first attempt).
  ready,

  /// The window is open.
  counting,

  /// An attempt ran out; attempts are left ("Try again").
  retry,

  /// The recognizer emitted the label inside a window.
  passed,

  /// No attempt passed.
  failed,
}

/// The practice check (sign rule 4, Q-L2, Q-L4): it passes only when the
/// recognizer emits exactly [label] as `word` or `confirm` inside the window
/// that "Sign now" opened; [LearnRules.practiceAttempts] attempts. No timer
/// passes it, nothing is random. Times are given by the caller.
class PracticeCheck {
  new(
    this.label, {
    this.window = LearnRules.practiceWindow,
    this.attempts = LearnRules.practiceAttempts,
  });

  final String label;
  final Duration window;
  final int attempts;

  PracticePhase get phase => _phase;
  PracticePhase _phase = PracticePhase.ready;

  /// Attempts started so far (counting one that is running).
  int get attempt => _attempt;
  int _attempt = 0;

  DateTime? _openedAt;

  /// Another sign was emitted in the last window (shown as a neutral hint,
  /// never named).
  bool get otherSignSeen => _otherSignSeen;
  bool _otherSignSeen = false;

  /// Q-L4: the smoothed probability of [label] at the step where it fired.
  double? get probability => _probability;
  double? _probability;

  /// The match % shown (Q-L4), once passed.
  int? get matchPercent {
    final p = _probability;
    return p == null ? null : (p * 100).round();
  }

  bool get canStart =>
      _phase == PracticePhase.ready || _phase == PracticePhase.retry;

  /// "Sign now" (or "Try again"): opens the window at [now].
  void start(DateTime now) {
    if (!canStart) throw StateError('practice is $_phase');
    _attempt++;
    _openedAt = now;
    _otherSignSeen = false;
    _phase = PracticePhase.counting;
  }

  /// Time left in the window at [now] (zero when not counting).
  Duration remaining(DateTime now) {
    final opened = _openedAt;
    if (_phase != PracticePhase.counting || opened == null) {
      return Duration.zero;
    }
    final left = window - now.difference(opened);
    return left.isNegative ? Duration.zero : left;
  }

  /// A Decider event arrived at [at]. [fires]: it is a `word` or `confirm`
  /// (a `tentative` or `cancel` never passes). Returns true if it passed
  /// the step.
  bool onEvent(
    String eventLabel, {
    required bool fires,
    required double? probability,
    required DateTime at,
  }) {
    final opened = _openedAt;
    if (_phase != PracticePhase.counting || opened == null || !fires) {
      return false;
    }
    final since = at.difference(opened);
    if (since.isNegative || since > window) return false;
    if (eventLabel != label) {
      _otherSignSeen = true;
      return false;
    }
    _probability = probability;
    _phase = PracticePhase.passed;
    return true;
  }

  /// The window's time is up at [now]: the attempt fails (the step fails
  /// after the last attempt). Does nothing before the window ends.
  void onTimeout(DateTime now) {
    final opened = _openedAt;
    if (_phase != PracticePhase.counting || opened == null) return;
    if (now.difference(opened) < window) return;
    _phase = _attempt >= attempts ? PracticePhase.failed : PracticePhase.retry;
  }

  /// The glove dropped or stopped during the window (S8-1): the attempt is
  /// cancelled and not counted.
  void cancelAttempt() {
    if (_phase != PracticePhase.counting) return;
    _attempt--;
    _openedAt = null;
    _phase = _attempt == 0 ? PracticePhase.ready : PracticePhase.retry;
  }
}
