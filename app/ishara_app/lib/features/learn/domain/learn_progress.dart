import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:meta/meta.dart';

/// One module on the Learn path.
@immutable
class ModuleProgress {
  const new({
    required this.module,
    required this.passed,
    required this.unlocked,
    required this.available,
  });

  final LearnModule module;

  /// Signs passed at least once, in practice or in their quiz (S8-3).
  final int passed;
  int get total => module.signs.length;

  /// All its signs passed: the next module unlocks (S8-3).
  bool get finished => passed >= total;

  /// The module above is finished (Q-L2), and so on up to the first.
  final bool unlocked;

  /// Every sign has an approved animation (Q-L1).
  final bool available;
}

/// Everything the Learn screen shows, computed from the activity log
/// (nothing is stored as a total).
@immutable
class LearnProgress {
  const new _({
    required this.xp,
    required this.medals,
    required this.streak,
    required this.learned,
    required this.modules,
    required this.dailyDoneToday,
    required this.dailyPool,
  });

  /// [events] in log order; [today] is the phone's local day now.
  factory compute(
    LearnCatalog catalog,
    List<ActivityEvent> events,
    LocalDay today,
  ) {
    var xp = 0;
    var medals = 0;
    final missionDays = <LocalDay>{};
    var dailyDone = false;
    final learned = <String>{};
    for (final e in events) {
      xp += e.xp;
      switch (e.type) {
        case ActivityType.missionDone:
          if (e.passed) medals++;
          missionDays.add(e.day);
          if (e.moduleId == LearnCatalog.dailyId && e.day == today) {
            dailyDone = true;
          }
        case ActivityType.practice:
          if (e.passed && catalog.sign(e.label!) != null) learned.add(e.label!);
        case ActivityType.quiz:
          // Q-L2: a quiz teaches a sign only when the glove can't sign it
          final sign = catalog.sign(e.label!);
          if (e.passed && sign != null && !sign.glove) learned.add(e.label!);
      }
    }
    final modules = moduleStates(catalog, events);
    // S8-4 / "stays the same all day": the daily pool is what was unlocked
    // when today began, so a module unlocked today joins it tomorrow.
    final before = [
      for (final e in events)
        if (e.day.isBefore(today)) e,
    ];
    final pool = [
      for (final m in moduleStates(catalog, before))
        if (m.unlocked) ...m.module.signs,
    ];
    return LearnProgress._(
      xp: xp,
      medals: medals,
      streak: streakOn(missionDays, today),
      learned: Set.unmodifiable(learned),
      modules: modules,
      dailyDoneToday: dailyDone,
      dailyPool: List.unmodifiable(pool),
    );
  }

  /// Q-L2: consecutive local days with at least one finished mission, up to
  /// today. A day not finished yet doesn't break it: until today has a
  /// mission, the streak counts up to yesterday. Days after [today] (the
  /// phone's clock was ahead, then corrected) don't count.
  static int streakOn(Set<LocalDay> missionDays, LocalDay today) {
    var day = missionDays.contains(today) ? today : today.previous;
    var n = 0;
    while (missionDays.contains(day)) {
      n++;
      day = day.previous;
    }
    return n;
  }

  /// Each module's progress, lock and availability from [events].
  static List<ModuleProgress> moduleStates(
    LearnCatalog catalog,
    List<ActivityEvent> events,
  ) {
    // S8-3: passed at least once, in practice or in its quiz step
    final passed = {
      for (final e in events)
        if (e.passed && e.type != ActivityType.missionDone) e.label!,
    };
    final out = <ModuleProgress>[];
    var aboveFinished = true;
    for (final m in catalog.modules) {
      final available = catalog.available(m);
      final p = ModuleProgress(
        module: m,
        passed: m.signs.where(passed.contains).length,
        unlocked: available && aboveFinished,
        available: available,
      );
      out.add(p);
      aboveFinished = aboveFinished && p.unlocked && p.finished;
    }
    return List.unmodifiable(out);
  }

  /// Sum of every event's XP.
  final int xp;

  /// Missions that ended with a medal.
  final int medals;
  final int streak;

  /// Q-L2 "signs learned": passed in practice, or in a quiz for signs the
  /// glove can't sign.
  final Set<String> learned;
  int get signsLearned => learned.length;

  /// In path order.
  final List<ModuleProgress> modules;

  /// The daily challenge reached its result screen today (S8-4: no second
  /// bonus).
  final bool dailyDoneToday;

  /// The signs the daily challenge picks from: the modules unlocked when
  /// today began, in path order.
  final List<String> dailyPool;

  ModuleProgress? module(String id) {
    for (final m in modules) {
      if (m.module.id == id) return m;
    }
    return null;
  }
}
