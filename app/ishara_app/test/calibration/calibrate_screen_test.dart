import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/features/calibration/presentation/calibrate_screen.dart';

import '../support/fake_glove.dart';
import '../support/screen_harness.dart';

Future<Harness> pumpCal(WidgetTester t, {bool stored = true}) async {
  final glove = FakeGloveSource(stored: stored);
  await glove.connect(glove.found.single);
  return await pumpScreen(
    t,
    const CalibrateScreen(),
    harness: Harness(glove: glove),
  );
}

void main() {
  testWidgets('step 1: eyebrow, title, lead, bars hidden (Q-K7)', (t) async {
    await pumpCal(t);
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    expect(find.text('Open your hand'), findsOneWidget);
    expect(
      find.text('Finger bars appear after Open and Fist.'),
      findsOneWidget,
    );
    expect(find.text('Start capture'), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-skip')), findsOneWidget);
  });

  testWidgets('hold-still indicator follows the gyro (Q-K7)', (t) async {
    final h = await pumpCal(t);
    for (var i = 0; i < 20; i++) {
      h.glove.sample();
    }
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Hand still'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      h.glove.sample(gx: i.isEven ? 900 : -900);
    }
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Hand moving'), findsOneWidget);
  });

  testWidgets('capture counts down, then the next step', (t) async {
    final h = await pumpCal(t);
    h.glove.stepTime = const Duration(seconds: 2);
    await t.ensureVisible(find.byKey(const ValueKey('cal-cta')));
    await t.tap(find.byKey(const ValueKey('cal-cta')));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Hold still… 2'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1500)); // 2.1 s: done
    await t.pump();
    expect(find.text('Captured ✓'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Make a fist'), findsOneWidget);
  });

  testWidgets('MOVED: explained, Try again repeats the step', (t) async {
    final h = await pumpCal(t);
    h.glove.stepResults[CalStep.open] = const CalStepResult(
      CalStep.open,
      ok: false,
      reason: 'MOVED',
    );
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    expect(find.text('Your hand moved'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    await t.pump(const Duration(milliseconds: 800));
    expect(h.glove.commands.where((c) => c == 'CAL OPEN'), hasLength(2));
  });

  testWidgets('RANGE on TURN, weak finger, then save → Ready', (t) async {
    final h = await pumpCal(t);
    h.glove.stepResults[CalStep.fist] = const CalStepResult(
      CalStep.fist,
      ok: true,
      weakFingers: [4],
    );
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    await t.pump(const Duration(milliseconds: 800));
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Weak finger sensor'), findsOneWidget);
    expect(find.textContaining('Pinky:'), findsOneWidget);
    expect(find.text('Turn your wrist'), findsOneWidget);
    expect(find.textContaining('for 3 seconds'), findsOneWidget); // Q-K4
    h.glove.stepResults[CalStep.turn] = const CalStepResult(
      CalStep.turn,
      ok: false,
      reason: 'RANGE',
    );
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    expect(find.text('Turn your wrist further'), findsOneWidget);
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    await t.pump(const Duration(milliseconds: 800));
    await settle(t);
    expect(h.glove.commands.last, 'CAL SAVE');
    expect(find.text('route:/ready'), findsOneWidget);
  });

  testWidgets('no stored calibration: Skip hidden, with the reason (Q-K6)', (
    t,
  ) async {
    await pumpCal(t, stored: false);
    expect(find.byKey(const ValueKey('cal-skip')), findsNothing);
    expect(find.byKey(const ValueKey('cal-skip-hidden')), findsOneWidget);
  });

  testWidgets('Skip → Ready (skipped)', (t) async {
    await pumpCal(t);
    await tapIt(t, find.byKey(const ValueKey('cal-skip')));
    expect(find.text('route:/ready?skipped=1'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('the glove disconnects: explained, Pair again', (t) async {
    final h = await pumpCal(t);
    h.glove.dropLink();
    await settle(t);
    expect(find.text('The glove disconnected'), findsOneWidget);
    expect(find.text('Pair again'), findsOneWidget);
    expect(h.glove.status.phase, GlovePhase.idle);
  });

  testWidgets('opened with no glove: explained; Pair again opens Pair', (
    t,
  ) async {
    await pumpScreen(t, const CalibrateScreen());
    expect(find.text('The glove disconnected'), findsOneWidget);
    await tapIt(t, find.byKey(const ValueKey('cal-cta')));
    expect(find.text('route:/pair'), findsOneWidget);
  });
}
