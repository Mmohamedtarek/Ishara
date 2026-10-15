import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';

import '../support/fake_glove.dart';
import '../support/fake_learn.dart';

/// Drives one mission in fake time.
class _M {
  new(this.rig, this.c, this.id, this.async);

  final LearnRig rig;
  final ProviderContainer c;
  final String id;
  final FakeAsync async;

  MissionController get ctl => c.read(missionControllerProvider(id).notifier);
  MissionState get s => c.read(missionControllerProvider(id));
  List<ActivityEvent> get events => c.read(activityRepositoryProvider).events;

  void wait(int ms) => async.elapse(Duration(milliseconds: ms));

  /// Answers the current quiz step (right or with another tile).
  void answer({bool right = true}) {
    final q = s.step! as QuizStep;
    ctl
      ..pick(right ? q.label : q.options.firstWhere((o) => o != q.label))
      ..check();
  }

  /// "Sign now", then the recognizer emits [label] after [ms].
  void sign(String label, {int ms = 4000, double p = .874}) {
    ctl.signNow();
    wait(ms);
    rig.feed.confirm(label, probability: p);
    wait(1);
  }
}

void _run(
  void Function(_M m) body, {
  String id = 'start',
  LearnRig? rig,
  bool connect = true,
}) {
  fakeAsync((async) {
    final r = rig ?? LearnRig();
    final c = ProviderContainer(overrides: r.overrides);
    if (connect) {
      r.glove.connect(r.glove.found.single).ignore();
      async.flushMicrotasks();
    }
    final sub = c.listen(missionControllerProvider(id), (_, _) {});
    r.avatar.loaded();
    async.flushMicrotasks();
    body(_M(r, c, id, async));
    sub.close();
    c.dispose();
    r.dispose().ignore();
    async.flushMicrotasks();
  });
}

