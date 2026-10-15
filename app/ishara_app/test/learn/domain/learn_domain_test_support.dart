import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';

/// A small catalogue shaped like Q-L1: two glove modules, a watch-only one,
/// and a module with an unapproved animation.
LearnCatalog testCatalog({bool lastAvailable = true}) => LearnCatalog(
  signs: [
    for (final l in ['a1', 'a2', 'a3', 'b1', 'b2', 'b3'])
      LearnSign(label: l, glove: true, avatar: true),
    for (final l in ['w1', 'w2'])
      LearnSign(label: l, glove: false, avatar: true),
    LearnSign(label: 'z1', glove: true, avatar: lastAvailable),
  ],
  modules: const [
    LearnModule(id: 'ma', signs: ['a1', 'a2', 'a3']),
    LearnModule(id: 'mb', signs: ['b1', 'b2', 'b3']),
    LearnModule(id: 'mw', signs: ['w1', 'w2'], watchOnly: true),
    LearnModule(id: 'mz', signs: ['z1']),
  ],
);

var _n = 0;

ActivityEvent ev(
  ActivityType type, {
  String day = '2026-10-14',
  String? label,
  String moduleId = 'ma',
  bool passed = true,
  double? prob,
  int? xp,
}) => ActivityEvent(
  id: 'e${_n++}',
  type: type,
  label: type == ActivityType.missionDone ? null : label ?? 'a1',
  moduleId: moduleId,
  passed: passed,
  prob: prob,
  xp:
      xp ??
      switch (type) {
        ActivityType.quiz => passed ? 10 : 0,
        ActivityType.practice => passed ? 15 : 0,
        ActivityType.missionDone => 0,
      },
  day: LocalDay.tryParse(day)!,
  at: DateTime.utc(2026, 10, 14, 12),
  deviceId: 'dev',
);

ActivityEvent done(String day, {String moduleId = 'ma', bool medal = true}) =>
    ev(
      ActivityType.missionDone,
      day: day,
      moduleId: moduleId,
      passed: medal,
      prob: medal ? 1 : .5,
    );

/// Quiz + practice passed for every sign of [module] on [day].
List<ActivityEvent> finish(LearnCatalog c, String module, String day) => [
  for (final l in c.module(module)!.signs) ...[
    ev(ActivityType.quiz, label: l, moduleId: module, day: day),
    if (c.sign(l)!.glove)
      ev(ActivityType.practice, label: l, moduleId: module, day: day),
  ],
  done(day, moduleId: module),
];

LocalDay d(String s) => LocalDay.tryParse(s)!;
