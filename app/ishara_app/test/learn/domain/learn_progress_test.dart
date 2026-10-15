import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/learn_progress.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';

import 'learn_domain_test_support.dart';

void main() {
  final cat = testCatalog();
  LearnProgress p(List<ActivityEvent> e, [String today = '2026-10-14']) =>
      LearnProgress.compute(cat, e, d(today));

  group('a new user', () {
    test('everything is zero; only the first module is open', () {
      final r = p(const []);
      expect(r.xp, 0);
      expect(r.medals, 0);
      expect(r.streak, 0);
      expect(r.signsLearned, 0);
      expect(r.dailyDoneToday, isFalse);
      expect(
        [for (final m in r.modules) m.unlocked],
        [true, false, false, false],
      );
      expect([for (final m in r.modules) m.passed], [0, 0, 0, 0]);
      expect(r.dailyPool, ['a1', 'a2', 'a3']);
    });
  });

  group('XP and medals (Q-L2), from the log only', () {
    test('XP is the sum of every event; medals count missionDone passed', () {
      final r = p([
        ev(ActivityType.quiz), // 10
        ev(ActivityType.quiz, passed: false), // 0
        ev(ActivityType.practice, prob: .9), // 15
        done('2026-10-14'),
        done('2026-10-14', medal: false),
        ev(
          ActivityType.missionDone,
          moduleId: LearnCatalog.dailyId,
          xp: 30,
        ), // daily bonus
      ]);
      expect(r.xp, 55);
      expect(r.medals, 2);
    });
  });

  group('signs learned (Q-L2)', () {
    test('practice passed counts; a quiz only for glove: false signs', () {
      final r = p([
        ev(ActivityType.quiz, label: 'a1'), // glove sign: quiz isn't enough
        ev(ActivityType.practice, label: 'a2'),
        ev(ActivityType.practice, label: 'a3', passed: false),
        ev(ActivityType.quiz, label: 'w1', moduleId: 'mw'),
        ev(ActivityType.quiz, label: 'w2', moduleId: 'mw', passed: false),
        ev(ActivityType.practice, label: 'a2'), // twice = once
        ev(ActivityType.practice, label: 'gone'), // not in this pack
      ]);
      expect(r.learned, {'a2', 'w1'});
      expect(r.signsLearned, 2);
    });
  });

  group('modules: progress and unlocks (S8-3)', () {
    test('progress counts a sign passed in practice or in its quiz', () {
      final r = p([
        ev(ActivityType.quiz, label: 'a1'),
        ev(ActivityType.practice, label: 'a2'),
        ev(ActivityType.quiz, label: 'a3', passed: false),
        ev(ActivityType.practice, label: 'a3', passed: false),
      ]);
      expect(r.module('ma')!.passed, 2);
      expect(r.module('ma')!.finished, isFalse);
      expect(r.module('mb')!.unlocked, isFalse);
    });

    test('a finished module unlocks the next one; without a glove too', () {
      // quizzes only (no glove): every sign passed once
      final r = p([
        for (final l in ['a1', 'a2', 'a3']) ev(ActivityType.quiz, label: l),
      ]);
      expect(r.module('ma')!.finished, isTrue);
      expect(r.module('mb')!.unlocked, isTrue);
      expect(r.module('mw')!.unlocked, isFalse);
      // but not "learned": glove signs need practice (Q-L2)
      expect(r.signsLearned, 0);
    });

    test('unlocks chain: a module needs every module above finished', () {
      // mb's signs passed (e.g. an old daily) while ma isn't finished
      final r = p([
        for (final l in ['b1', 'b2', 'b3']) ev(ActivityType.quiz, label: l),
      ]);
      expect(r.module('mb')!.finished, isTrue);
      expect(r.module('mb')!.unlocked, isFalse);
      expect(r.module('mw')!.unlocked, isFalse);
    });

    test('Q-L1: a module with an unapproved animation stays locked, and so '
        'does everything below it', () {
      final c = testCatalog(lastAvailable: false);
      final all = [
        ...finish(c, 'ma', '2026-10-10'),
        ...finish(c, 'mb', '2026-10-11'),
        ...finish(c, 'mw', '2026-10-12'),
      ];
      final r = LearnProgress.compute(c, all, d('2026-10-14'));
      expect(r.module('mw')!.unlocked, isTrue);
      expect(r.module('mz')!.available, isFalse);
      expect(r.module('mz')!.unlocked, isFalse);
    });
  });

  group('streak (Q-L2): consecutive local days with a finished mission', () {
    int streak(List<String> days, String today) =>
        LearnProgress.streakOn({for (final x in days) d(x)}, d(today));

    test('counts back from today', () {
      expect(
        streak(['2026-10-12', '2026-10-13', '2026-10-14'], '2026-10-14'),
        3,
      );
    });

    test('today not finished yet: it still counts up to yesterday', () {
      expect(streak(['2026-10-12', '2026-10-13'], '2026-10-14'), 2);
    });

    test('a missed day breaks it', () {
      expect(streak(['2026-10-11', '2026-10-13'], '2026-10-14'), 1);
      expect(streak(['2026-10-11', '2026-10-12'], '2026-10-14'), 0);
      expect(streak(['2026-10-12'], '2026-10-14'), 0);
    });

    test('two missions on one day count as one day', () {
      final r = p([done('2026-10-13'), done('2026-10-14'), done('2026-10-14')]);
      expect(r.streak, 2);
      expect(r.medals, 3);
    });

    test('across midnight: 23:59 and 00:01 are two days in a row', () {
      final before = LocalDay.of(DateTime(2026, 10, 13, 23, 59));
      final after = LocalDay.of(DateTime(2026, 10, 14, 0, 1));
      expect(before, d('2026-10-13'));
      expect(after, d('2026-10-14'));
      expect(LearnProgress.streakOn({before, after}, after), 2);
    });

    test('across month and year ends, and 29 February', () {
      expect(streak(['2026-12-31', '2027-01-01'], '2027-01-01'), 2);
      expect(
        streak(['2028-02-28', '2028-02-29', '2028-03-01'], '2028-03-01'),
        3,
      );
      expect(streak(['2026-02-28', '2026-03-01'], '2026-03-01'), 2);
    });

    test("the phone's clock was ahead, then corrected: future days don't "
        'count, and do not break the streak up to today', () {
      // a mission logged on "2026-10-20" while the clock was wrong
      expect(
        streak(['2026-10-13', '2026-10-14', '2026-10-20'], '2026-10-14'),
        2,
      );
      // once the real date reaches it, it counts like any day
      expect(streak(['2026-10-19', '2026-10-20'], '2026-10-20'), 2);
    });

    test('timezone change: each mission keeps the day it was logged with', () {
      // 22:30 UTC on 13 Oct is 01:30 on 14 Oct in Cairo (EEST, UTC+3) and
      // 18:30 on 13 Oct in New York (EDT, UTC−4): the log stores the local
      // day the phone showed, and the streak reads those days.
      final instant = DateTime.utc(2026, 10, 13, 22, 30);
      final cairo = LocalDay.of(instant.add(const Duration(hours: 3)));
      final newYork = LocalDay.of(instant.subtract(const Duration(hours: 4)));
      expect(cairo, d('2026-10-14'));
      expect(newYork, d('2026-10-13'));
      // flew west after a mission at "14 Oct" Cairo time: the next mission
      // is logged on 13 Oct New York time; both days are in the log
      expect(LearnProgress.streakOn({cairo, newYork}, cairo), 2);
    });

    test("Egypt's daylight-saving switches (midnight): no day is skipped or "
        'doubled', () {
      // Spring forward: 2026-04-24 00:00 EET → 01:00 EEST (a 23 h day).
      // Missions at 23:50 on 23 Apr and at 01:05 on 24 Apr (15 min later)
      // are on two days in a row.
      final a = LocalDay.of(DateTime(2026, 4, 23, 23, 50));
      final b = LocalDay.of(DateTime(2026, 4, 24, 1, 5));
      expect(LearnProgress.streakOn({a, b}, b), 2);
      // From 25 Apr 00:30 EEST, "24 hours earlier" on the clock is 23 Apr
      // 23:30 EET: subtracting time would skip 24 Apr. The day before is
      // calendar arithmetic, so 25 Apr → 24 Apr.
      expect(d('2026-04-25').previous, d('2026-04-24'));
      expect(
        LearnProgress.streakOn({
          d('2026-04-23'),
          d('2026-04-24'),
          d('2026-04-25'),
        }, d('2026-04-25')),
        3,
      );
      // Fall back: 2026-10-29 24:00 EEST → 23:00 EET (a 25 h day): both
      // 23:30s are on 29 Oct, the next day is 30 Oct.
      expect(LocalDay.of(DateTime(2026, 10, 29, 23, 30)), d('2026-10-29'));
      expect(d('2026-10-29').next, d('2026-10-30'));
      expect(d('2026-10-30').previous, d('2026-10-29'));
    });
  });

  group('daily challenge (Q-L2, S8-4)', () {
    test('done today: only a daily missionDone on today counts', () {
      expect(
        p([done('2026-10-13', moduleId: LearnCatalog.dailyId)]).dailyDoneToday,
        isFalse,
      );
      expect(p([done('2026-10-14')]).dailyDoneToday, isFalse);
      expect(
        p([done('2026-10-14', moduleId: LearnCatalog.dailyId)]).dailyDoneToday,
        isTrue,
      );
    });

    test('the pool is fixed for the day: a module unlocked today joins it '
        'tomorrow', () {
      final c = testCatalog();
      final events = [
        // ma passed except a3 before today…
        ev(ActivityType.quiz, label: 'a1', day: '2026-10-13'),
        ev(ActivityType.quiz, label: 'a2', day: '2026-10-13'),
        // …and finished today: mb unlocks today
        ev(ActivityType.quiz, label: 'a3'),
      ];
      final today = LearnProgress.compute(c, events, d('2026-10-14'));
      expect(today.module('mb')!.unlocked, isTrue);
      expect(today.dailyPool, ['a1', 'a2', 'a3']);
      final tomorrow = LearnProgress.compute(c, events, d('2026-10-15'));
      expect(tomorrow.dailyPool, ['a1', 'a2', 'a3', 'b1', 'b2', 'b3']);
    });
  });
}
