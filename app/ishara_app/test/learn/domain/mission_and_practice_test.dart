import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/mission_tally.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';
import 'package:ishara_app/features/learn/domain/seeded_random.dart';

import 'learn_domain_test_support.dart';

/// The shipped ASL pack as Learn sees it.
LearnCatalog shippedCatalog() {
  final labels = Labels.parse(
    File('assets/packs/asl/kit/model/labels.txt').readAsStringSync(),
  );
  final c = SignCatalogue.parse(
    File('assets/packs/asl/signs.json').readAsStringSync(),
    labels: labels,
  );
  return LearnCatalog(
    signs: [
      for (final s in c.signs)
        LearnSign(label: s.label, glove: s.glove, avatar: s.avatar),
    ],
    modules: [
      for (final m in c.modules)
        LearnModule(id: m.id, signs: m.signs, watchOnly: m.watchOnly),
    ],
  );
}

void main() {
  group('seeded random: the same numbers everywhere', () {
    test('mulberry32 and FNV-1a match an independent implementation', () {
      // reference values from Python (app/PROGRESS.md, step 8)
      expect(SeededRandom.seedOf('a'), 0xE40C292C);
      expect(SeededRandom.seedOf('daily:2026-10-14'), 948568466);
      final r = SeededRandom(1);
      expect(
        [r.nextUint32(), r.nextUint32(), r.nextUint32()],
        [2693262067, 11749833, 2265367787],
      );
      final d = SeededRandom(948568466);
      expect(
        [d.nextUint32(), d.nextUint32(), d.nextUint32()],
        [2978335912, 3057186545, 661338289],
      );
    });

    test('nextInt stays in range; shuffle keeps every item', () {
      final r = SeededRandom(7);
      for (var i = 0; i < 1000; i++) {
        expect(r.nextInt(5), inInclusiveRange(0, 4));
      }
      expect(() => r.nextInt(0), throwsArgumentError);
      final items = List.generate(20, (i) => i);
      r.shuffle(items);
      expect(items.toSet(), Set.of(List.generate(20, (i) => i)));
    });
  });

  group('mission building (sign rule 3)', () {
    final cat = testCatalog();

    test('a module: each sign a quiz, then a practice step if the glove '
        'can sign it, in module order', () {
      final plan = MissionBuilder.forModule(cat, cat.module('ma')!, seed: 1);
      expect(
        [for (final s in plan.steps) '${s.runtimeType}:${s.label}'],
        [
          'QuizStep:a1',
          'PracticeStep:a1',
          'QuizStep:a2',
          'PracticeStep:a2',
          'QuizStep:a3',
          'PracticeStep:a3',
        ],
      );
      expect(plan.isDaily, isFalse);
    });

    test('a watch-only module: quiz steps only (zero practice)', () {
      final plan = MissionBuilder.forModule(cat, cat.module('mw')!, seed: 1);
      expect(plan.steps, everyElement(isA<QuizStep>()));
      expect(plan.steps, hasLength(2));
    });

    test('a sign without an approved animation gets no step', () {
      final c = testCatalog(lastAvailable: false);
      expect(
        MissionBuilder.forModule(c, c.module('mz')!, seed: 1).steps,
        isEmpty,
      );
    });

    test('quiz: 4 different signs the avatar can perform, the answer among '
        'them, shuffled by the seed', () {
      for (var seed = 0; seed < 200; seed++) {
        final o = MissionBuilder.quizOptions(cat, 'a1', SeededRandom(seed));
        expect(o, hasLength(LearnRules.quizOptions));
        expect(o.toSet(), hasLength(4));
        expect(o, contains('a1'));
        expect(o.every((l) => cat.sign(l)!.avatar), isTrue);
      }
      final c = testCatalog(lastAvailable: false);
      for (var seed = 0; seed < 200; seed++) {
        expect(
          MissionBuilder.quizOptions(c, 'a1', SeededRandom(seed)),
          isNot(contains('z1')),
        );
      }
      // same seed, same tiles; the answer isn't always first
      expect(
        MissionBuilder.quizOptions(cat, 'a1', SeededRandom(3)),
        MissionBuilder.quizOptions(cat, 'a1', SeededRandom(3)),
      );
      expect({
        for (var s = 0; s < 50; s++)
          MissionBuilder.quizOptions(cat, 'a1', SeededRandom(s)).indexOf('a1'),
      }, hasLength(4));
    });

    test('daily: 5 signs from the pool, the same all day, from a seed of the '
        'date', () {
      final pool = ['a1', 'a2', 'a3', 'b1', 'b2', 'b3', 'w1', 'w2'];
      final day = d('2026-10-14');
      final a = MissionBuilder.dailySigns(pool, day);
      expect(a, hasLength(LearnRules.dailySigns));
      expect(a.toSet(), hasLength(5));
      expect(pool, containsAll(a));
      expect(MissionBuilder.dailySigns(pool, day), a);
      final plan = MissionBuilder.daily(cat, pool, day);
      expect(plan.signs, a);
      expect(plan.isDaily, isTrue);
      expect(MissionBuilder.daily(cat, pool, day).steps.map((s) => s.label), [
        for (final s in plan.steps) s.label,
      ]);
      // another day, usually another pick
      final days = {
        for (var i = 0; i < 10; i++)
          MissionBuilder.dailySigns(pool, LocalDay(2026, 10, 14 + i)).join(),
      };
      expect(days.length, greaterThan(1));
    });

    test('daily: a glove: false sign gets no practice step', () {
      final plan = MissionBuilder.daily(cat, [
        'w1',
        'w2',
        'a1',
      ], d('2026-10-14'));
      for (final s in plan.steps.whereType<PracticeStep>()) {
        expect(cat.sign(s.label)!.glove, isTrue);
      }
      expect(plan.steps.whereType<QuizStep>(), hasLength(3));
      expect(plan.steps.whereType<PracticeStep>(), hasLength(1));
    });

    test('a pool smaller than 5 gives every sign once', () {
      expect(MissionBuilder.dailySigns(['a1', 'a2'], d('2026-10-14')).toSet(), {
        'a1',
        'a2',
      });
    });

    test('architecture (sign rule 3), shipped ASL pack: no practice step '
        'for a glove: false sign or in a watch-only module, in every module '
        'and 400 days of daily challenges', () {
      final c = shippedCatalog();
      expect(
        [for (final m in c.modules) m.id],
        ['start', 'numbers', 'people', 'needs', 'watch'],
      );
      expect(c.modules.last.watchOnly, isTrue);
      final all = [for (final m in c.modules) ...m.signs];
      void check(MissionPlan p) {
        for (final s in p.steps) {
          final sign = c.sign(s.label)!;
          expect(sign.avatar, isTrue, reason: s.label);
          if (s is PracticeStep) {
            expect(sign.glove, isTrue, reason: '${p.moduleId} ${s.label}');
            expect(c.moduleOf(s.label)!.watchOnly, isFalse);
          }
        }
      }

      for (final m in c.modules) {
        final plan = MissionBuilder.forModule(c, m, seed: 42);
        check(plan);
        expect(plan.steps.whereType<QuizStep>(), hasLength(m.signs.length));
      }
      var day = d('2026-01-01');
      for (var i = 0; i < 400; i++) {
        check(MissionBuilder.daily(c, all, day));
        day = day.next;
      }
    });
  });

  group('practice check (sign rule 4, Q-L2, Q-L4)', () {
    final t0 = DateTime.utc(2026, 10, 14, 12);
    Duration ms(int v) => Duration(milliseconds: v);

    test('passes on the exact label as word or confirm inside the window; '
        "the match % is that step's smoothed probability", () {
      for (final kind in ['word', 'confirm']) {
        final c = PracticeCheck('hello')..start(t0);
        expect(c.phase, PracticePhase.counting);
        expect(
          c.onEvent(
            'hello',
            fires: true,
            probability: .874,
            at: t0.add(ms(4200)),
          ),
          isTrue,
          reason: kind,
        );
        expect(c.phase, PracticePhase.passed);
        expect(c.matchPercent, 87);
        expect(c.attempt, 1);
      }
    });

    test('a tentative or cancel never passes', () {
      final c = PracticeCheck('hello')..start(t0);
      expect(
        c.onEvent('hello', fires: false, probability: .9, at: t0.add(ms(10))),
        isFalse,
      );
      expect(c.phase, PracticePhase.counting);
    });

    test('another sign: no pass, remembered for a neutral hint', () {
      final c = PracticeCheck('hello')..start(t0);
      expect(
        c.onEvent('thanks', fires: true, probability: .9, at: t0.add(ms(10))),
        isFalse,
      );
      expect(c.otherSignSeen, isTrue);
      expect(c.phase, PracticePhase.counting);
      // the right sign later in the same window still passes
      expect(
        c.onEvent('hello', fires: true, probability: .8, at: t0.add(ms(3000))),
        isTrue,
      );
    });

    test("the window is 8 s, inclusive; events before it or after it don't "
        'count', () {
      final c = PracticeCheck('hello')..start(t0);
      expect(
        c.onEvent(
          'hello',
          fires: true,
          probability: .9,
          at: t0.subtract(ms(1)),
        ),
        isFalse,
      );
      expect(
        c.onEvent('hello', fires: true, probability: .9, at: t0.add(ms(8001))),
        isFalse,
      );
      expect(
        c.onEvent('hello', fires: true, probability: .9, at: t0.add(ms(8000))),
        isTrue,
      );
    });

    test('a timer never passes it: 3 timed-out attempts fail the step', () {
      final c = PracticeCheck('hello');
      var now = t0;
      for (var i = 1; i <= 3; i++) {
        c.start(now);
        expect(c.remaining(now), LearnRules.practiceWindow);
        c.onTimeout(now.add(ms(7999))); // too early: nothing happens
        expect(c.phase, PracticePhase.counting);
        now = now.add(LearnRules.practiceWindow);
        c.onTimeout(now);
        expect(c.remaining(now), Duration.zero);
        expect(c.attempt, i);
        expect(c.phase, i < 3 ? PracticePhase.retry : PracticePhase.failed);
        // the window is closed: a late confirm doesn't count
        expect(
          c.onEvent('hello', fires: true, probability: .9, at: now),
          isFalse,
        );
      }
      expect(c.matchPercent, isNull);
      expect(() => c.start(now), throwsStateError);
    });

    test('the glove dropped (S8-1): the attempt is cancelled, not counted', () {
      final c = PracticeCheck('hello')
        ..start(t0)
        ..cancelAttempt();
      expect(c.phase, PracticePhase.ready);
      expect(c.attempt, 0);
      c
        ..start(t0)
        ..onTimeout(t0.add(LearnRules.practiceWindow))
        ..start(t0.add(const Duration(seconds: 9)))
        ..cancelAttempt();
      expect(c.phase, PracticePhase.retry);
      expect(c.attempt, 1);
      c.cancelAttempt(); // nothing running: no change
      expect(c.attempt, 1);
    });

    test('a second attempt can pass after a failed one', () {
      final c = PracticeCheck('hello')
        ..start(t0)
        ..onTimeout(t0.add(LearnRules.practiceWindow));
      final t1 = t0.add(const Duration(seconds: 20));
      c.start(t1);
      expect(
        c.onEvent('hello', fires: true, probability: .5, at: t1.add(ms(5000))),
        isTrue,
      );
      expect(c.attempt, 2);
      expect(c.matchPercent, 50);
    });
  });

  group('mission tally (Q-L2, S8-1)', () {
    test('XP per step; skipped practice left out of accuracy', () {
      final t = const MissionTally()
          .add(StepOutcome.right, practice: false) // +10
          .add(StepOutcome.right, practice: true) // +15
          .add(StepOutcome.wrong, practice: false)
          .add(StepOutcome.skipped, practice: true);
      expect(t.xp, 25);
      expect(t.right, 2);
      expect(t.attempted, 3);
      expect(t.accuracyPercent, 67);
      expect(t.medal, isFalse);
    });

    test('a medal from exactly 80 %', () {
      var t = const MissionTally();
      for (var i = 0; i < 4; i++) {
        t = t.add(StepOutcome.right, practice: false);
      }
      t = t.add(StepOutcome.wrong, practice: true);
      expect(t.accuracy, .8);
      expect(t.medal, isTrue);
      expect(const MissionTally().medal, isFalse);
      expect(const MissionTally().accuracy, 0);
    });

    test('a mission with only quiz steps (watch only)', () {
      var t = const MissionTally();
      for (var i = 0; i < 5; i++) {
        t = t.add(StepOutcome.right, practice: false);
      }
      expect(t.xp, 50);
      expect(t.accuracyPercent, 100);
    });

    test('step XP', () {
      expect(LearnRules.stepXp(practice: false, passed: true), 10);
      expect(LearnRules.stepXp(practice: true, passed: true), 15);
      expect(LearnRules.stepXp(practice: true, passed: false), 0);
    });
  });

  group('activity event (Phase 0 model users/{uid}/activity/{eventId})', () {
    test('round-trips through JSON with every field', () {
      final e = ev(
        ActivityType.practice,
        label: 'hello',
        moduleId: 'start',
        prob: .87,
      );
      final j = e.toJson();
      expect(j.keys.toSet(), {
        'v',
        'id',
        'type',
        'label',
        'moduleId',
        'passed',
        'prob',
        'xp',
        'day',
        'at',
        'deviceId',
      });
      final back = ActivityEvent.tryParse(j)!;
      expect(back.toJson(), j);
      expect(j['day'], '2026-10-14');
      expect(j['at'], '2026-10-14T12:00:00.000Z');
    });

    test('anything else is not counted (a newer version, damage)', () {
      final good = ev(ActivityType.quiz).toJson();
      for (final bad in <Map<String, Object?>>[
        {...good, 'v': 2},
        {...good, 'type': 'badge'},
        {...good, 'xp': -5},
        {...good, 'xp': 1.5},
        {...good, 'day': '2026-02-30'},
        {...good, 'day': '14/10/2026'},
        {...good, 'at': 'yesterday'},
        {...good, 'label': null}, // a quiz needs its sign
        {...done('2026-10-14').toJson(), 'label': 'hello'},
        {...good, 'prob': 'high'},
        {...good}..remove('deviceId'),
      ]) {
        expect(ActivityEvent.tryParse(bad), isNull, reason: '$bad');
      }
      expect(ActivityEvent.tryParse('text'), isNull);
    });

    test('LocalDay parses and prints yyyy-mm-dd', () {
      expect('${const LocalDay(2026, 1, 5)}', '2026-01-05');
      expect(LocalDay.tryParse('2026-1-5'), isNull);
      expect(d('2026-10-14').compareTo(d('2026-10-15')), lessThan(0));
      expect(d('2026-10-14').hashCode, d('2026-10-14').hashCode);
    });

    test('the catalogue refuses a module using the daily id or an unknown '
        'sign', () {
      expect(
        () => LearnCatalog(
          signs: const [LearnSign(label: 'a', glove: true, avatar: true)],
          modules: const [
            LearnModule(id: LearnCatalog.dailyId, signs: ['a']),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => LearnCatalog(
          signs: const [],
          modules: const [
            LearnModule(id: 'm', signs: ['a']),
          ],
        ),
        throwsArgumentError,
      );
      expect(testCatalog().module('nope'), isNull);
      expect(testCatalog().moduleOf('nope'), isNull);
    });
  });
}
