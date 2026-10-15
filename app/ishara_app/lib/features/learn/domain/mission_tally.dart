import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:meta/meta.dart';

/// How a step ended.
enum StepOutcome {
  /// Right answer / passed practice.
  right,

  /// Wrong answer / practice failed after its attempts.
  wrong,

  /// Practice skipped without a glove (S8-1): no XP, not in accuracy.
  skipped,
}

/// A mission's running score.
@immutable
class MissionTally {
  const new({this.xp = 0, this.right = 0, this.attempted = 0});

  /// XP from the steps (the daily bonus comes with the result).
  final int xp;
  final int right;

  /// Steps that count for accuracy (S8-1: not skipped ones).
  final int attempted;

  MissionTally add(StepOutcome outcome, {required bool practice}) =>
      switch (outcome) {
        StepOutcome.skipped => this,
        StepOutcome.right => MissionTally(
          xp: xp + LearnRules.stepXp(practice: practice, passed: true),
          right: right + 1,
          attempted: attempted + 1,
        ),
        StepOutcome.wrong => MissionTally(
          xp: xp,
          right: right,
          attempted: attempted + 1,
        ),
      };

  double get accuracy =>
      LearnRules.accuracy(right: right, attempted: attempted);

  /// Shown on the result screen (whole %).
  int get accuracyPercent => (accuracy * 100).round();

  bool get medal => LearnRules.medal(accuracy);
}
