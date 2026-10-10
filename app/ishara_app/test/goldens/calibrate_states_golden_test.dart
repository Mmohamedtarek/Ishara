import 'dart:math' as math;

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

import '../support/fake_glove.dart';

/// Every state of Calibrate, driven through the real flow on a scripted
/// glove (steps take the glove's 2 s / 2 s / 3 s), with live samples: for
/// the side-by-side comparison with the prototype's states.

class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// Hand poses fed as samples.
enum _Pose { open, fist, turned }

void _feed(List<FakeGloveSource> gloves, _Pose pose) {
  for (final g in gloves) {
    switch (pose) {
      case _Pose.open:
        g.sample(flex: const [1000, 1000, 1000, 1000, 1000]);
      case _Pose.fist:
        g.sample(flex: const [3000, 3000, 3000, 3000, 3000]);
      case _Pose.turned:
        g.sample(
          flex: const [1000, 1000, 1000, 1000, 1000],
          ay: (8192 * math.sin(20 * math.pi / 180)).round(),
          az: (8192 * math.cos(20 * math.pi / 180)).round(),
        );
    }
  }
}

/// [ms] of time in 100 ms frames, feeding [pose] each frame.
Future<void> _hold(
  WidgetTester t,
  List<FakeGloveSource> gloves,
  _Pose pose,
  int ms,
) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    _feed(gloves, pose);
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capture(WidgetTester t) async {
  for (final e in find.byKey(const ValueKey('cal-cta')).evaluate().toList()) {
    await t.tap(find.byWidget(e.widget), warnIfMissed: false);
  }
  await t.pump();
}

/// What to do before the picture, from a fresh Calibrate screen.
typedef _Script = Future<void> Function(
  WidgetTester t,
  List<FakeGloveSource> gloves,
);

Future<void> _state(
  String name,
  _Script script, {
  void Function(FakeGloveSource g)? setUp,
  bool stored = true,
}) {
  final gloves = <FakeGloveSource>[];
  return goldenTest(
    'calibrate $name: EN / AR x light / dark',
    fileName: 'calibrate_$name',
    pumpBeforeTest: (t) => t.pump(const Duration(milliseconds: 500)),
    // after the picture: let a running step (and its 0.75 s pause) finish,
    // so no timer is left pending
    whilePerforming: (t) async {
      await script(t, gloves);
      return () => t.pump(const Duration(seconds: 6));
    },
    builder: () {
      gloves.clear();
      return GoldenTestGroup(
        columns: 4,
        children: [
          for (final lang in AppLanguage.values)
            for (final mode in [ThemeMode.light, ThemeMode.dark])
              GoldenTestScenario(
                name: '${lang.name} ${mode.name}',
                constraints: const BoxConstraints.tightFor(
                  width: 390,
                  height: 844,
                ),
                child: Builder(
                  builder: (context) {
                    final g = FakeGloveSource(stored: stored);
                    g.stepTimes.addAll(const {
                      CalStep.open: Duration(seconds: 2),
                      CalStep.fist: Duration(seconds: 2),
                      CalStep.turn: Duration(seconds: 3),
                    });
                    setUp?.call(g);
                    g.connect(g.found.single).ignore();
                    gloves.add(g);
                    return ProviderScope(
                      overrides: [
                        appSettingsControllerProvider.overrideWith(
                          () => _Fixed(
                            AppSettings(language: lang, themeMode: mode),
                          ),
                        ),
                        appRouterProvider.overrideWith(
                          (ref) =>
                              buildRouter(initialLocation: AppRoutes.calibrate),
                        ),
                        gloveSourceProvider.overrideWithValue(g),
                        keyValueStoreProvider.overrideWithValue(
                          MemoryKeyValueStore(),
                        ),
                      ],
                      child: const IsharaApp(),
                    );
                  },
                ),
              ),
        ],
      );
    },
  );
}

// The flow, step by step (each script starts from the screen's first frame).
Future<void> s1Idle(WidgetTester t, List<FakeGloveSource> g) =>
    _hold(t, g, _Pose.open, 600);

Future<void> s1Counting(WidgetTester t, List<FakeGloveSource> g) async {
  await s1Idle(t, g);
  await _capture(t);
  await _hold(t, g, _Pose.open, 1100);
}

Future<void> s1Captured(WidgetTester t, List<FakeGloveSource> g) async {
  await s1Counting(t, g);
  await _hold(t, g, _Pose.open, 1000);
}

Future<void> s2Idle(WidgetTester t, List<FakeGloveSource> g) async {
  await s1Captured(t, g);
  await _hold(t, g, _Pose.open, 800);
}

Future<void> s2Counting(WidgetTester t, List<FakeGloveSource> g) async {
  await s2Idle(t, g);
  await _capture(t);
  await _hold(t, g, _Pose.fist, 1100);
}

Future<void> s2Captured(WidgetTester t, List<FakeGloveSource> g) async {
  await s2Counting(t, g);
  await _hold(t, g, _Pose.fist, 1000);
}

Future<void> s3Idle(WidgetTester t, List<FakeGloveSource> g) async {
  await s2Captured(t, g);
  await _hold(t, g, _Pose.open, 800);
}

Future<void> s3Counting(WidgetTester t, List<FakeGloveSource> g) async {
  await s3Idle(t, g);
  await _capture(t);
  await _hold(t, g, _Pose.turned, 1500);
}

Future<void> s3Captured(WidgetTester t, List<FakeGloveSource> g) async {
  await s3Counting(t, g);
  await _hold(t, g, _Pose.turned, 1600);
}

Future<void> main() async {
  await _state('s1_idle', s1Idle);
  await _state('s1_counting', s1Counting);
  await _state('s1_captured', s1Captured);
  await _state('s2_idle', s2Idle);
  await _state('s2_counting', s2Counting);
  await _state('s2_captured', s2Captured);
  await _state('s3_idle', s3Idle);
  await _state('s3_counting', s3Counting);
  await _state('s3_captured', s3Captured);
  // after TURN: CAL SAVE, then Ready
  await _state('ready', (t, g) async {
    await s3Captured(t, g);
    await _hold(t, g, _Pose.open, 2000);
  });
  // states the prototype lacks
  await _state(
    'fail_moved',
    (t, g) async {
      await s1Idle(t, g);
      await _capture(t);
      await _hold(t, g, _Pose.open, 2200);
    },
    setUp: (g) => g.stepResults[CalStep.open] = const CalStepResult(
      CalStep.open,
      ok: false,
      reason: 'MOVED',
    ),
  );
  await _state(
    'fail_range',
    (t, g) async {
      await s3Idle(t, g);
      await _capture(t);
      await _hold(t, g, _Pose.turned, 3200);
    },
    setUp: (g) => g.stepResults[CalStep.turn] = const CalStepResult(
      CalStep.turn,
      ok: false,
      reason: 'RANGE',
    ),
  );
  await _state(
    'weak_finger',
    s3Idle,
    setUp: (g) => g.stepResults[CalStep.fist] = const CalStepResult(
      CalStep.fist,
      ok: true,
      weakFingers: [4],
    ),
  );
  await _state('no_stored_calibration', s1Idle, stored: false);
  await _state('disconnected', (t, g) async {
    await s1Idle(t, g);
    for (final x in g) {
      x.dropLink();
    }
    await t.pump(const Duration(milliseconds: 300));
  });
}
