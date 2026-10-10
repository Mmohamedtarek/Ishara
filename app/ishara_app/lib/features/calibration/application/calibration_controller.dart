import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/live_hand.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calibration_controller.g.dart';

/// Where the current step is.
enum StepPhase {
  /// Waiting for "Start capture".
  idle,

  /// The glove is capturing (2 s, 2 s, 3 s).
  capturing,

  /// `#CALSTEP … OK`; the next step follows (prototype: after 0.75 s).
  captured,

  /// `#CALSTEP … FAIL <reason>`, a rejected or timed-out command, or a lost
  /// connection ([CalibrationState.failure] / [CalibrationState.reason]).
  failed,

  /// After TURN: `CAL SAVE` is running.
  saving,

  /// `#CAL {…}` received: calibration done.
  saved,
}

@immutable
class CalibrationState {
  const new({
    this.step = CalStep.open,
    this.phase = StepPhase.idle,
    this.done = const {},
    this.startedAt,
    this.reason,
    this.failure,
    this.weakFingers = const [],
    this.canSkip = false,
    this.connected = true,
  });

  final CalStep step;
  final StepPhase phase;

  /// Steps that succeeded in this run.
  final Set<CalStep> done;

  /// When the current capture started (the screen draws the countdown).
  final DateTime? startedAt;

  /// The glove's FAIL reason: `MOVED`, `RANGE`, `MPU`, `CANCELLED`.
  final String? reason;

  /// Rejected command (`#ERR CAL …`), timeout or lost connection.
  final GloveFailure? failure;

  /// `#FLEX WEAK <i>` fingers (sensor problem), reported once OPEN and FIST
  /// are done.
  final List<int> weakFingers;

  /// Q-K6: Skip only when the glove has a stored `#CAL {…}`.
  final bool canSkip;
  final bool connected;

  /// The step's length on the glove (BLE-CONTRACT §7; TURN 3 s, Q-K4).
  static Duration durationOf(CalStep s) =>
      Duration(seconds: s == CalStep.turn ? 3 : 2);

  /// Q-K7: finger bars only once OPEN and FIST are done.
  bool get showFingers =>
      done.contains(CalStep.open) && done.contains(CalStep.fist);

  CalibrationState copyWith({
    CalStep? step,
    StepPhase? phase,
    Set<CalStep>? done,
    DateTime? startedAt,
    String? reason,
    GloveFailure? failure,
    List<int>? weakFingers,
    bool? canSkip,
    bool? connected,
    bool clearError = false,
  }) => CalibrationState(
    step: step ?? this.step,
    phase: phase ?? this.phase,
    done: done ?? this.done,
    startedAt: startedAt ?? this.startedAt,
    reason: clearError ? null : reason ?? this.reason,
    failure: clearError ? null : failure ?? this.failure,
    weakFingers: weakFingers ?? this.weakFingers,
    canSkip: canSkip ?? this.canSkip,
    connected: connected ?? this.connected,
  );
}

/// Runs the calibration flow (BLE-CONTRACT §7) and feeds the live hand.
@riverpod
class CalibrationController extends _$CalibrationController {
  static final _log = Log('calibration');

  /// The live view (finger bars, hold-still, rotation) from raw samples.
  final hand = LiveHand();

  /// Bumped when samples arrive: the live view redraws on it.
  final ValueNotifier<int> samplesSeen = ValueNotifier(0);
  StepCapture? _capture;
  bool _savedOrSkipped = false;

  GloveSource get _glove => ref.read(gloveSourceProvider);

  @override
  CalibrationState build() {
    final glove = ref.read(gloveSourceProvider);
    final subs = <StreamSubscription<Object?>>[
      glove.samples.listen(_onSamples),
      glove.statusChanges.listen(_onStatus),
    ];
    ref.onDispose(() {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    });
    final s = glove.status;
    ref.onDispose(samplesSeen.dispose);
    final connected = s.phase == GlovePhase.ready;
    // Opened without a connected glove (Settings, Ready): say so at once.
    return CalibrationState(
      canSkip: s.storedCalibration == StoredCalibration.present,
      connected: connected,
      phase: connected ? StepPhase.idle : StepPhase.failed,
      failure: connected ? null : const GloveDisconnectedFailure(),
    );
  }