void main() {
  group('a module mission (prototype startMission)', () {
    test('Start here: each sign a quiz then a practice step, in order', () {
      _run((m) {
        expect(m.s.plan!.moduleId, 'start');
        expect(
          [for (final s in m.s.plan!.steps) '${s.runtimeType}:${s.label}'],
          [
            for (final l in ['hello', 'thanks', 'please', 'yes', 'no']) ...[
              'QuizStep:$l',
              'PracticeStep:$l',
            ],
          ],
        );
        // the avatar loops the sign at the user's speed (1x)
        expect(m.rig.avatar.plays.last, ('hello', 1.0, true));
      });
    });

    test('closing the mission stops its looping sign (Talk must not '
        'inherit it)', () {
      late LearnRig rig;
      _run((m) {
        rig = m.rig;
        expect(m.rig.avatar.plays.last.$3, isTrue);
      });
      expect(rig.avatar.sent.last['cmd'], 'stop');
    });

    test('a locked module or an unknown id is unavailable', () {
      _run((m) => expect(m.s.unavailable, isTrue), id: 'numbers');
      _run((m) => expect(m.s.unavailable, isTrue), id: 'nope');
    });
  });

  group('pick the meaning', () {
    test('right: +10 XP, logged once; Next goes on', () {
      _run((m) {
        m.ctl.check(); // nothing picked: nothing happens
        expect(m.s.checked, isFalse);
        m.answer();
        expect(m.s.correct, isTrue);
        expect(m.s.xp, 10);
        final e = m.events.single;
        expect(e.type, ActivityType.quiz);
        expect(e.label, 'hello');
        expect(e.moduleId, 'start');
        expect(e.passed, isTrue);
        expect(e.xp, 10);
        expect(e.deviceId, hasLength(32));
        // a second Check or pick changes nothing
        m.ctl
          ..check()
          ..pick('thanks');
        expect(m.events, hasLength(1));
        m.ctl.next();
        expect(m.s.step, isA<PracticeStep>());
        // practice loops the sign at 0.8x (prototype)
        expect(m.rig.avatar.plays.last, ('hello', .8, true));
      });
    });

    test('wrong: no XP, the right tile is known, replay at 0.5x', () {
      _run((m) {
        m.answer(right: false);
        expect(m.s.correct, isFalse);
        expect(m.s.xp, 0);
        expect(m.events.single.passed, isFalse);
        expect(m.events.single.xp, 0);
        expect(m.rig.avatar.plays.last, ('hello', .5, true));
        // Replay keeps the slow speed for a wrong answer
        m.ctl.replay();
        expect(m.rig.avatar.plays.last, ('hello', .5, true));
      });
    });

    test('a new speed replays the quiz sign at it', () {
      _run((m) {
        m.c.read(signSpeedProvider.notifier).cycle(); // 1 → 0.5
        expect(m.rig.avatar.plays.last, ('hello', .5, true));
      });
    });
  });

  group('your turn: the practice check (sign rule 4)', () {
    void toPractice(_M m) => m
      ..answer()
      ..ctl.next();

    test('Sign now cues the glove; the exact label as confirm inside 8 s '
        'passes; match % = its smoothed probability (Q-L4)', () {
      _run((m) {
        toPractice(m);
        m.sign('hello');
        expect(m.rig.glove.commands, contains('practice hello'));
        final p = m.s.practice!;
        expect(p.phase, PracticePhase.passed);
        expect(p.matchPercent, 87);
        final e = m.events.last;
        expect(e.type, ActivityType.practice);
        expect(e.passed, isTrue);
        expect(e.prob, .874);
        expect(e.xp, 15);
        expect(m.s.xp, 25);
      });
    });

    test('counting: the seconds left and the fill', () {
      _run((m) {
        toPractice(m);
        m.ctl.signNow();
        expect(m.s.practice!.phase, PracticePhase.counting);
        expect(m.s.practice!.secondsLeft, 8);
        m.wait(2500);
        expect(m.s.practice!.secondsLeft, 6);
        // published once a second (the screen animates the fill)
        expect(m.s.practice!.progress, closeTo(.25, .02));
        m.ctl.signNow(); // already counting: no second cue
        expect(
          m.rig.glove.commands.where((c) => c.startsWith('practice')),
          hasLength(1),
        );
      });
    });

    test('a word passes too; a tentative alone never does', () {
      _run((m) {
        toPractice(m);
        m.ctl.signNow();
        m.rig.feed.tentative('hello');
        m.wait(8100);
        expect(m.s.practice!.phase, PracticePhase.retry);
        m.ctl.signNow();
        m.rig.feed.word('hello', probability: .95);
        expect(m.s.practice!.phase, PracticePhase.passed);
        expect(m.s.practice!.matchPercent, 95);
      });
    });

    test('another sign: no pass, a neutral hint; 3 attempts, then the step '
        'fails (logged, no XP)', () {
      _run((m) {
        toPractice(m);
        for (var i = 1; i <= 3; i++) {
          m.ctl.signNow();
          m.rig.feed.confirm('thanks');
          expect(m.s.practice!.phase, PracticePhase.counting);
          m.wait(8100);
          expect(m.s.practice!.otherSignSeen, isTrue);
          expect(m.s.practice!.attempt, i);
        }
        expect(m.s.practice!.phase, PracticePhase.failed);
        final e = m.events.last;
        expect(e.type, ActivityType.practice);
        expect(e.passed, isFalse);
        expect(e.prob, isNull);
        expect(e.xp, 0);
        expect(m.s.tally.attempted, 2);
        // a late confirm changes nothing
        m.rig.feed.confirm('hello');
        expect(m.s.practice!.phase, PracticePhase.failed);
        m.ctl.next();
        expect(m.s.step!.label, 'thanks');
      });
    });

    test('nothing at all for 8 s: the attempt fails without a hint', () {
      _run((m) {
        toPractice(m);
        m.ctl.signNow();
        m.wait(8100);
        expect(m.s.practice!.phase, PracticePhase.retry);
        expect(m.s.practice!.otherSignSeen, isFalse);
      });
    });

    test('events outside a window are ignored (before Sign now, after it '
        'ended)', () {
      _run((m) {
        toPractice(m);
        m.rig.feed.confirm('hello');
        expect(m.s.practice!.phase, PracticePhase.ready);
        m.ctl.signNow();
        m.wait(8100);
        m.rig.feed.confirm('hello');
        expect(m.s.practice!.phase, PracticePhase.retry);
      });
    });

    test('hidden (Pair on top): the window is cancelled, not counted; '
        'events are ignored', () {
      _run((m) {
        toPractice(m);
        m.ctl.signNow();
        m.wait(1000);
        m.ctl.setVisible(visible: false);
        expect(m.s.practice!.phase, PracticePhase.ready);
        expect(m.s.practice!.attempt, 0);
        m.rig.feed.confirm('hello');
        expect(m.s.practice!.phase, PracticePhase.ready);
        m.ctl.setVisible(visible: true);
        m.sign('hello');
        expect(m.s.practice!.phase, PracticePhase.passed);
      });
    });
  });

  group('the glove during practice (S8-1)', () {
    test('no glove: blocked, Sign now does nothing; skip: no XP, no log, '
        'left out of accuracy', () {
      _run((m) {
        expect(m.s.block, PracticeBlock.noGlove);
        m
          ..answer()
          ..ctl.next();
        m.ctl.signNow();
        expect(m.s.practice!.phase, PracticePhase.ready);
        expect(m.rig.glove.commands, isNot(contains('practice hello')));
        m.ctl.skipPractice();
        expect(m.s.step, isA<QuizStep>());
        expect(m.events.where((e) => e.type == ActivityType.practice), isEmpty);
        expect(m.s.tally.attempted, 1);
        expect(m.s.tally.accuracy, 1);
      }, connect: false);
    });

    test('skip is refused while the glove works', () {
      _run((m) {
        m
          ..answer()
          ..ctl.next()
          ..ctl.skipPractice();
        expect(m.s.step, isA<PracticeStep>());
      });
    });

    test('#CAL NONE: not calibrated', () {
      _run(
        (m) => expect(m.s.block, PracticeBlock.notCalibrated),
        rig: LearnRig(glove: FakeGloveSource(stored: false)),
      );
    });

    test('#MPU FAIL', () {
      _run(
        (m) => expect(m.s.block, PracticeBlock.mpuFail),
        rig: LearnRig(glove: FakeGloveSource()..mpuFail = true),
      );
    });

    test('the link drops while counting: the attempt is cancelled (not '
        'counted), one reconnect, then practice goes on', () {
      _run((m) {
        m
          ..answer()
          ..ctl.next()
          ..ctl.signNow()
          ..wait(2000);
        m.rig.glove.dropLink();
        expect(m.s.practice!.attempt, 0);
        expect(m.s.practice!.phase, PracticePhase.ready);
        m.async.flushMicrotasks();
        expect(
          m.rig.glove.commands.where((c) => c == 'connect g1'),
          hasLength(2),
        );
        expect(m.rig.glove.status.phase, GlovePhase.ready);
        expect(m.s.block, isNull);
        m.sign('hello');
        expect(m.s.practice!.phase, PracticePhase.passed);
        expect(m.s.practice!.attempt, 1);
      });
    });

    test("another caller's reconnect that finds nothing ends on no glove, "
        'not a stale "Reconnecting…"', () {
      _run((m) {
        m.rig.glove.found = const [];
        m.rig.glove.dropLink();
        expect(m.s.block, PracticeBlock.reconnecting);
        m.async.flushMicrotasks();
        expect(m.s.block, PracticeBlock.noGlove);
      });
    });

    test('the recognizer stopped: blocked until the glove connects again', () {
      _run((m) {
        m.rig.feed.fail();
        expect(m.s.block, PracticeBlock.stopped);
        m.rig.glove.dropLink();
        m.async.flushMicrotasks();
        expect(m.s.block, isNull);
      });
    });
  });

  group('the result (Q-L2, S8-2, S8-4)', () {
    void playAll(_M m, {bool right = true}) {
      while (m.s.result == null) {
        if (m.s.step is QuizStep) {
          m.answer(right: right);
        } else {
          m.sign(right ? m.s.step!.label : 'other-sign');
          if (!right) {
            for (var i = 0; i < 3; i++) {
              if (m.s.practice!.phase == PracticePhase.retry) m.ctl.signNow();
              m.wait(8100);
            }
          }
        }
        m.ctl.next();
      }
    }

    test('all right: 125 XP, 100 %, a medal, the next module unlocked, the '
        'avatar celebrates once (pack data)', () {
      _run((m) {
        m.wait(65000);
        playAll(m);
        final r = m.s.result!;
        expect(r.xp, 125);
        expect(r.bonus, 0);
        expect(r.accuracyPercent, 100);
        expect(r.medal, isTrue);
        expect(r.unlockedNext, isTrue);
        expect(r.moduleFinished, isTrue);
        expect(r.seconds, greaterThanOrEqualTo(65 + 5 * 4));
        final done = m.events.last;
        expect(done.type, ActivityType.missionDone);
        expect(done.label, isNull);
        expect(done.passed, isTrue);
        expect(done.prob, 1);
        expect(done.xp, 0);
        expect(m.rig.avatar.plays.last, ('yes', 1.0, false));
        // the result has no caption: full height for the avatar
        expect(
          m.rig.avatar.sent.where((c) => c['cmd'] == 'reframe').last,
          containsPair('captionPx', 0),
        );
        final sub = m.c.listen(learnProgressProvider, (_, _) {});
        m.async.flushMicrotasks();
        final p = sub.read().requireValue;
        sub.close();
        expect(p.xp, 125);
        expect(p.medals, 1);
        expect(p.signsLearned, 5);
        expect(p.streak, 1);
        expect(p.module('numbers')!.unlocked, isTrue);
      });
    });

    test('a daily started before midnight and finished after it is that '
        "day's challenge (bonus, day)", () {
      fakeAsync((async) {
        final r = LearnRig();
        final c = ProviderContainer(overrides: r.overrides);
        r.glove.connect(r.glove.found.single).ignore();
        async.flushMicrotasks();
        final sub = c.listen(
          missionControllerProvider(LearnCatalog.dailyId),
          (_, _) {},
        );
        r.avatar.loaded();
        async.flushMicrotasks();
        final m = _M(r, c, LearnCatalog.dailyId, async);
        expect(LocalDay.of(clock.now()), const LocalDay(2026, 10, 14));
        async.elapse(const Duration(minutes: 3)); // past midnight
        while (m.s.result == null) {
          if (m.s.step is QuizStep) {
            m.answer();
          } else {
            m.sign(m.s.step!.label);
          }
          m.ctl.next();
        }
        expect(LocalDay.of(clock.now()), const LocalDay(2026, 10, 15));
        expect(m.s.result!.bonus, 30);
        expect(m.events.last.day, const LocalDay(2026, 10, 14));
        sub.close();
        c.dispose();
        r.dispose().ignore();
        async.flushMicrotasks();
      }, initialTime: DateTime(2026, 10, 14, 23, 58));
    });

    test('shown again or back from the background: the step sign loops '
        'again (the avatar pause ended it)', () {
      _run((m) {
        final n = m.rig.avatar.plays.length;
        m.ctl
          ..setVisible(visible: false)
          ..setVisible(visible: true);
        expect(m.rig.avatar.plays.length, n + 1);
        expect(m.rig.avatar.plays.last, ('hello', 1.0, true));
        m.ctl.resumed();
        expect(m.rig.avatar.plays.length, n + 2);
      });
    });

    test('closing halfway keeps what was earned (S8-2), no missionDone', () {
      _run((m) {
        m
          ..answer()
          ..ctl.next()
          ..sign('hello');
        expect(m.events.map((e) => e.xp), [10, 15]);
        expect(
          m.events.where((e) => e.type == ActivityType.missionDone),
          isEmpty,
        );
      });
    });

    test('quizzes right, practice failed: 50 %, no medal, the module is '
        'still finished by its quizzes (S8-3)', () {
      _run((m) {
        while (m.s.result == null) {
          if (m.s.step is QuizStep) {
            m.answer();
          } else {
            for (var i = 0; i < 3; i++) {
              m.ctl.signNow();
              m.wait(8100);
            }
          }
          m.ctl.next();
        }
        expect(m.s.result!.accuracyPercent, 50);
        expect(m.s.result!.medal, isFalse);
        expect(m.s.result!.xp, 50);
        expect(m.s.result!.unlockedNext, isTrue);
        expect(m.events.last.passed, isFalse);
      });
    });

    test('daily challenge: +30 the first time today, then no bonus', () {
      final first = LearnRig();
      _run(
        (m) {
          playAll(m);
          expect(m.s.result!.bonus, 30);
          expect(m.events.last.moduleId, LearnCatalog.dailyId);
          expect(m.events.last.xp, 30);
        },
        id: LearnCatalog.dailyId,
        rig: first,
      );
      // the same day again, on the same phone
      _run(
        (m) {
          expect(m.s.plan!.signs, isNotEmpty);
          playAll(m);
          expect(m.s.result!.bonus, 0);
          expect(m.events.where((e) => e.xp == 30), hasLength(1));
        },
        id: LearnCatalog.dailyId,
        rig: LearnRig(kv: first.kv),
      );
    });

    test('a mission with zero practice steps (watch only)', () {
      final phone = LearnRig().kv;
      for (final id in ['start', 'numbers', 'people', 'needs']) {
        _run(
          (m) {
            expect(m.s.unavailable, isFalse, reason: id);
            playAll(m);
          },
          id: id,
          rig: LearnRig(kv: phone),
        );
      }
      _run(
        (m) {
          expect(m.s.unavailable, isFalse);
          expect(m.s.plan!.steps, everyElement(isA<QuizStep>()));
          expect(m.s.plan!.steps, hasLength(5));
          playAll(m);
          expect(m.s.result!.xp, 50);
          expect(m.s.result!.medal, isTrue);
          expect(m.s.result!.unlockedNext, isFalse);
          expect(m.s.result!.moduleFinished, isTrue);
        },
        id: 'watch',
        rig: LearnRig(kv: phone),
      );
    });
  });

  test('"today" moves on at local midnight by itself', () {
    fakeAsync((async) {
      final c = ProviderContainer();
      final sub = c.listen(learnTodayProvider, (_, _) {});
      expect(sub.read(), const LocalDay(2026, 10, 14));
      async.elapse(const Duration(minutes: 31));
      expect(sub.read(), const LocalDay(2026, 10, 15));
      sub.close();
      c.dispose();
    }, initialTime: DateTime(2026, 10, 14, 23, 30));
  });
}
