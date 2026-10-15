import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/presentation/mission_screen.dart';

import '../support/fake_learn.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

class _Mission {
  final rig = LearnRig();
  late Harness h;

  ProviderContainer get c =>
      ProviderScope.containerOf(t.element(find.byType(MissionScreen)));
  late WidgetTester t;

  MissionState get s => c.read(missionControllerProvider('start'));
  MissionController get ctl =>
      c.read(missionControllerProvider('start').notifier);

  Future<void> pump(
    WidgetTester tester, {
    bool connect = true,
    AppLanguage language = AppLanguage.en,
  }) async {
    t = tester;
    addTearDown(rootBundle.clear);
    addTearDown(rig.dispose);
    if (connect) {
      await t.runAsync(() => rig.glove.connect(rig.glove.found.single));
    }
    h = await pumpScreen(
      t,
      const MissionScreen(moduleId: 'start'),
      language: language,
      harness: Harness(glove: rig.glove, store: rig.kv),
      overrides: rig.screenOverrides,
    );
    rig.avatar.loaded();
    await settle(t);
  }

  /// Right answer to the quiz on screen, then Next.
  Future<void> passQuiz() async {
    await tapIt(t, _key('tile-${s.step!.label}'));
    await tapIt(t, _key('mission-check'));
    await tapIt(t, _key('mission-check'));
  }
}

