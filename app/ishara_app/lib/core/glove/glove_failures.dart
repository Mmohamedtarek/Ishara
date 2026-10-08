import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/glove_events.dart';

/// Base of every glove failure (each one maps to an error screen).
abstract class GloveFailure extends Failure {
  const new(super.message, {super.cause, super.stackTrace});
}

/// Why Bluetooth can't be used.
enum BluetoothProblem {
  off,
  unauthorized,
  unsupported,
  locationOff,

  /// The state isn't known yet (e.g. a permission alert is open): retry.
  notReady,
}

/// Bluetooth is off, not allowed, or missing.
final class BluetoothUnavailableFailure extends GloveFailure {
  const new(this.problem) : super('bluetooth unavailable');
  final BluetoothProblem problem;

  @override
  String get kind => 'bluetooth_${problem.name}';
}

/// No `Ishara-XXXX` glove was found before the scan ended.
final class GloveNotFoundFailure extends GloveFailure {
  const new() : super('no glove found');

  @override
  String get kind => 'glove_not_found';
}

/// Connecting failed (link, MTU, services or characteristics).
final class GloveConnectFailure extends GloveFailure {
  const new(super.message, {super.cause, super.stackTrace});

  @override
  String get kind => 'glove_connect';
}

/// INFO `proto` isn't 1: "update the app / firmware", don't stream (BLE §2).
final class GloveProtocolMismatchFailure extends GloveFailure {
  const new(this.proto) : super('glove protocol $proto, app speaks 1');
  final Object? proto;

  @override
  String get kind => 'glove_protocol';
}

/// A command got no reply in time (BLE §5).
final class GloveCommandTimeoutFailure extends GloveFailure {
  const new(this.command) : super('no reply to $command');
  final String command;

  @override
  String get kind => 'glove_timeout';
}

/// A command was answered with `#ERR <CMD> <reason>`.
final class GloveCommandRejectedFailure extends GloveFailure {
  new(this.error) : super('glove refused: ${error.command} ${error.reason}');
  final ErrorEvent error;

  @override
  String get kind => 'glove_rejected';
}

/// The link dropped (while connecting or streaming).
final class GloveDisconnectedFailure extends GloveFailure {
  const new() : super('glove disconnected');

  @override
  String get kind => 'glove_disconnected';
}

/// The glove's `#CAL` reply breaks the contract (missing keys, not JSON).
final class GloveBadCalibrationFailure extends GloveFailure {
  const new(Failure parse) : super('invalid #CAL from the glove', cause: parse);

  @override
  String get kind => 'glove_bad_calibration';
}

/// Scanning failed for a reason other than Bluetooth being unavailable
/// (e.g. Android throttling repeated scans).
final class GloveScanFailure extends GloveFailure {
  const new({super.cause, super.stackTrace}) : super('scan failed');

  @override
  String get kind => 'glove_scan';
}
