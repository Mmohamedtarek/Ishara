import 'dart:async';

import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pair_controller.g.dart';

/// Where the Pair screen is (prototype `state.pair`, plus the states the
/// prototype lacks: Phase 0 screen map, BLE-CONTRACT).
enum PairStage {
  /// Asking for the runtime permissions.
  permission,

  /// Permissions refused ([PairState.permission] says how).
  permissionDenied,

  /// Bluetooth can't be used ([PairState.bluetooth] says why).
  bluetoothProblem,

  /// Looking for gloves.
  scanning,

  /// At least one glove found ([PairState.gloves]).
  found,

  /// The scan ended without a glove.
  notFound,

  /// The three checks are running.
  connecting,

  /// Connected and every check passed.
  connected,

  /// A check failed ([PairState.failedCheck], [PairState.failure] /
  /// [PairState.mpuFail]).
  failed,
}

/// One of the three pairing checks (Q-K3).
enum CheckState { waiting, running, ok, failed }

@immutable
class PairState {
  const new({
    this.stage = PairStage.permission,
    this.gloves = const [],
    this.checks = const [
      CheckState.waiting,
      CheckState.waiting,
      CheckState.waiting,
    ],
    this.permission,
    this.bluetooth,
    this.failure,
    this.mpuFail = false,
    this.status = const GloveStatus(),
  });

  final PairStage stage;

  /// Gloves found, strongest signal first.
  final List<DiscoveredGlove> gloves;

  /// Check 1 connect + MTU + services; 2 "Checking the sensors" (INFO
  /// `proto == 1`, EVENT, `#BAT`, no `#MPU FAIL`); 3 `GETCAL`.
  final List<CheckState> checks;
  final GlovePermission? permission;
  final BluetoothProblem? bluetooth;
  final GloveFailure? failure;

  /// `#MPU FAIL` during check 2: the motion sensor isn't answering.
  final bool mpuFail;

  /// The glove client's status (device, INFO, battery, stored calibration).
  final GloveStatus status;

  /// Index of the failed check, or null.
  int? get failedCheck {
    final i = checks.indexOf(CheckState.failed);
    return i < 0 ? null : i;
  }

  PairState copyWith({
    PairStage? stage,
    List<DiscoveredGlove>? gloves,
    List<CheckState>? checks,
    GlovePermission? permission,
    BluetoothProblem? bluetooth,
    GloveFailure? failure,
    bool? mpuFail,
    GloveStatus? status,
  }) => PairState(
    stage: stage ?? this.stage,
    gloves: gloves ?? this.gloves,
    checks: checks ?? this.checks,
    permission: permission ?? this.permission,
    bluetooth: bluetooth ?? this.bluetooth,
    failure: failure ?? this.failure,
    mpuFail: mpuFail ?? this.mpuFail,
    status: status ?? this.status,
  );
}

/// Runs the Pair screen: permissions → scan → connect with the three checks.
@riverpod
class PairController extends _$PairController {
  static final _log = Log('pair');

  StreamSubscription<List<DiscoveredGlove>>? _scan;
  StreamSubscription<GloveStatus>? _statusSub;
  bool _askedLocation = false;

  GloveSource get _glove => ref.read(gloveSourceProvider);

  @override
  PairState build() {
    ref.onDispose(() {
      unawaited(_scan?.cancel());
      unawaited(_statusSub?.cancel());
    });
    final s = ref.read(gloveSourceProvider).status;
    // Coming back to Pair while connected (prototype `keep`): stay connected.
    if (s.phase == GlovePhase.ready && !s.mpuFail) {
      return PairState(
        stage: PairStage.connected,
        checks: List.filled(3, CheckState.ok),
        status: s,
      );
    }
    return const PairState();
  }

  /// Asks for the permissions, then scans.
  Future<void> start() async {
    state = const PairState();
    final p = await ref.read(glovePermissionsProvider).request();
    if (!ref.mounted) return;
    if (p != GlovePermission.granted) {
      state = PairState(stage: PairStage.permissionDenied, permission: p);
      return;
    }
    await _startScan();
  }

  /// "Scan again" (also after a failure or from the connected state).
  Future<void> scanAgain() async {
    await _scan?.cancel();
    if (_glove.status.isConnected) await _glove.disconnect();
    if (!ref.mounted) return;
    await start();
  }

  Future<void> openSettings() =>
      ref.read(glovePermissionsProvider).openSettings();

