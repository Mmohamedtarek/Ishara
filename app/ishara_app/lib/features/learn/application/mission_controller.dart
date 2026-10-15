import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/device/device_id.dart';
import 'package:ishara_app/core/device/haptics.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/learn_progress.dart';
import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/mission_tally.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';
import 'package:ishara_app/features/pair/application/reconnect.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mission_controller.g.dart';

/// Why the glove can't be used for a practice step (S8-1), with the step 6
/// / 7 texts and actions.
enum PracticeBlock {
  /// No glove connected (D13, Connect → Pair).
  noGlove,

  /// `#CAL NONE` (D14, Calibrate now).
  notCalibrated,

  /// One automatic reconnect after a drop is running (D11).
  reconnecting,

  /// `#MPU FAIL` (step 6 texts, Connect → Pair).
  mpuFail,

  /// The recognizer failed (D15).
  stopped,
}

/// A practice step as the screen shows it.
@immutable
class PracticeView {
  const new({
    required this.phase,
    required this.attempt,
    this.secondsLeft = 0,
    this.progress = 0,
    this.matchPercent,
    this.otherSignSeen = false,
  });

  final PracticePhase phase;

  /// Attempts used (1-based while counting).
  final int attempt;
  int get attempts => LearnRules.practiceAttempts;

  /// Whole seconds left in the window (prototype "Hold the sign… 3").
  final int secondsLeft;

  /// 0 → 1 across the window (the button's fill).
  final double progress;

  /// Q-L4, once passed.
  final int? matchPercent;

  /// Another sign was emitted in the last window (neutral hint).
  final bool otherSignSeen;
}

/// The result screen.
@immutable
class MissionResult {
  const new({
    required this.xp,
    required this.bonus,
    required this.accuracyPercent,
    required this.medal,
    required this.seconds,
    required this.unlockedNext,
    required this.moduleFinished,
  });

  /// XP of the mission, the daily bonus included.
  final int xp;

  /// The daily challenge's +30 (0 otherwise, S8-4).
  final int bonus;
  final int accuracyPercent;
  final bool medal;
  final int seconds;

  /// This mission unlocked a module.
  final bool unlockedNext;

  /// A module mission whose module is now finished (all signs passed).
  final bool moduleFinished;
}

@immutable
class MissionState {
  const new({
    this.plan,
    this.index = 0,
    this.tally = const MissionTally(),
    this.picked,
    this.checked = false,
    this.practice,
    this.block,
    this.result,
    this.unavailable = false,
  });

  /// Null while loading.
  final MissionPlan? plan;
  final int index;
  final MissionTally tally;

  /// Quiz: the tile picked, and whether "Check" was pressed.
  final String? picked;
  final bool checked;

  /// The current practice step, if it is one.
  final PracticeView? practice;

  /// The glove can't be used now (only shown on a practice step).
  final PracticeBlock? block;

  /// Set when the mission is over.
  final MissionResult? result;

  /// The module doesn't exist or is locked: the screen goes back.
  final bool unavailable;

  MissionStep? get step {
    final p = plan;
    if (p == null || result != null || index >= p.steps.length) return null;
    return p.steps[index];
  }

  /// The quiz answer was right (after Check).
  bool get correct => checked && picked == step?.label;

  /// XP shown in the top bar.
  int get xp => result?.xp ?? tally.xp;

  MissionState copyWith({
    MissionPlan? plan,
    int? index,
    MissionTally? tally,
    String? picked,
    bool clearPicked = false,
    bool? checked,
    PracticeView? practice,
    bool clearPractice = false,
    PracticeBlock? block,
    bool clearBlock = false,
    MissionResult? result,
    bool? unavailable,
  }) => MissionState(
    plan: plan ?? this.plan,
    index: index ?? this.index,
    tally: tally ?? this.tally,
    picked: clearPicked ? null : picked ?? this.picked,
    checked: checked ?? this.checked,
    practice: clearPractice ? null : practice ?? this.practice,
    block: clearBlock ? null : block ?? this.block,
    result: result ?? this.result,
    unavailable: unavailable ?? this.unavailable,
  );
}

/// Seeds the quiz tiles of a module mission (tests fix it).
@riverpod
int missionSeed(Ref ref) => Random().nextInt(1 << 31);

/// One mission (prototype `startMission` / `renderMissionStep` /
/// `renderMissionDone`), per module id or `daily`.
///
/// It is the only reader of recognition events while a practice window is
/// open and the mission is on screen; Talk ignores events while it is
/// hidden (DECISIONS 2026-10-13), and a mission covers it.
@riverpod
class MissionController extends _$MissionController {
  static final _log = Log('learn');
  static const _tick = Duration(milliseconds: 100);

