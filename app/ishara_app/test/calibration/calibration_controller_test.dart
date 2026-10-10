import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/features/calibration/application/calibration_controller.dart';

import '../support/fake_glove.dart';

void main() {
  late FakeGloveSource glove;
  late ProviderContainer c;

  Future<void> connected({bool stored = true}) async {
    glove = FakeGloveSource(stored: stored);
    c = ProviderContainer(
      overrides: [gloveSourceProvider.overrideWithValue(glove)],
    );
    await glove.connect(glove.found.single);
    c.listen(calibrationControllerProvider, (_, _) {});
  }

  tearDown(() => c.dispose());

  CalibrationState s() => c.read(calibrationControllerProvider);
  CalibrationController ctl() => c.read(calibrationControllerProvider.notifier);

  test('OPEN, FIST, TURN, then CAL SAVE (BLE-CONTRACT §7)', () async {
    await connected();
    expect(s().step, CalStep.open);
    expect(s().phase, StepPhase.idle);
    expect(s().showFingers, isFalse);
    await ctl().capture();
    expect(s().done, {CalStep.open});
    expect(s().step, CalStep.fist);
    await ctl().capture();
    expect(s().showFingers, isTrue); // Q-K7
    await ctl().capture();
    expect(s().phase, StepPhase.saved);
    expect(glove.commands, [
      'connect g1',
      'CAL OPEN',
      'CAL FIST',
      'CAL TURN',
      'CAL SAVE',
    ]);
  });

  test('step lengths: 2 s, 2 s, 3 s (Q-K4)', () {
    expect(CalibrationState.durationOf(CalStep.open).inSeconds, 2);
    expect(CalibrationState.durationOf(CalStep.fist).inSeconds, 2);
    expect(CalibrationState.durationOf(CalStep.turn).inSeconds, 3);
  });

  test(
    'a FAIL keeps the step, with its reason; Try again repeats it',
    () async {
      await connected();
      glove.stepResults[CalStep.open] = const CalStepResult(
        CalStep.open,
        ok: false,
        reason: 'MOVED',
      );
      await ctl().capture();
      expect(s().phase, StepPhase.failed);
      expect(s().reason, 'MOVED');
      expect(s().step, CalStep.open);
      await ctl().capture();
      expect(s().reason, isNull);
      expect(s().done, {CalStep.open});
    },
  );

  test('#FLEX WEAK fingers are kept and reported', () async {
    await connected();
    await ctl().capture();
    glove.stepResults[CalStep.fist] = const CalStepResult(
      CalStep.fist,
      ok: true,
      weakFingers: [4, 2],
    );
    await ctl().capture();
    expect(s().weakFingers, [2, 4]);
  });

  test('a rejected command (#ERR CAL BUSY) fails the step', () async {
    await connected();
    glove.stepResults.clear();
    glove.saveError = GloveCommandRejectedFailure(
      const ErrorEvent('CAL', 'NVS'),
    );
    for (var i = 0; i < 3; i++) {
      await ctl().capture();
    }
    expect(s().phase, StepPhase.failed);
    expect(s().failure, isA<GloveCommandRejectedFailure>());
    // the glove still has the three steps: saving again works
    await ctl().retrySave();
    expect(s().phase, StepPhase.saved);
  });

  test('Skip only with a stored calibration (Q-K6); it cancels unsaved '
      'steps', () async {
    await connected(stored: false);
    expect(s().canSkip, isFalse);
    expect(await ctl().skip(), isFalse);
    c.dispose();
    await connected();
    expect(s().canSkip, isTrue);
    await ctl().capture();
    expect(await ctl().skip(), isTrue);
    expect(glove.commands.last, 'CAL CANCEL');
  });

  test(
    'leaving before anything ran sends nothing; after a step it cancels',
    () async {
      await connected();
      await ctl().leave();
      expect(glove.commands, ['connect g1']);
      await ctl().capture();
      await ctl().leave();
      expect(glove.commands.last, 'CAL CANCEL');
    },
  );

  test('the link drops: failed, not connected', () async {
    await connected();
    glove.dropLink();
    expect(s().connected, isFalse);
    expect(s().phase, StepPhase.failed);
    expect(s().failure, isA<GloveDisconnectedFailure>());
  });

  test(
    'live hand: samples feed it; bars come from the captured steps',
    () async {
      await connected();
      glove.stepTime = const Duration(milliseconds: 10);
      final run = ctl().capture();
      for (var i = 0; i < 5; i++) {
        glove.sample(flex: const [1000, 1000, 1000, 1000, 1000]);
      }
      await run;
      final run2 = ctl().capture();
      for (var i = 0; i < 5; i++) {
        glove.sample(flex: const [3000, 3000, 3000, 3000, 2000]);
      }
      await run2;
      glove.sample(flex: const [2000, 2000, 2000, 2000, 1500]);
      expect(ctl().hand.fingers, [.5, .5, .5, .5, .5]);
      expect(ctl().hand.still, isTrue);
      expect(s().phase, isNot(StepPhase.failed));
      expect(glove.status.phase, GlovePhase.ready);
    },
  );

  test('a drop during the pause after a step stays a failure', () async {
    await connected();
    final run = ctl().capture();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    glove.dropLink(); // inside the 0.75 s pause
    await run;
    expect(s().phase, StepPhase.failed);
    expect(s().failure, isA<GloveDisconnectedFailure>());
  });

  test('opened with no glove: failed, disconnected', () async {
    glove = FakeGloveSource();
    c = ProviderContainer(
      overrides: [gloveSourceProvider.overrideWithValue(glove)],
    )..listen(calibrationControllerProvider, (_, _) {});
    expect(s().connected, isFalse);
    expect(s().phase, StepPhase.failed);
    expect(s().failure, isA<GloveDisconnectedFailure>());
  });

  test("step 6 review: after Save the bars use the glove's #CAL", () async {
    await connected();
    // the phone's captures: open 1500, fist 2500 on every finger
    final open = ctl().capture();
    glove.sample(flex: const [1500, 1500, 1500, 1500, 1500]);
    await open;
    final fist = ctl().capture();
    glove.sample(flex: const [2500, 2500, 2500, 2500, 2500]);
    await fist;
    glove.sample(flex: const [2500, 2500, 2500, 2500, 2500]);
    expect(ctl().hand.fingers, List.filled(5, 1)); // the phone's references
    await ctl().capture(); // TURN, then CAL SAVE
    expect(s().phase, StepPhase.saved);
    // the glove's #CAL: open 1000, fist 3000 -> 2500 is 75 %
    glove.sample(flex: const [2500, 2500, 2500, 2500, 2500]);
    expect(ctl().hand.fingers, List.filled(5, .75));
  });
}
