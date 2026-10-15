import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/mission_tally.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';

import '../support/fake_glove.dart';
import '../support/fake_learn.dart';
import '../support/fake_talk.dart';

class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// One mission state, fixed.
class _FixedMission extends MissionController {
  new(this.fixed);
  final MissionState fixed;
  @override
  MissionState build(String moduleId) => fixed;
}

final _cast = AvatarCast.parse(File(avatarCastAsset).readAsStringSync());
final _library = AvatarLibrary.parse(
  File('assets/packs/asl/avatar/library.json').readAsStringSync(),
  language: SignLanguage.asl,
);
final LearnCatalog _catalog = learnCatalogFrom(shippedSignCatalogue);
const _today = LocalDay(2026, 10, 14);

AvatarRuntime _runtime() {
  final surface = UnavailableAvatarSurface();
  return AvatarRuntime(
    AvatarController(
      page: surface,
      library: _library,
      libraryUrl: '',
      castUrl: '',
      cast: _cast,
    ),
    surface,
  );
}

/// Gloves made for the current scenario (samples are fed before capture).
final _gloves = <FakeGloveSource>[];

FakeGloveSource _connected() {
  final g = FakeGloveSource();
  g.connect(g.found.single).ignore();
  _gloves.add(g);
  return g;
}

FakeGloveSource _none() {
  final g = FakeGloveSource();
  _gloves.add(g);
  return g;
}

Widget _app(
  AppLanguage language,
  ThemeMode mode, {
  required String route,
  required FakeGloveSource Function() glove,
  List<ActivityEvent> events = const [],
  bool guest = false,
  MissionState? mission,
}) => ProviderScope(
  overrides: [
    appSettingsControllerProvider.overrideWith(
      () => _Fixed(AppSettings(language: language, themeMode: mode)),
    ),
    appRouterProvider.overrideWith(
      (ref) => buildRouter(initialLocation: route),
    ),
    gloveSourceProvider.overrideWithValue(glove()),
    activeGloveKindProvider.overrideWithValue(GloveSourceKind.ble),
    glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
    keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
    avatarCastProvider.overrideWithValue(AsyncData(_cast)),
    avatarRuntimeProvider.overrideWithValue(AsyncData(_runtime())),
    signCatalogueProvider.overrideWithValue(AsyncData(shippedSignCatalogue)),
    learnCatalogProvider.overrideWithValue(AsyncData(_catalog)),
    activityEventsProvider.overrideWithValue(AsyncData(events)),
    learnTodayProvider.overrideWithValue(_today),
    learnGuestProvider.overrideWithValue(guest),
    if (mission != null)
      missionControllerProvider.overrideWith2((_) => _FixedMission(mission)),
    ...TalkFakes().overrides,
  ],
  child: const IsharaApp(),
);

Future<void> _golden(
  String name, {
  required String route,
  FakeGloveSource Function() glove = _connected,
  List<ActivityEvent> events = const [],
  bool guest = false,
  MissionState? mission,
}) => goldenTest(
  '$name: EN / AR x light / dark',
  fileName: 'learn_$name',
  pumpBeforeTest: (t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      // a half-bent hand on the practice panes
      for (final g in _gloves) {
        g.sample(flex: const [1600, 1300, 2000, 2400, 2700]);
      }
      await t.pump(const Duration(milliseconds: 200));
    }
  },
  builder: () {
    _gloves.clear();
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
              child: _app(
                lang,
                mode,
                route: route,
                glove: glove,
                events: events,
                guest: guest,
                mission: mission,
              ),
            ),
      ],
    );
  },
);

var _n = 0;
ActivityEvent _ev(
  ActivityType type,
  String day, {
  String? label,
  String module = 'start',
  bool passed = true,
}) => ActivityEvent(
  id: 'e${_n++}',
  type: type,
  label: label,
  moduleId: module,
  passed: passed,
  prob: type == ActivityType.practice ? .9 : null,
  xp: switch (type) {
    ActivityType.quiz => 10,
    ActivityType.practice => 15,
    ActivityType.missionDone => 0,
  },
  day: LocalDay.tryParse(day)!,
  at: DateTime.utc(2026, 10, 14, 12),
  deviceId: 'dev',
);