  late LearnCatalog _catalog;
  PracticeCheck? _check;
  Timer? _timer;
  final _subs = <StreamSubscription<Object?>>[];
  final Stopwatch _time = clock.stopwatch();
  bool _visible = true;
  bool _wasReady = false;
  bool _reconnecting = false;
  bool _recognitionStopped = false;

  /// Unlocks when the mission started (to tell if it unlocked one).
  List<ModuleProgress> _before = const [];

  /// The day the plan was made for: a daily challenge started before
  /// midnight and finished after it is still that day's challenge.
  late LocalDay _planDay;

  GloveSource get _glove => ref.read(gloveSourceProvider);

  @override
  MissionState build(String moduleId) {
    ref
      ..onDispose(() {
        _timer?.cancel();
        // the mission's looping sign must not follow the user to Talk
        _playedOn?.stop();
        for (final s in _subs) {
          unawaited(s.cancel());
        }
        _subs.clear();
      })
      ..listen(gloveStatusProvider, (_, next) {
        if (next.value case final s?) _onGlove(s);
      })
      ..listen(recognitionFeedProvider, (_, next) {
        if (next.value case final feed?) _subscribe(feed);
      }, fireImmediately: true)
      // the user changed the speed: the step's sign loops at the new one
      // (not a wrong answer's 0.5x replay)
      ..listen(signSpeedProvider, (_, _) {
        final step = state.step;
        if (step is PracticeStep || (step is QuizStep && !state.checked)) {
          _demo();
        }
      });
    _wasReady = _glove.status.phase == GlovePhase.ready;
    unawaited(_load(moduleId));
    return const MissionState();
  }

  Future<void> _load(String id) async {
    final LearnCatalog catalog;
    final List<ActivityEvent> events;
    try {
      catalog = await ref.read(learnCatalogProvider.future);
      events = ref.read(activityRepositoryProvider).events;
    } on Object catch (e, st) {
      _log.warn('mission_load_failed', {'error': '$e', 'stack': '$st'});
      if (ref.mounted) state = state.copyWith(unavailable: true);
      return;
    }
    if (!ref.mounted) return;
    _catalog = catalog;
    final today = _planDay = LocalDay.of(clock.now());
    final progress = LearnProgress.compute(catalog, events, today);
    _before = progress.modules;
    final MissionPlan plan;
    if (id == LearnCatalog.dailyId) {
      plan = MissionBuilder.daily(catalog, progress.dailyPool, today);
    } else {
      final m = progress.module(id);
      if (m == null || !m.unlocked) {
        state = state.copyWith(unavailable: true);
        return;
      }
      plan = MissionBuilder.forModule(
        catalog,
        m.module,
        seed: ref.read(missionSeedProvider),
      );
    }
    if (plan.steps.isEmpty) {
      state = state.copyWith(unavailable: true);
      return;
    }
    _time.start();
    state = state.copyWith(plan: plan);
    _refreshBlock();
    _enterStep();
  }

  void _subscribe(RecognitionFeed feed) {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs
      ..clear()
      ..add(feed.events.listen(_onEvent))
      ..add(
        feed.errors.listen((f) {
          _log.failure('recognition_failed', f);
          _recognitionStopped = true;
          _cancelWindow();
          _refreshBlock();
        }),
      );
  }

  // ---- the screen ----

