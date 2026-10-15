import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:ishara_app/features/learn/domain/seeded_random.dart';
import 'package:meta/meta.dart';

/// One step of a mission.
@immutable
sealed class MissionStep {
  const new(this.label);

  /// The sign of this step.
  final String label;
}

/// Watch the avatar and pick the meaning among [options].
final class QuizStep extends MissionStep {
  const new(super.label, this.options);

  /// [LearnRules.quizOptions] different signs, the answer among them.
  final List<String> options;
}

/// "Your turn": sign it with the glove (only `glove: true` signs, sign
/// rule 3).
final class PracticeStep extends MissionStep {
  const new(super.label);
}

/// The steps of one mission, in order.
@immutable
class MissionPlan {
  const new({required this.moduleId, required this.signs, required this.steps});

  /// A module id, or [LearnCatalog.dailyId].
  final String moduleId;

  /// The mission's signs, in order.
  final List<String> signs;
  final List<MissionStep> steps;

  bool get isDaily => moduleId == LearnCatalog.dailyId;
}

/// Builds missions. Every step decision is here, so sign rule 3 is checked
/// in one place: a practice step only for a sign the glove recognizes, and
/// never in a watch-only module.
abstract final class MissionBuilder {
  /// A module's mission: its signs in order, each a quiz then (if the glove
  /// can sign it) a practice step (prototype `renderMissionStep`). [seed]
  /// shuffles the quiz tiles.
  static MissionPlan forModule(
    LearnCatalog catalog,
    LearnModule module, {
    required int seed,
  }) {
    final r = SeededRandom(seed);
    return MissionPlan(
      moduleId: module.id,
      signs: module.signs,
      steps: [
        for (final l in module.signs)
          ..._steps(catalog, l, watchOnly: module.watchOnly, r: r),
      ],
    );
  }

  /// Q-L2: [LearnRules.dailySigns] signs from [pool] (the modules unlocked
  /// when [day] began), picked with a seed from the date: the same all day,
  /// and the same in tests.
  static List<String> dailySigns(List<String> pool, LocalDay day) {
    final picks = [...pool];
    SeededRandom(SeededRandom.seedOf('daily:$day')).shuffle(picks);
    return List.unmodifiable(picks.take(LearnRules.dailySigns));
  }

  /// The daily challenge of [day]: [dailySigns] of [pool]; each sign's steps
  /// follow its own module (a watch-only sign has no practice).
  static MissionPlan daily(
    LearnCatalog catalog,
    List<String> pool,
    LocalDay day,
  ) {
    final signs = dailySigns(pool, day);
    final r = SeededRandom(SeededRandom.seedOf('daily-tiles:$day'));
    return MissionPlan(
      moduleId: LearnCatalog.dailyId,
      signs: signs,
      steps: [
        for (final l in signs)
          ..._steps(
            catalog,
            l,
            watchOnly: catalog.moduleOf(l)?.watchOnly ?? false,
            r: r,
          ),
      ],
    );
  }

  static List<MissionStep> _steps(
    LearnCatalog catalog,
    String label, {
    required bool watchOnly,
    required SeededRandom r,
  }) {
    final sign = catalog.sign(label)!;
    // Q-L1: only approved animations (avatar: true) are taught
    if (!sign.avatar) return const [];
    return [
      QuizStep(label, quizOptions(catalog, label, r)),
      if (sign.glove && !watchOnly) PracticeStep(label),
    ];
  }

  /// The answer and 3 other signs the avatar can perform, never the same
  /// sign twice, shuffled.
  static List<String> quizOptions(
    LearnCatalog catalog,
    String label,
    SeededRandom r,
  ) {
    final others = [
      for (final s in catalog.signs)
        if (s.avatar && s.label != label) s.label,
    ];
    r.shuffle(others);
    final options = [label, ...others.take(LearnRules.quizOptions - 1)];
    r.shuffle(options);
    return List.unmodifiable(options);
  }
}
