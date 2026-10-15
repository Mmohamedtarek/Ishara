import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/device/keep_screen_on.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';

import '../support/fake_glove.dart';
import '../support/fake_learn.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// S8-8: Connect / Calibrate now from a practice step come back to the same
/// step with its attempts reset, not to Ready. Real router, Pair and
/// Calibrate screens; a fake glove.
class _App {
  new(this.glove);

  final FakeGloveSource glove;
  late final rig = LearnRig(glove: glove);
  late WidgetTester t;
  late ProviderContainer c;

  MissionState get s => c.read(missionControllerProvider('start'));

  Future<void> pump(WidgetTester tester, {bool connect = false}) async {
    t = tester;
    rootBundle.clear();
    addTearDown(rootBundle.clear);
    addTearDown(rig.dispose);
    final talk = TalkFakes();
    addTearDown(talk.feed.dispose);
    t.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    if (connect) {
      await t.runAsync(() => glove.connect(glove.found.single));
    }
    final router = buildRouter(initialLocation: AppRoutes.learn);
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(delay: Duration.zero),
          ),
          ...rig.overrides,
          conversationTimeoutProvider.overrideWithValue(
            AsyncData(talk.timeout),
          ),
          textToSpeechProvider.overrideWithValue(talk.tts),
          keepScreenOnProvider.overrideWithValue(talk.screen),
        ],
        child: const IsharaApp(),
      ),
    );
    rig.avatar.loaded();
    await settle(t, n: 10);
    c = ProviderScope.containerOf(t.element(_key('screen-learn')));
    await tapIt(t, _key('learn-module-start'));
    await settle(t, n: 10);
    // the first quiz, then "your turn"
    await tapIt(t, _key('tile-hello'));
    await tapIt(t, _key('mission-check'));
    await tapIt(t, _key('mission-check'));
    expect(s.step, isA<PracticeStep>());
  }

  /// Back on the mission: the same step, attempts reset, usable.
  void expectBackOnStep() {
    expect(_key('screen-mission'), findsOneWidget);
    expect(_key('screen-ready'), findsNothing);
    expect(s.step, isA<PracticeStep>());
    expect(s.step!.label, 'hello');
    expect(s.practice!.phase, PracticePhase.ready);
    expect(s.practice!.attempt, 0);
    expect(s.block, isNull);
  }
}

void main() {
  testWidgets('no glove: Connect → Pair → connected (calibrated) → back to '
      'the same practice step, attempts reset', (t) async {
    final a = _App(FakeGloveSource());
    await a.pump(t);
    expect(a.s.block, PracticeBlock.noGlove);
    await tapIt(t, _key('mission-connect'));
    await settle(t, n: 10);
    expect(_key('screen-pair'), findsOneWidget);
    await tapIt(t, _key('pair-connect-g1'));
    await settle(t, n: 20);
    a.expectBackOnStep();
    expect(a.glove.status.phase, GlovePhase.ready);
  });

  testWidgets('a used attempt is reset after the glove comes back', (t) async {
    final a = _App(FakeGloveSource());
    await a.pump(t, connect: true);
    await tapIt(t, _key('mission-sign'));
    await t.pump(const Duration(milliseconds: 8200));
    await settle(t);
    expect(a.s.practice!.phase, PracticePhase.retry);
    a.glove.dropLink();
    // the automatic reconnect: the fake finds and connects it again; make
    // it fail so the user has to tap Connect
    a.glove.found = const [];
    await settle(t, n: 10);
    expect(a.s.block, PracticeBlock.noGlove);
    a.glove.found = const [
      DiscoveredGlove(id: 'g1', name: 'Ishara-3FA2', rssi: -55),
    ];
    await tapIt(t, _key('mission-connect'));
    await settle(t, n: 10);
    await tapIt(t, _key('pair-connect-g1'));
    await settle(t, n: 20);
    a.expectBackOnStep();
  });

  testWidgets('#CAL NONE: Calibrate now → Calibrate → saved → back to the '
      'same practice step (not Ready)', (t) async {
    final a = _App(FakeGloveSource(stored: false));
    await a.pump(t, connect: true);
    expect(a.s.block, PracticeBlock.notCalibrated);
    await tapIt(t, _key('mission-calibrate'));
    await settle(t, n: 10);
    expect(_key('screen-calibrate'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tapIt(t, _key('cal-cta'));
      await t.pump(const Duration(seconds: 1));
      await settle(t, n: 10);
    }
    await settle(t, n: 20);
    a.expectBackOnStep();
  });

  testWidgets('an uncalibrated glove found by Connect goes on to Calibrate, '
      'then back to the step (two screens)', (t) async {
    final a = _App(FakeGloveSource(stored: false));
    await a.pump(t);
    await tapIt(t, _key('mission-connect'));
    await settle(t, n: 10);
    await tapIt(t, _key('pair-connect-g1'));
    await settle(t, n: 20);
    // not calibrated: Pair stays, "Continue to calibration"
    expect(_key('screen-pair'), findsOneWidget);
    await tapIt(t, _key('pair-cta'));
    await settle(t, n: 10);
    for (var i = 0; i < 3; i++) {
      await tapIt(t, _key('cal-cta'));
      await t.pump(const Duration(seconds: 1));
      await settle(t, n: 10);
    }
    await settle(t, n: 20);
    a.expectBackOnStep();
  });
}