/// Start here finished (with a medal) on 12 Oct, two Numbers signs on 13
/// and 14 Oct: 3-day streak, 145 XP, 5 signs learned, 1 medal.
final List<ActivityEvent> _progress = [
  for (final l in ['hello', 'thanks', 'please', 'yes', 'no']) ...[
    _ev(ActivityType.quiz, '2026-10-12', label: l),
    _ev(ActivityType.practice, '2026-10-12', label: l),
  ],
  _ev(ActivityType.missionDone, '2026-10-12'),
  for (final (l, d) in [('one', '2026-10-13'), ('two', '2026-10-14')]) ...[
    _ev(ActivityType.quiz, d, label: l, module: 'numbers'),
    _ev(ActivityType.missionDone, d, module: 'numbers', passed: false),
  ],
];

final MissionPlan _plan = MissionBuilder.forModule(
  _catalog,
  _catalog.module('start')!,
  seed: 3,
);

MissionState _at(
  int index, {
  String? picked,
  bool checked = false,
  PracticeView? practice,
  PracticeBlock? block,
  MissionTally tally = const MissionTally(xp: 10, right: 1, attempted: 1),
  MissionResult? result,
}) => MissionState(
  plan: _plan,
  index: index,
  tally: tally,
  picked: picked,
  checked: checked,
  practice: practice,
  block: block,
  result: result,
);

String _wrongPick() {
  final q = _plan.steps[2] as QuizStep;
  return q.options.firstWhere((o) => o != q.label);
}

Future<void> main() async {
  // Learn home
  await _golden('new_guest', route: AppRoutes.learn, guest: true);
  await _golden('progress', route: AppRoutes.learn, events: _progress);
  await _golden(
    'daily_done',
    route: AppRoutes.learn,
    events: [
      ..._progress,
      _ev(ActivityType.missionDone, '2026-10-14', module: LearnCatalog.dailyId),
    ],
  );

  final mission = AppRoutes.mission('start');
  // pick the meaning (thanks: step 2)
  await _golden(
    'quiz_idle',
    route: mission,
    mission: _at(2, tally: const MissionTally(xp: 25, right: 2, attempted: 2)),
  );
  await _golden(
    'quiz_picked',
    route: mission,
    mission: _at(2, picked: 'thanks'),
  );
  await _golden(
    'quiz_right',
    route: mission,
    mission: _at(
      2,
      picked: 'thanks',
      checked: true,
      tally: const MissionTally(xp: 35, right: 3, attempted: 3),
    ),
  );
  await _golden(
    'quiz_wrong',
    route: mission,
    mission: _at(2, picked: _wrongPick(), checked: true),
  );
  // your turn (thanks: step 3)
  await _golden(
    'practice_idle',
    route: mission,
    mission: _at(
      3,
      practice: const PracticeView(phase: PracticePhase.ready, attempt: 0),
    ),
  );
  await _golden(
    'practice_counting',
    route: mission,
    mission: _at(
      3,
      practice: const PracticeView(
        phase: PracticePhase.counting,
        attempt: 1,
        secondsLeft: 5,
        progress: .4,
      ),
    ),
  );
  await _golden(
    'practice_passed',
    route: mission,
    mission: _at(
      3,
      practice: const PracticeView(
        phase: PracticePhase.passed,
        attempt: 1,
        matchPercent: 87,
      ),
      tally: const MissionTally(xp: 25, right: 2, attempted: 2),
    ),
  );
  await _golden(
    'practice_retry',
    route: mission,
    mission: _at(
      3,
      practice: const PracticeView(
        phase: PracticePhase.retry,
        attempt: 1,
        otherSignSeen: true,
      ),
    ),
  );
  await _golden(
    'practice_failed',
    route: mission,
    mission: _at(
      3,
      practice: const PracticeView(phase: PracticePhase.failed, attempt: 3),
      tally: const MissionTally(xp: 10, right: 1, attempted: 2),
    ),
  );
  await _golden(
    'practice_no_glove',
    route: mission,
    glove: _none,
    mission: _at(
      3,
      practice: const PracticeView(phase: PracticePhase.ready, attempt: 0),
      block: PracticeBlock.noGlove,
    ),
  );
  // the result
  await _golden(
    'result_medal',
    route: mission,
    mission: _at(
      10,
      tally: const MissionTally(xp: 125, right: 10, attempted: 10),
      result: const MissionResult(
        xp: 125,
        bonus: 0,
        accuracyPercent: 100,
        medal: true,
        seconds: 154,
        unlockedNext: true,
        moduleFinished: true,
      ),
    ),
  );
  await _golden(
    'result_no_medal',
    route: mission,
    mission: _at(
      10,
      tally: const MissionTally(xp: 65, right: 5, attempted: 9),
      result: const MissionResult(
        xp: 65,
        bonus: 0,
        accuracyPercent: 56,
        medal: false,
        seconds: 201,
        unlockedNext: false,
        moduleFinished: false,
      ),
    ),
  );
}
