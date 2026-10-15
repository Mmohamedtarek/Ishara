// On the emulator or a phone, with the mock glove (debug build default):
//   flutter test integration_test/learn_test.dart -d emulator-5554
// For the review video, paced (pause on each screen, in ms):
//   flutter test integration_test/learn_test.dart -d emulator-5554 \
//     --plain-name "person A" --dart-define=PACE_MS=1200
// A whole "Start here" mission on the real app: the 3D avatar in its
// WebView, the mock glove playing practice/<label>.csv as BLE frames, the
// recognizer (3 models, Decider) in its isolate. Nothing fakes a word.
// Prints LEARN lines for the step record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_events.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_controls.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';

final _pace = Duration(
  milliseconds: int.parse(
    const String.fromEnvironment('PACE_MS', defaultValue: '0'),
  ),
);

/// The real glove, except that "Sign now" for [from] plays [to]'s practice
/// recording (mutation check).
class _SwapPractice implements GloveSource {
  new(this._inner, this.from, this.to);
  final GloveSource _inner;
  final String from;
  final String to;
  @override
  void cuePractice(String label) =>
      _inner.cuePractice(label == from ? to : label);
  @override
  GloveStatus get status => _inner.status;
  @override
  Stream<GloveStatus> get statusChanges => _inner.statusChanges;
  @override
  Stream<List<GloveSample>> get samples => _inner.samples;
  @override
  Stream<GloveEvent> get events => _inner.events;
  @override
  Stream<List<DiscoveredGlove>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _inner.scan(timeout: timeout);
  @override
  Future<void> connect(DiscoveredGlove glove) => _inner.connect(glove);
  @override
  Future<void> disconnect() => _inner.disconnect();
  @override
  Future<GloveCalibration?> readCalibration() => _inner.readCalibration();
  @override
  Future<CalStepResult> calibrate(CalStep step) => _inner.calibrate(step);
  @override
  Future<GloveCalibration> saveCalibration() => _inner.saveCalibration();
  @override
  Future<void> cancelCalibration() => _inner.cancelCalibration();
  @override
  Future<BatteryEvent> readBattery() => _inner.readBattery();
  @override
  Future<void> dispose() => _inner.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> linger(WidgetTester t, [Duration? d]) async {
    final end = DateTime.now().add(d ?? _pace);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> waitUntil(
    WidgetTester t,
    bool Function() done, {
    Duration timeout = const Duration(seconds: 30),
    String what = 'condition',
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) throw TimeoutException(what);
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await waitUntil(t, () => f.evaluate().isNotEmpty, what: key);
    await t.ensureVisible(f);
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(f);
    await t.pump(const Duration(milliseconds: 200));
  }

  Future<void> run(
    WidgetTester t,
    MockPerson person, {
    String? swapFrom,
    String? swapTo,
  }) async {
    final sw = Stopwatch()..start();
    void mark(String what) => debugPrint(
      'LEARN ${person.dir}${swapFrom == null ? '' : ' (swap)'} '
      '${sw.elapsedMilliseconds} ms $what',
    );
    final store = MemoryKeyValueStore({
      'onboarding.done': true,
      'setup.spoken': 'en',
      'setup.role': 'sign',
      'glove.id': 'mock:ishara',
      'glove.name': 'Ishara-M0CK',
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.learn),
          ),
          if (swapFrom != null)
            gloveSourceProvider.overrideWith((ref) {
              final client = GloveClient(ref.watch(mockGloveProvider)!);
              ref.onDispose(client.dispose);
              return _SwapPractice(client, swapFrom, swapTo!);
            }),
        ],
        child: const IsharaApp(),
      ),
    );
    final learn = find.byKey(const ValueKey('screen-learn'));
    await waitUntil(t, () => learn.evaluate().isNotEmpty, what: 'Learn');
    final c = ProviderScope.containerOf(t.element(learn));
    // connect the mock glove (as Pair would), the person's own data
    final source = c.read(gloveSourceProvider);
    final found = await source.scan().firstWhere((l) => l.isNotEmpty);
    await source.connect(found.first);
    await c.read(mockControlsProvider)!.setPerson(person);
    await waitUntil(
      t,
      () => source.status.phase == GlovePhase.ready,
      what: 'glove ready',
    );
    mark('glove ready');
    // the 3D avatar in its WebView
    final avatar = (await c.read(avatarRuntimeProvider.future)).controller;
    await waitUntil(
      t,
      () => avatar.status.value == AvatarStatus.ready,
      timeout: const Duration(seconds: 90),
      what: 'avatar ready',
    );
    final started = <SignStarted>[];
    final sub = avatar.events.listen((e) {
      if (e is SignStarted) started.add(e);
    });
    mark('avatar ready');
    await linger(t);

    await tapKey(t, 'learn-module-start');
    await waitUntil(
      t,
      () => find.byKey(const ValueKey('screen-mission')).evaluate().isNotEmpty,
      what: 'mission',
    );
    MissionState s() => c.read(missionControllerProvider('start'));
    await waitUntil(t, () => s().plan != null, what: 'plan');
    var wrongDone = false;
    var dropDone = false;
    final outcomes = <String, PracticePhase>{};
    while (s().result == null) {
      final step = s().step!;
      if (step is QuizStep) {
        await waitUntil(
          t,
          () => started.any((e) => e.label == step.label),
          what: 'avatar plays ${step.label}',
        );
        final normal = started.lastWhere((e) => e.label == step.label);
        await linger(t);
        if (!wrongDone) {
          // one deliberate wrong answer: the right tile is shown and the
          // sign replays at 0.5x (twice as long)
          final wrong = step.options.firstWhere((o) => o != step.label);
          await tapKey(t, 'tile-$wrong');
          final before = started.length;
          await tapKey(t, 'mission-check');
          // the 1x loop may start once more before the replay command
          // arrives: look for the replay among the next starts
          double ratioOf(SignStarted e) =>
              e.duration.inMicroseconds / normal.duration.inMicroseconds;
          bool slow(SignStarted e) =>
              e.label == step.label && (ratioOf(e) - 2).abs() < .02;
          await waitUntil(
            t,
            () => started.skip(before).any(slow),
            timeout: const Duration(seconds: 10),
            what: 'replay at 0.5x',
          );
          final ratio = ratioOf(started.skip(before).firstWhere(slow));
          expect(
            find.text('Not quite. That sign was Hello. Watch it again.'),
            findsOneWidget,
          );
          mark('wrong pick ${step.label}: replay x$ratio slower');
          wrongDone = true;
        } else {
          await tapKey(t, 'tile-${step.label}');
          await tapKey(t, 'mission-check');
          mark('quiz ${step.label}: right');
        }
        await linger(t);
        await tapKey(t, 'mission-check'); // Next
        continue;
      }
      if (!dropDone && swapFrom == null) {
        // once: the glove disconnects during practice; Connect → Pair →
        // connected → back on this step with its attempts reset (S8-8)
        await waitUntil(t, () => s().practice != null, what: 'practice step');
        await tapKey(t, 'mission-sign');
        await linger(t, const Duration(milliseconds: 800));
        await source.disconnect();
        await waitUntil(
          t,
          () => s().block == PracticeBlock.noGlove,
          what: 'no glove',
        );
        expect(s().practice!.attempt, 0, reason: 'attempt not counted');
        mark('practice ${step.label}: glove disconnected');
        await linger(t);
        await tapKey(t, 'mission-connect');
        final connect = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('pair-connect-'),
        );
        await waitUntil(
          t,
          () => connect.evaluate().isNotEmpty,
          what: 'Pair found the glove',
        );
        await linger(t);
        await t.tap(connect.first);
        await waitUntil(
          t,
          () =>
              find.byKey(const ValueKey('screen-pair')).evaluate().isEmpty &&
              s().block == null,
          what: 'back on the practice step',
        );
        expect(s().step!.label, step.label);
        expect(s().practice!.phase, PracticePhase.ready);
        expect(s().practice!.attempt, 0);
        mark('practice ${step.label}: reconnected, back on the step');
        dropDone = true;
      }
      // your turn: "Sign now" plays practice/<label>.csv through the
      // real pipeline
      while (s().practice!.phase == PracticePhase.ready ||
          s().practice!.phase == PracticePhase.retry) {
        await tapKey(t, 'mission-sign');
        await waitUntil(
          t,
          () => s().practice!.phase != PracticePhase.counting,
          timeout: const Duration(seconds: 12),
          what: 'window',
        );
      }
      final p = s().practice!;
      outcomes[step.label] = p.phase;
      mark(
        'practice ${step.label}: ${p.phase.name}, try ${p.attempt}'
        '${p.matchPercent == null ? '' : ', ${p.matchPercent}% match'}',
      );
      await linger(t);
      await tapKey(t, 'mission-next');
    }
    final r = s().result!;
    mark(
      'result: +${r.xp} XP, ${r.accuracyPercent} %, medal ${r.medal}, '
      '${r.seconds} s, unlocked ${r.unlockedNext}',
    );
    await linger(t, _pace * 2);
    if (swapFrom == null) {
      expect(outcomes.values, everyElement(PracticePhase.passed));
      expect(outcomes.keys, ['hello', 'thanks', 'please', 'yes', 'no']);
      // 4 quizzes + 5 practice steps right, 1 quiz wrong
      expect(r.xp, 4 * 10 + 5 * 15);
      expect(r.accuracyPercent, 90);
      expect(r.medal, isTrue);
      expect(r.unlockedNext, isTrue);
      await tapKey(t, 'mission-back');
      await waitUntil(t, () => learn.evaluate().isNotEmpty, what: 'back');
      final progress = await c.read(learnProgressProvider.future);
      expect(progress.xp, 115);
      expect(progress.signsLearned, 5);
      expect(progress.medals, 1);
      expect(progress.module('numbers')!.unlocked, isTrue);
      await linger(t, _pace * 2);
      mark('Learn: ${progress.xp} XP, ${progress.signsLearned} signs');
    } else {
      expect(outcomes[swapFrom], PracticePhase.failed);
      expect(
        {
          for (final e in outcomes.entries)
            if (e.key != swapFrom) e.value,
        },
        {PracticePhase.passed},
      );
    }
    await sub.cancel();
  }

  for (final person in MockPerson.values) {
    testWidgets(
      'person ${person.dir}: a whole "Start here" mission on the '
      'mock glove',
      (t) => run(t, person),
    );
  }

  testWidgets(
    'mutation: "please" plays thanks.csv → that practice step '
    'fails after 3 tries',
    (t) => run(t, MockPerson.a, swapFrom: 'please', swapTo: 'thanks'),
  );
}