  void _onSamples(List<GloveSample> batch) {
    for (final s in batch) {
      hand.add(s);
      _capture?.add(s);
    }
    samplesSeen.value++;
  }

  void _onStatus(GloveStatus s) {
    if (!ref.mounted) return;
    final connected = s.phase == GlovePhase.ready;
    state = state.copyWith(
      connected: connected,
      canSkip: s.storedCalibration == StoredCalibration.present,
    );
    if (!connected &&
        state.phase != StepPhase.saved &&
        state.phase != StepPhase.failed) {
      state = state.copyWith(
        phase: StepPhase.failed,
        failure: s.failure ?? const GloveDisconnectedFailure(),
      );
    }
  }

  /// "Start capture" (or "Try again" after a failure) for the current step.
  Future<void> capture() async {
    if (state.phase == StepPhase.capturing || state.phase == StepPhase.saving) {
      return;
    }
    final step = state.step;
    if (step == CalStep.open) hand.resetReferences();
    final cap = _capture = StepCapture(hand);
    state = state.copyWith(
      phase: StepPhase.capturing,
      startedAt: clock.now(),
      clearError: true,
    );
    final CalStepResult r;
    try {
      r = await _glove.calibrate(step);
    } on GloveFailure catch (f) {
      _capture = null;
      if (!ref.mounted) return;
      _log.warn('step_error', {'step': step.wire, 'kind': f.kind});
      state = state.copyWith(phase: StepPhase.failed, failure: f);
      return;
    }
    _capture = null;
    if (!ref.mounted) return;
    final weak = {...state.weakFingers, ...r.weakFingers}.toList()..sort();
    if (!r.ok) {
      _log.info('step_fail', {'step': step.wire, 'reason': r.reason});
      state = state.copyWith(
        phase: StepPhase.failed,
        reason: r.reason,
        weakFingers: weak,
      );
      return;
    }
    switch (step) {
      case CalStep.open:
        cap.applyAsOpen();
      case CalStep.fist:
        cap.applyAsFist();
      case CalStep.turn:
        break;
    }
    state = state.copyWith(
      phase: StepPhase.captured,
      done: {...state.done, step},
      weakFingers: weak,
    );
    // Prototype: the next step follows 0.75 s after "Captured".
    await Future<void>.delayed(const Duration(milliseconds: 750));
    // the glove dropped during the pause: keep the "disconnected" failure
    if (!ref.mounted || state.phase == StepPhase.failed) return;
    if (step != CalStep.turn) {
      state = state.copyWith(
        step: CalStep.values[step.index + 1],
        phase: StepPhase.idle,
      );
      return;
    }
    await _save();
  }

  Future<void> _save() async {
    state = state.copyWith(phase: StepPhase.saving);
    try {
      final cal = await _glove.saveCalibration();
      if (!ref.mounted) return;
      hand.useCalibration(cal);
      _savedOrSkipped = true;
      state = state.copyWith(phase: StepPhase.saved);
    } on GloveFailure catch (f) {
      if (!ref.mounted) return;
      _log.warn('save_error', {'kind': f.kind});
      state = state.copyWith(phase: StepPhase.failed, failure: f);
    }
  }

  /// "Try again" after `CAL SAVE` failed: runs the save again (the glove
  /// still has the three steps).
  Future<void> retrySave() => _save();

  /// Q-K6: allowed only with a stored calibration. Drops unsaved steps.
  Future<bool> skip() async {
    if (!state.canSkip) return false;
    await leave();
    _savedOrSkipped = true;
    return true;
  }

  /// Leaving the screen (Back, Skip): `CAL CANCEL` drops unsaved steps or
  /// stops a running one. Nothing to cancel after a save.
  Future<void> leave() async {
    if (_savedOrSkipped || !_glove.status.isConnected) return;
    if (state.done.isEmpty && state.phase != StepPhase.capturing) return;
    try {
      await _glove.cancelCalibration();
    } on GloveFailure catch (f) {
      _log.warn('cancel_error', {'kind': f.kind});
    }
  }
}
