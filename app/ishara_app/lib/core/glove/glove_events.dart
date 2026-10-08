import 'dart:convert';
import 'dart:typed_data';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:meta/meta.dart';

/// The 3 calibration steps (BLE-CONTRACT §5, §7).
enum CalStep {
  open,
  fist,
  turn;

  String get wire => name.toUpperCase();

  static CalStep? fromWire(String s) => switch (s) {
    'OPEN' => open,
    'FIST' => fist,
    'TURN' => turn,
    _ => null,
  };
}

/// Battery state from `#BAT` (BLE-CONTRACT §6).
enum BatteryLevel { usb, ok, low }

/// A text line from the EVENT characteristic (BLE-CONTRACT §6).
@immutable
sealed class GloveEvent {
  const new();
}

/// `#CAL {json}`.
final class CalibrationEvent extends GloveEvent {
  const new(this.calibration);
  final GloveCalibration calibration;
}

/// `#CAL NONE`: the glove is not calibrated.
final class NoCalibrationEvent extends GloveEvent {
  const new();
}

/// `#CALSTEP <OPEN|FIST|TURN> <OK|FAIL> [reason]`.
final class CalStepEvent extends GloveEvent {
  const new(this.step, {required this.ok, this.reason});
  final CalStep step;
  final bool ok;

  /// `MOVED`, `RANGE`, `MPU`, `CANCELLED` (or a future reason) on FAIL.
  final String? reason;
}

/// `#BAT NO_BATTERY (USB)` · `#BAT OK 3.92V 78%` · `#BAT LOW 3.38V`.
final class BatteryEvent extends GloveEvent {
  const new(this.level, {this.volts, this.percent});
  final BatteryLevel level;
  final double? volts;
  final int? percent;
}

/// `#OK <CMD>`.
final class OkEvent extends GloveEvent {
  const new(this.command);
  final String command;
}

/// `#ERR <CMD> <reason>` (also sent without a command, e.g. `#ERR STREAM MTU`).
final class ErrorEvent extends GloveEvent {
  const new(this.command, this.reason);
  final String command;
  final String reason;
}

/// `#PONG`.
final class PongEvent extends GloveEvent {
  const new();
}

/// `#MPU FAIL`: the motion sensor isn't responding.
final class MpuFailEvent extends GloveEvent {
  const new();
}

/// `#FLEX WEAK <0-4>`: a finger sensor moved under 300 counts (0 = thumb).
final class FlexWeakEvent extends GloveEvent {
  const new(this.finger);
  final int finger;
}

/// Parses EVENT lines. Unknown lines return null and must be ignored
/// (BLE-CONTRACT §6: new messages can be added later).
abstract final class GloveEventParser {
  static final _bat = RegExp(r'^#BAT (OK|LOW) ([\d.]+)V(?: (\d+)%)?$');

  /// Parses one line (without the trailing newline). Throws [ParseFailure]
  /// only for a `#CAL {...}` whose JSON breaks the contract.
  static GloveEvent? parse(String line) {
    final l = line.trim();
    if (l == '#CAL NONE') return const NoCalibrationEvent();
    if (l.startsWith('#CAL {')) {
      return CalibrationEvent(GloveCalibration.parse(l.substring(5)));
    }
    if (l == '#PONG') return const PongEvent();
    if (l == '#MPU FAIL') return const MpuFailEvent();
    final parts = l.split(RegExp(' +'));
    switch (parts.first) {
      case '#CALSTEP' when parts.length >= 3:
        final step = CalStep.fromWire(parts[1]);
        if (step == null || (parts[2] != 'OK' && parts[2] != 'FAIL')) {
          return null;
        }
        return CalStepEvent(
          step,
          ok: parts[2] == 'OK',
          reason: parts.length > 3 ? parts.sublist(3).join(' ') : null,
        );
      case '#BAT':
        if (l == '#BAT NO_BATTERY (USB)') {
          return const BatteryEvent(BatteryLevel.usb);
        }
        final m = _bat.firstMatch(l);
        if (m == null) return null;
        return BatteryEvent(
          m.group(1) == 'OK' ? BatteryLevel.ok : BatteryLevel.low,
          volts: double.tryParse(m.group(2)!),
          percent: m.group(3) == null ? null : int.parse(m.group(3)!),
        );
      case '#OK' when parts.length >= 2:
        return OkEvent(parts.sublist(1).join(' '));
      case '#ERR' when parts.length >= 3:
        return ErrorEvent(parts[1], parts.sublist(2).join(' '));
      case '#FLEX' when parts.length == 3 && parts[1] == 'WEAK':
        final f = int.tryParse(parts[2]);
        return f != null && f >= 0 && f <= 4 ? FlexWeakEvent(f) : null;
    }
    return null;
  }
}

/// Joins EVENT notifications into lines: a line longer than one notification
/// arrives in pieces and ends with `\n` (BLE-CONTRACT §6).
class LineAssembler {
  final _pending = BytesBuilder();

  /// Upper bound for one line; anything longer is dropped (protects memory
  /// if a newline is ever lost).
  static const maxLineBytes = 4096;

  /// Adds one notification; returns the complete lines it finished.
  List<String> add(List<int> chunk) {
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 0x0A) {
        _pending.add(chunk.sublist(start, i));
        final bytes = _pending.takeBytes();
        final line = utf8
            .decode(bytes, allowMalformed: true)
            .replaceAll('\r', '');
        if (line.trim().isNotEmpty) lines.add(line);
        start = i + 1;
      }
    }
    if (start < chunk.length) _pending.add(chunk.sublist(start));
    if (_pending.length > maxLineBytes) _pending.clear();
    return lines;
  }

  /// Drops a half-received line (on disconnect).
  void clear() => _pending.clear();
}