  /// The mission screen is on stage (not covered, not leaving). Hidden, an
  /// open window is cancelled (not counted) and events are ignored.
  void setVisible({required bool visible}) {
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) {
      _cancelWindow();
    } else {
      // hiding paused the avatar, which ended the step's loop
      _demo();
    }
  }

  /// The app came back to the foreground: the avatar was paused (its loop
  /// ended), so the step's sign starts again.
  void resumed() {
    if (_visible) _demo();
  }

  // ---- quiz ----

  void pick(String label) {
    final step = state.step;
    if (step is! QuizStep || state.checked || !step.options.contains(label)) {
      return;
    }
    state = state.copyWith(picked: label);
  }

  /// "Check": right → +10 XP; wrong → the right tile is marked and the sign
  /// replays at 0.5×.
  void check() {
    final step = state.step;
    final picked = state.picked;
    if (step is! QuizStep || picked == null || state.checked) return;
    final right = picked == step.label;
    _logStep(ActivityType.quiz, step.label, passed: right);
    state = state.copyWith(
      checked: true,
      tally: state.tally.add(
        right ? StepOutcome.right : StepOutcome.wrong,
        practice: false,
      ),
    );
    if (!right) {
      _play(step.label, speed: LearnRules.wrongReplaySpeed, loop: true);
    }
  }

  // ---- practice ----

  /// "Sign now" / "Try again": opens the 8 s window and cues the glove
  /// (the mock plays `practice/<label>.csv`; the real glove ignores it).
  void signNow() {
    final check = _check;
    if (check == null || !check.canStart || state.block != null) return;
    check.start(clock.now());
    _glove.cuePractice(check.label);
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());
    _publish();
  }

  /// Connect / Calibrate now from this step (S8-8): the user comes back to
  /// the same step with its attempts reset.
  void leaveForGlove() {
    final check = _check;
    if (check == null ||
        check.phase == PracticePhase.passed ||
        check.phase == PracticePhase.failed) {
      return;
    }
    _timer?.cancel();
    _check = PracticeCheck(check.label);
    _publish();
  }

  /// S8-1: "Continue without practice" while the glove can't be used. No
  /// XP, the sign isn't learned, left out of accuracy.
  void skipPractice() {
    final check = _check;
    if (check == null ||
        state.block == null ||
        check.phase == PracticePhase.passed ||
        check.phase == PracticePhase.failed) {
      return;
    }
    _cancelWindow();
    state = state.copyWith(
      tally: state.tally.add(StepOutcome.skipped, practice: true),
    );
    _advance();
  }

  void _onTick() {
    final check = _check;
    if (check == null) return;
    check.onTimeout(clock.now());
    if (check.phase != PracticePhase.counting) {
      _timer?.cancel();
      if (check.phase == PracticePhase.failed) _practiceEnded(passed: false);
      _publish();
      return;
    }
    // the screen animates the fill itself: publish whole seconds only
    final left = (check.remaining(clock.now()).inMilliseconds / 1000).ceil();
    if (left != state.practice?.secondsLeft) _publish();
  }

  void _onEvent(RecognitionEvent e) {
    final check = _check;
    if (!_visible || check == null || check.phase != PracticePhase.counting) {
      return;
    }
    final passed = check.onEvent(
      e.label,
      fires: e.speaks,
      probability: e.probability,
      at: clock.now(),
    );
    if (passed) {
      _timer?.cancel();
      _practiceEnded(passed: true);
      ref.read(vibrateProvider).short(); // S9-1
    }
    _publish();
  }

  void _practiceEnded({required bool passed}) {
    final check = _check!;
    _logStep(
      ActivityType.practice,
      check.label,
      passed: passed,
      prob: passed ? check.probability : null,
    );
    state = state.copyWith(
      tally: state.tally.add(
        passed ? StepOutcome.right : StepOutcome.wrong,
        practice: true,
      ),
    );
  }

  /// The window stops without counting the attempt (glove lost, hidden).
  void _cancelWindow() {
    final check = _check;
    if (check == null || check.phase != PracticePhase.counting) return;
    _timer?.cancel();
    check.cancelAttempt();
    _publish();
  }

  void _publish() {
    final check = _check;
    if (check == null || !ref.mounted) return;
    final now = clock.now();
    final left = check.remaining(now);
    state = state.copyWith(
      practice: PracticeView(
        phase: check.phase,
        attempt: check.attempt,
        secondsLeft: (left.inMilliseconds / 1000).ceil(),
        progress: check.phase == PracticePhase.counting
            ? 1 - left.inMilliseconds / check.window.inMilliseconds
            : 0,
        matchPercent: check.matchPercent,
        otherSignSeen: check.otherSignSeen,
      ),
    );
  }

  // ---- the glove (S8-1) ----

  void _onGlove(GloveStatus s) {
    final ready = s.phase == GlovePhase.ready;
    if (_wasReady && !ready) {
      _cancelWindow();
      // the link dropped (not a disconnect the user asked for): one try,
      // shared with Talk's
      if (s.phase == GlovePhase.idle && s.failure != null) {
        unawaited(_reconnect());
      }
    }
    if (ready && !_wasReady) _recognitionStopped = false;
    _wasReady = ready;
    _refreshBlock();
  }

  Future<void> _reconnect() async {
    _reconnecting = true;
    _refreshBlock();
    try {
      await reconnectToPairedGlove(ref);
    } finally {
      _reconnecting = false;
      if (ref.mounted) _refreshBlock();
    }
  }

  void _refreshBlock() {
    if (!ref.mounted) return;
    final b = _blockFor(_glove.status);
    state = b == null
        ? state.copyWith(clearBlock: true)
        : state.copyWith(block: b);
  }

  PracticeBlock? _blockFor(GloveStatus s) {
    if (s.mpuFail) return PracticeBlock.mpuFail;
    if (s.phase == GlovePhase.ready) {
      if (_recognitionStopped) return PracticeBlock.stopped;
      return s.storedCalibration == StoredCalibration.none
          ? PracticeBlock.notCalibrated
          : null;
    }
    if (_reconnecting || s.phase != GlovePhase.idle) {
      return PracticeBlock.reconnecting;
    }
    return PracticeBlock.noGlove;
  }

  // ---- steps ----

  /// "Next" after a checked quiz or a finished practice step.
  void next() {
    final step = state.step;
    final done = switch (step) {
      QuizStep() => state.checked,
      PracticeStep() =>
        _check?.phase == PracticePhase.passed ||
            _check?.phase == PracticePhase.failed,
      null => false,
    };
    if (done) _advance();
  }

  void _advance() {
    final plan = state.plan!;
    final index = state.index + 1;
    state = state.copyWith(
      index: index,
      clearPicked: true,
      checked: false,
      clearPractice: true,
    );
    if (index >= plan.steps.length) {
      _finish();
    } else {
      _enterStep();
    }
  }

  void _enterStep() {
    _timer?.cancel();
    final step = state.step;
    if (step is PracticeStep) {
      _check = PracticeCheck(step.label);
      _publish();
    } else {
      _check = null;
    }
    _demo();
  }

  /// "Replay" on the avatar card: the step's sign again.
  void replay() => _demo();

  void _demo() {
    final step = state.step;
    if (step == null) return;
    final speed = switch (step) {
      QuizStep() when state.checked && !state.correct =>
        LearnRules.wrongReplaySpeed,
      QuizStep() => ref.read(signSpeedProvider),
      // user, step 8 review: never faster than a slower speed they chose
      PracticeStep() => min(
        LearnRules.practiceDemoSpeed,
        ref.read(signSpeedProvider),
      ),
    };
    _play(step.label, speed: speed, loop: true);
  }

  void _finish() {
    _timer?.cancel();
    _time.stop();
    final plan = state.plan!;
    final repo = ref.read(activityRepositoryProvider);
    final today = plan.isDaily ? _planDay : LocalDay.of(clock.now());
    final progress = LearnProgress.compute(_catalog, repo.events, today);
    final bonus = plan.isDaily && !progress.dailyDoneToday
        ? LearnRules.dailyBonusXp
        : 0;
    final tally = state.tally;
    _append(
      ActivityType.missionDone,
      null,
      passed: tally.medal,
      prob: tally.accuracy,
      xp: bonus,
      day: plan.isDaily ? _planDay : null,
    );
    final after = progress.modules;
    final unlocked = [
      for (final (i, m) in after.indexed)
        if (m.unlocked && !_before[i].unlocked) m.module.id,
    ];
    state = state.copyWith(
      result: MissionResult(
        xp: tally.xp + bonus,
        bonus: bonus,
        accuracyPercent: tally.accuracyPercent,
        medal: tally.medal,
        seconds: _time.elapsed.inSeconds,
        unlockedNext: unlocked.isNotEmpty,
        moduleFinished: progress.module(plan.moduleId)?.finished ?? false,
      ),
    );
    // the result has no caption: the avatar gets its full height back
    _avatar?.reframe();
    final celebrate = _avatar?.library.celebrate;
    if (celebrate != null) _play(celebrate, speed: 1, loop: false);
  }

  // ---- log and avatar ----

  void _logStep(
    ActivityType type,
    String label, {
    required bool passed,
    double? prob,
  }) => _append(
    type,
    label,
    passed: passed,
    prob: prob,
    xp: LearnRules.stepXp(
      practice: type == ActivityType.practice,
      passed: passed,
    ),
  );

  void _append(
    ActivityType type,
    String? label, {
    required bool passed,
    required int xp,
    double? prob,
    LocalDay? day,
  }) {
    final now = clock.now();
    final event = ActivityEvent(
      id: _newId(),
      type: type,
      label: label,
      moduleId: state.plan!.moduleId,
      passed: passed,
      prob: prob,
      xp: xp,
      day: day ?? LocalDay.of(now),
      at: now.toUtc(),
      deviceId: ref.read(deviceIdProvider),
    );
    unawaited(
      ref.read(activityRepositoryProvider).append(event).catchError((
        Object e,
        StackTrace st,
      ) {
        _log.warn('log_failed', {'error': '$e'});
      }),
    );
  }

  static final _ids = Random.secure();
  static String _newId() => [
    for (var i = 0; i < 16; i++)
      _ids.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// The avatar this mission played on (stopped when the mission ends).
  AvatarController? _playedOn;

  AvatarController? get _avatar =>
      ref.read(avatarRuntimeProvider).value?.controller;

  void _play(String label, {required double speed, required bool loop}) {
    final avatar = _avatar;
    if (avatar == null) return;
    if (!avatar.library.has(label)) {
      // never another sign in its place (sign rule 7)
      _log.warn('no_animation', {'label': label});
      return;
    }
    _playedOn = avatar;
    avatar.play(label, speed: speed, loop: loop);
  }
}
