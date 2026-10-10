import 'dart:async';
import 'dart:typed_data';

import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/recognition/calibration.dart';

/// A scripted glove for screen and controller tests (no timers of its own
/// unless [stepTime] / [connectTime] are set, so fake-async tests control
/// everything).
class FakeGloveSource implements GloveSource {
  new({
    this.found = const [
      DiscoveredGlove(id: 'g1', name: 'Ishara-3FA2', rssi: -55),
    ],
    this.stored = true,
  });

  /// What the scan finds (emitted at once, then the scan ends).
  List<DiscoveredGlove> found;

  /// The scan throws this instead (Bluetooth off…), [scanErrorTimes] times.
  GloveFailure? scanError;
  int scanErrorTimes = 1 << 30;

  /// The glove has a stored `#CAL {…}`.
  bool stored;

  /// Connect fails with this, in [failAt].
  GloveFailure? connectError;
  GlovePhase failAt = GlovePhase.linking;

  /// `#MPU FAIL` during check 2.
  bool mpuFail = false;

  BatteryEvent battery = const BatteryEvent(
    BatteryLevel.ok,
    volts: 3.92,
    percent: 78,
  );

  /// Next result per step (default OK).
  final Map<CalStep, CalStepResult> stepResults = {};

  /// `CAL SAVE` fails with this.
  GloveFailure? saveError;

  /// Time each connect phase / calibration step takes (zero = at once).
  Duration connectTime = Duration.zero;
  Duration stepTime = Duration.zero;

  /// Per-step time (wins over [stepTime]), e.g. the glove's 2 s / 2 s / 3 s.
  final Map<CalStep, Duration> stepTimes = {};

  final commands = <String>[];
  final _status = StreamController<GloveStatus>.broadcast(sync: true);
  final _samples = StreamController<List<GloveSample>>.broadcast(sync: true);
  final _events = StreamController<GloveEvent>.broadcast(sync: true);
  GloveStatus _s = const GloveStatus();

  static final calibration = GloveCalibration.parse(
    '{"v":2,"open":[1000,1000,1000,1000,1000],'
    '"fist":[3000,3000,3000,3000,3000],"gyro_bias_raw":[0,0,0],'
    '"roll_neutral":0,"roll_min":-40,"roll_max":40}',
  );

  void _set(GloveStatus s) {
    _s = s;
    _status.add(s);
  }

  /// Sends one sample (flex, accel, gyro raw values).
  void sample({
    List<int> flex = const [2000, 2000, 2000, 2000, 2000],
    int ay = 0,
    int az = 8192,
    int gx = 0,
  }) => _samples.add([
    GloveSample(0, Int16List.fromList([...flex, 0, ay, az, gx, 0, 0])),
  ]);

  /// The link drops.
  void dropLink() => _set(
    GloveStatus(failure: const GloveDisconnectedFailure(), device: _s.device),
  );

  @override
  GloveStatus get status => _s;

  @override
  Stream<GloveStatus> get statusChanges => _status.stream;

  @override
  Stream<List<GloveSample>> get samples => _samples.stream;

  @override
  Stream<GloveEvent> get events => _events.stream;

  @override
  Stream<List<DiscoveredGlove>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    commands.add('scan');
    final e = scanError;
    if (e != null && scanErrorTimes > 0) {
      scanErrorTimes--;
      throw e;
    }
    if (found.isNotEmpty) yield found;
  }

  @override
  Future<void> connect(DiscoveredGlove glove) async {
    commands.add('connect ${glove.id}');
    for (final phase in [
      GlovePhase.linking,
      GlovePhase.checkingSensors,
      GlovePhase.readingCalibration,
    ]) {
      _set(
        GloveStatus(
          phase: phase,
          device: glove,
          battery: phase.index >= GlovePhase.readingCalibration.index
              ? battery
              : null,
          mpuFail:
              mpuFail && phase.index >= GlovePhase.readingCalibration.index,
          info: phase.index >= GlovePhase.readingCalibration.index
              ? const GloveInfo(
                  proto: 1,
                  firmware: '0.3.0',
                  board: 'devkit',
                  rateHz: 50,
                  channels: 11,
                )
              : null,
        ),
      );
      if (connectTime > Duration.zero) await Future<void>.delayed(connectTime);
      final e = connectError;
      if (e != null && phase == failAt) {
        _set(GloveStatus(device: glove, failure: e));
        throw e;
      }
    }
    _set(
      _s.copyWith(
        phase: GlovePhase.ready,
        storedCalibration: stored
            ? StoredCalibration.present
            : StoredCalibration.none,
        calibration: stored ? calibration : null,
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    commands.add('disconnect');
    _set(const GloveStatus());
  }

  @override
  Future<GloveCalibration?> readCalibration() async =>
      stored ? calibration : null;

  @override
  Future<CalStepResult> calibrate(CalStep step) async {
    commands.add('CAL ${step.wire}');
    final time = stepTimes[step] ?? stepTime;
    if (time > Duration.zero) await Future<void>.delayed(time);
    if (!_s.isConnected) throw const GloveDisconnectedFailure();
    return stepResults.remove(step) ?? CalStepResult(step, ok: true);
  }

  @override
  Future<GloveCalibration> saveCalibration() async {
    commands.add('CAL SAVE');
    final e = saveError;
    if (e != null) {
      saveError = null;
      throw e;
    }
    stored = true;
    _set(
      _s.copyWith(
        storedCalibration: StoredCalibration.present,
        calibration: calibration,
      ),
    );
    return calibration;
  }

  @override
  Future<void> cancelCalibration() async => commands.add('CAL CANCEL');

  @override
  Future<BatteryEvent> readBattery() async => battery;

  @override
  void cuePractice(String label) {}

  @override
  Future<void> dispose() async {
    await _status.close();
    await _samples.close();
    await _events.close();
  }
}

/// Scripted permissions.
class FakeGlovePermissions implements GlovePermissions {
  new({
    this.answer = GlovePermission.granted,
    this.location = GlovePermission.granted,
    this.alreadyGranted = true,
  });

  GlovePermission answer;
  GlovePermission location;
  bool alreadyGranted;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<GlovePermission> request() async {
    requests++;
    return answer;
  }

  @override
  Future<GlovePermission> requestLocation() async => location;

  @override
  Future<bool> granted() async => alreadyGranted;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}