  Future<void> _startScan() async {
    await _scan?.cancel();
    state = const PairState(stage: PairStage.scanning);
    final found = <DiscoveredGlove>[];
    _scan = _glove.scan().listen(
      (list) {
        found
          ..clear()
          ..addAll(list)
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        if (state.stage == PairStage.scanning ||
            state.stage == PairStage.found) {
          state = state.copyWith(
            stage: found.isEmpty ? PairStage.scanning : PairStage.found,
            gloves: List.unmodifiable(found),
          );
        }
      },
      onError: (Object e) async {
        if (e is BluetoothUnavailableFailure) {
          // Android 11 and older: scanning needs location; ask once.
          if (e.problem == BluetoothProblem.unauthorized && !_askedLocation) {
            _askedLocation = true;
            final p = await ref
                .read(glovePermissionsProvider)
                .requestLocation();
            if (!ref.mounted) return;
            if (p == GlovePermission.granted) {
              unawaited(_startScan());
            } else {
              state = PairState(
                stage: PairStage.permissionDenied,
                permission: p,
              );
            }
            return;
          }
          state = PairState(
            stage: PairStage.bluetoothProblem,
            bluetooth: e.problem,
          );
        } else {
          _log.warn('scan_failed', {'error': '$e'});
          state = PairState(
            stage: PairStage.notFound,
            failure: e is GloveFailure ? e : null,
          );
        }
      },
      onDone: () {
        if (state.stage == PairStage.scanning) {
          state = state.copyWith(stage: PairStage.notFound);
        }
      },
    );
  }

  static List<CheckState> _checksFor(GlovePhase phase) => switch (phase) {
    GlovePhase.idle ||
    GlovePhase.scanning => List.filled(3, CheckState.waiting),
    GlovePhase.linking => const [
      CheckState.running,
      CheckState.waiting,
      CheckState.waiting,
    ],
    GlovePhase.checkingSensors => const [
      CheckState.ok,
      CheckState.running,
      CheckState.waiting,
    ],
    GlovePhase.readingCalibration => const [
      CheckState.ok,
      CheckState.ok,
      CheckState.running,
    ],
    GlovePhase.ready => List.filled(3, CheckState.ok),
  };

  /// Connects to [glove] with the three checks; saves it when they pass.
  Future<void> connect(DiscoveredGlove glove) async {
    // Stop scanning without waiting for the scan's clean-up: the radio stops
    // at once, and the client ignores a late "scan ended" once connecting.
    final scan = _scan;
    _scan = null;
    unawaited(scan?.cancel());
    state = PairState(
      stage: PairStage.connecting,
      gloves: state.gloves,
      checks: _checksFor(GlovePhase.linking),
    );
    var lastPhase = GlovePhase.linking;
    await _statusSub?.cancel();
    _statusSub = _glove.statusChanges.listen((s) {
      if (!ref.mounted || state.stage != PairStage.connecting) return;
      if (s.phase.index >= GlovePhase.linking.index) lastPhase = s.phase;
      state = state.copyWith(checks: _checksFor(lastPhase), status: s);
    });
    try {
      await _glove.connect(glove);
    } on GloveFailure catch (f) {
      if (!ref.mounted) return;
      final checks = [..._checksFor(lastPhase)];
      final i = checks.indexOf(CheckState.running);
      if (i >= 0) checks[i] = CheckState.failed;
      state = state.copyWith(
        stage: PairStage.failed,
        checks: checks,
        failure: f,
        status: _glove.status,
      );
      return;
    } finally {
      await _statusSub?.cancel();
      _statusSub = null;
    }
    if (!ref.mounted) return;
    final s = _glove.status;
    if (s.mpuFail) {
      // Q-K3: check 2 includes "no #MPU FAIL". Without the motion sensor
      // calibration and recognition can't work: stop here.
      await _glove.disconnect();
      if (!ref.mounted) return;
      state = state.copyWith(
        stage: PairStage.failed,
        checks: const [CheckState.ok, CheckState.failed, CheckState.waiting],
        mpuFail: true,
        status: s,
      );
      return;
    }
    await ref
        .read(profileControllerProvider.notifier)
        .setGlove(PairedGlove(id: glove.id, name: glove.name));
    if (!ref.mounted) return;
    state = state.copyWith(
      stage: PairStage.connected,
      checks: List.filled(3, CheckState.ok),
      status: s,
    );
  }
}
