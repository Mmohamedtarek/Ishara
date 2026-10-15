/// Learn's numbers, each from a user decision.
abstract final class LearnRules {
  /// Q-L2: a right pick-the-meaning answer.
  static const quizXp = 10;

  /// Q-L2: a passed practice step.
  static const practiceXp = 15;

  /// Q-L2 / S8-4: the daily challenge, once per local day.
  static const dailyBonusXp = 30;

  /// Q-L2: a mission ending at this accuracy or more earns a medal.
  static const medalAccuracy = .8;

  /// Q-L2: "Sign now" opens a window this long…
  static const practiceWindow = Duration(seconds: 8);

  /// …and a practice step has this many attempts.
  static const practiceAttempts = 3;

  /// Q-L2: the daily challenge's signs.
  static const dailySigns = 5;

  /// Tiles in a pick-the-meaning step: the answer and 3 others.
  static const quizOptions = 4;

  /// A wrong pick replays the sign at this speed (user, step 8).
  static const wrongReplaySpeed = .5;

  /// The prototype's practice step loops the sign at 0.8×
  /// (`renderMissionStep`).
  static const practiceDemoSpeed = .8;

  /// The prototype's "Great!" text from this match % (`greatMatch`, p ≥ 92).
  static const greatMatchPercent = 92;

  /// XP for a finished step.
  static int stepXp({required bool practice, required bool passed}) =>
      !passed ? 0 : (practice ? practiceXp : quizXp);

  /// S8-1: right ÷ steps attempted (skipped practice is left out).
  static double accuracy({required int right, required int attempted}) =>
      attempted == 0 ? 0 : right / attempted;

  static bool medal(double accuracy) => accuracy >= medalAccuracy;
}
