import 'dart:typed_data';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:meta/meta.dart';

/// A mock glove recording from the kit (`mock/A|B/*.csv`).
///
/// Format (AI-SPEC §1, BLE-CONTRACT §4): the USB serial lines
/// `seq,f0,f1,f2,f3,f4,ax,ay,az,gx,gy,gz` (serial `seq` is 8-bit and is not
/// used: the mock gives samples a 16-bit `seq` like BLE does). Lines starting
/// with `#` are glove messages (the first one is `#CAL ...`).
@immutable
class Recording {
  const new({required this.samples, required this.messages});

  factory parse(String text, {String name = 'recording'}) {
    final rows = <int>[];
    final messages = <RecordingMessage>[];
    var lineNo = 0;
    for (final raw in text.split('\n')) {
      lineNo++;
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        messages.add(RecordingMessage(rows.length ~/ AiSpec.channels, line));
        continue;
      }
      final parts = line.split(',');
      if (parts.length != AiSpec.channels + 1) {
        throw ParseFailure(
          '$name:$lineNo has ${parts.length} values, expected 12',
          source: name,
        );
      }
      for (var i = 1; i < parts.length; i++) {
        final v = int.tryParse(parts[i].trim());
        if (v == null) {
          throw ParseFailure('$name:$lineNo: not an integer', source: name);
        }
        rows.add(v);
      }
    }
    return Recording(samples: Int32List.fromList(rows), messages: messages);
  }

  /// All samples, 11 values each, flattened.
  final Int32List samples;

  /// `#` lines, with the number of samples before them.
  final List<RecordingMessage> messages;

  int get length => samples.length ~/ AiSpec.channels;

  /// The 11 raw values of sample [i].
  Int32List sample(int i) => Int32List.sublistView(
    samples,
    i * AiSpec.channels,
    (i + 1) * AiSpec.channels,
  );

  /// The JSON of the first `#CAL {...}` line, if any.
  String? get calibrationJson {
    for (final m in messages) {
      if (m.line.startsWith('#CAL {')) return m.line.substring(5);
    }
    return null;
  }
}

/// A `#` line of a recording.
@immutable
class RecordingMessage {
  const new(this.beforeSample, this.line);

  /// How many samples come before this line.
  final int beforeSample;
  final String line;
}
