import 'dart:async';

import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:meta/meta.dart';

/// A glove seen while scanning (BLE §1).
@immutable
class DiscoveredGlove {
  const new({required this.id, required this.name, required this.rssi});

  /// Transport id (BLE address / iOS identifier).
  final String id;

  /// `Ishara-XXXX`.
  final String name;

  /// Signal strength in dBm.
  final int rssi;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredGlove &&
      other.id == id &&
      other.name == name &&
      other.rssi == rssi;

  @override
  int get hashCode => Object.hash(id, name, rssi);
}

/// INFO, read once after connecting (BLE §2). Unknown fields are ignored.
@immutable
class GloveInfo {
  const new({
    required this.proto,
    required this.firmware,
    required this.board,
    required this.rateHz,
    required this.channels,
  });

  final int proto;
  final String firmware;

  /// `devkit` or `xiao`: for display and support only, never branch on it.
  final String board;
  final int rateHz;
  final int channels;
}

/// Where a connection is (Q-K3 maps the pairing checks onto these phases).
enum GlovePhase {
  /// Not connected.
  idle,

  /// Looking for gloves.
  scanning,

  /// Check 1: connect, MTU 247, services.
  linking,

  /// Check 2: INFO `proto == 1`, EVENT subscribed (`#BAT`, no `#MPU FAIL`).
  checkingSensors,

  /// Check 3: `GETCAL`.
  readingCalibration,

  /// Connected and streaming.
  ready,
}

/// Calibration stored on the glove, as far as the app knows.
enum StoredCalibration {
  /// Not asked yet.
  unknown,

  /// `#CAL NONE`.
  none,

  /// `#CAL {...}` received.
  present,
}

/// Everything the UI needs about the glove connection.
@immutable
class GloveStatus {
  const new({
    this.phase = GlovePhase.idle,
    this.device,
    this.info,
    this.battery,
    this.storedCalibration = StoredCalibration.unknown,
    this.calibration,
    this.mpuFail = false,
    this.failure,
  });

  final GlovePhase phase;
  final DiscoveredGlove? device;
  final GloveInfo? info;
  final BatteryEvent? battery;
  final StoredCalibration storedCalibration;
  final GloveCalibration? calibration;

  /// `#MPU FAIL` was received on this connection (motion sensor problem).
  final bool mpuFail;

  /// Why the last connection attempt or connection ended, if it failed.
  final GloveFailure? failure;

  bool get isConnected => phase.index >= GlovePhase.linking.index;

  GloveStatus copyWith({
    GlovePhase? phase,
    DiscoveredGlove? device,
    GloveInfo? info,
    BatteryEvent? battery,
    StoredCalibration? storedCalibration,
    GloveCalibration? calibration,
    bool? mpuFail,
    GloveFailure? failure,
    bool clearFailure = false,
  }) => GloveStatus(
    phase: phase ?? this.phase,
    device: device ?? this.device,
    info: info ?? this.info,
    battery: battery ?? this.battery,
    storedCalibration: storedCalibration ?? this.storedCalibration,
    calibration: calibration ?? this.calibration,
    mpuFail: mpuFail ?? this.mpuFail,
    failure: clearFailure ? null : failure ?? this.failure,
  );
}

/// The result of one calibration step (BLE §7).
@immutable
class CalStepResult {
  const new(
    this.step, {
    required this.ok,
    this.reason,
    this.weakFingers = const [],
  });

  final CalStep step;
  final bool ok;

  /// `MOVED`, `RANGE`, `MPU`, `CANCELLED`… on failure.
  final String? reason;

  /// `#FLEX WEAK <i>` fingers reported right before this reply.
  final List<int> weakFingers;
}

/// The one interface the app uses for the glove. Implementations: the real
/// glove over BLE and the mock glove; only `lib/core/glove/` knows which one
/// is active.
abstract interface class GloveSource {
  /// Current status and its changes.
  GloveStatus get status;
  Stream<GloveStatus> get statusChanges;

  /// Raw samples as they arrive (one list per DATA frame), in `seq` order of
  /// arrival; the recognizer applies the gap rule.
  Stream<List<GloveSample>> get samples;

  /// Every parsed EVENT line (`#CAL`, `#BAT`, `#MPU FAIL`, `#FLEX WEAK`…).
  Stream<GloveEvent> get events;

  /// Scans for gloves; the stream emits the list found so far and ends after
  /// [timeout]. Throws [BluetoothUnavailableFailure] if Bluetooth can't scan.
  Stream<List<DiscoveredGlove>> scan({Duration timeout});

  /// Connects and runs the contract setup (BLE §3) up to streaming.
  /// Throws a [GloveFailure]; [status] tells which phase failed.
  Future<void> connect(DiscoveredGlove glove);

  Future<void> disconnect();

  /// `GETCAL`.
  Future<GloveCalibration?> readCalibration();

  /// `CAL OPEN | FIST | TURN` (2 s, 2 s, 3 s on the glove).
  Future<CalStepResult> calibrate(CalStep step);

  /// `CAL SAVE` → the new calibration.
  Future<GloveCalibration> saveCalibration();

  /// `CAL CANCEL`.
  Future<void> cancelCalibration();

  /// `BAT`.
  Future<BatteryEvent> readBattery();

  /// Learn "Sign now" was pressed for [label]. The real glove ignores it; the
  /// mock glove plays that sign's practice recording (Q-L5). Callers don't
  /// need to know which source is active.
  void cuePractice(String label);

  Future<void> dispose();
}