void main() {
  testWidgets('quiz: Check waits for a pick; a right pick says so, +10 XP; '
      'Next goes to "your turn"', (t) async {
    final m = _Mission();
    await m.pump(t);
    expect(find.text('Pick the meaning'), findsOneWidget);
    expect(find.text('Which word is this sign?'), findsOneWidget);
    expect(find.text('WATCH NOUR'), findsOneWidget);
    // disabled: tapping does nothing
    await tapIt(t, _key('mission-check'));
    expect(m.s.checked, isFalse);
    await tapIt(t, _key('tile-hello'));
    await tapIt(t, _key('mission-check'));
    expect(find.text("Correct! That's Hello."), findsOneWidget);
    expect(find.text('+10 XP'), findsOneWidget);
    expect(
      find.descendant(of: _key('mission-xp'), matching: find.text('+10')),
      findsOneWidget,
    );
    await tapIt(t, _key('mission-check'));
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Sign “Hello” with your glove.'), findsOneWidget);
    // practice shows the word in the caption
    expect(
      find.descendant(
        of: _key('mission-caption'),
        matching: find.text('Hello'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('quiz: a wrong pick names the right sign and replays it at '
      '0.5x', (t) async {
    final m = _Mission();
    await m.pump(t);
    final wrong = (m.s.step! as QuizStep).options.firstWhere(
      (o) => o != 'hello',
    );
    await tapIt(t, _key('tile-$wrong'));
    await tapIt(t, _key('mission-check'));
    expect(
      find.text('Not quite. That sign was Hello. Watch it again.'),
      findsOneWidget,
    );
    expect(m.rig.avatar.plays.last, ('hello', .5, true));
  });

  testWidgets("practice: Sign now counts down; the recognizer's confirm "
      'passes it with its match %', (t) async {
    final m = _Mission();
    await m.pump(t);
    await m.passQuiz();
    await tapIt(t, _key('mission-sign'));
    expect(find.text('Hold the sign… 8'), findsOneWidget);
    expect(find.text('Try 1 of 3'), findsOneWidget);
    expect(m.rig.glove.commands, contains('practice hello'));
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Hold the sign… 5'), findsOneWidget);
    m.rig.feed.confirm('hello', probability: .94);
    await settle(t);
    expect(find.text('Great! 94% match'), findsOneWidget);
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('+15 XP'), findsOneWidget);
    await tapIt(t, _key('mission-next'));
    expect(m.s.step!.label, 'thanks');
  });

  testWidgets('practice: another sign → a neutral hint, never its name; '
      'Try again', (t) async {
    final m = _Mission();
    await m.pump(t);
    await m.passQuiz();
    await tapIt(t, _key('mission-sign'));
    m.rig.feed.confirm('thanks');
    await t.pump(const Duration(milliseconds: 8100));
    await settle(t);
    expect(
      find.text('Not quite. Watch Nour again and try once more.'),
      findsOneWidget,
    );
    expect(find.textContaining('Thank'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Try 2 of 3'), findsOneWidget);
  });

  testWidgets('practice: 3 attempts with nothing → out of tries, Next', (
    t,
  ) async {
    final m = _Mission();
    await m.pump(t);
    await m.passQuiz();
    for (var i = 0; i < 3; i++) {
      await tapIt(t, _key('mission-sign'));
      await t.pump(const Duration(milliseconds: 8100));
      await settle(t);
      if (i < 2) {
        expect(
          find.text("The glove didn't catch the sign. Try again."),
          findsOneWidget,
        );
      }
    }
    expect(
      find.text("Out of tries for “Hello”. Let's move on."),
      findsOneWidget,
    );
    await tapIt(t, _key('mission-next'));
    expect(m.s.step!.label, 'thanks');
  });

  testWidgets('no glove: D10 + D13, Connect → Pair; "Continue without '
      'practice" goes on', (t) async {
    final m = _Mission();
    await m.pump(t, connect: false);
    await m.passQuiz();
    expect(_key('mission-block-noGlove'), findsOneWidget);
    expect(find.text('Glove not connected'), findsOneWidget);
    expect(find.text('Connect your glove to sign.'), findsOneWidget);
    expect(_key('mission-sign'), findsNothing);
    await tapIt(t, _key('mission-connect'));
    expect(find.text('route:/pair'), findsOneWidget);
    m.h.router.pop();
    await settle(t);
    await tapIt(t, _key('mission-skip'));
    expect(m.s.step!.label, 'thanks');
    expect(m.s.step, isA<QuizStep>());
  });

  testWidgets('result: medal, numbers, Back to Learn', (t) async {
    final m = _Mission();
    await m.pump(t);
    while (m.s.result == null) {
      final step = m.s.step!;
      if (step is QuizStep) {
        m.ctl
          ..pick(step.label)
          ..check()
          ..next();
      } else {
        m.ctl.signNow();
        m.rig.feed.confirm(step.label);
        m.ctl.next();
      }
      await t.pump();
    }
    await settle(t);
    expect(find.text('Mission complete!'), findsWidgets);
    expect(find.text("You've unlocked the next module."), findsOneWidget);
    expect(find.text('+125'), findsWidgets);
    expect(find.text('100%'), findsOneWidget);
    expect(_key('mission-medal'), findsOneWidget);
    await tapIt(t, _key('mission-back'));
    expect(find.text('route:/learn'), findsOneWidget);
  });

  testWidgets('TalkBack: close, the step bar, the XP, tiles (selected)', (
    t,
  ) async {
    final sem = t.ensureSemantics();
    final m = _Mission();
    await m.pump(t);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Step 1 of 10'), findsOneWidget);
    expect(find.bySemanticsLabel('+0 XP'), findsOneWidget);
    expect(find.bySemanticsLabel('Replay'), findsOneWidget);
    await tapIt(t, _key('tile-hello'));
    expect(
      t.getSemantics(_key('tile-hello')),
      isSemantics(
        label: 'Hello',
        isButton: true,
        isSelected: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tapIt(t, find.bySemanticsLabel('Close'));
    expect(find.text('route:/learn'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('Arabic: the texts, the words and the labels', (t) async {
    final sem = t.ensureSemantics();
    final m = _Mission();
    await m.pump(t, language: AppLanguage.ar);
    expect(find.text('اختار المعنى'), findsOneWidget);
    expect(find.text('أهلاً'), findsOneWidget);
    expect(find.bySemanticsLabel('اقفل'), findsOneWidget);
    expect(find.bySemanticsLabel('خطوة 1 من 10'), findsOneWidget);
    await m.passQuiz();
    expect(find.text('اعمل إشارة “أهلاً” بالجوانتي.'), findsOneWidget);
    sem.dispose();
  });
}
