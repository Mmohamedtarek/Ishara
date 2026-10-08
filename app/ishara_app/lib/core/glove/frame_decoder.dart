import 'dart:typed_data';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:meta/meta.dart';

/// One glove sample: its 16-bit `seq` and the 11 raw values
/// `f0 f1 f2 f3 f4 ax ay az gx gy gz` (BLE-CONTRACT §4, AI-SPEC §1).
@immutable
class GloveSample {
  const new(this.seq, this.values);

  final int seq;
  final Int16List values;

  @override
  bool operator ==(Object other) =>
      other is GloveSample &&
      other.seq == seq &&
      _sameValues(other.values, values);

  @override
  int get hashCode => Object.hash(seq, Object.hashAll(values));

  static bool _sameValues(Int16List a, Int16List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// DATA frames (BLE-CONTRACT §4), little-endian:
/// `ver` u8 = 1 · `n` u8 (1-10) · `seq` u16 of the first sample ·
/// n × 11 × int16. Sample k of the frame has `seq + k` (mod 65536).
abstract final class FrameCodec {
  static const version = 1;
  static const headerBytes = 4;
  static const int sampleBytes = AiSpec.channels * 2;
  static const maxSamples = 10;

  /// Decodes one notification. Throws [ParseFailure] if it is not a valid
  /// version-1 frame (the caller drops it and logs it).
  static List<GloveSample> decode(Uint8List frame) {
    if (frame.length < headerBytes) {
      throw ParseFailure('frame of ${frame.length} bytes', source: 'DATA');
    }
    final b = ByteData.sublistView(frame);
    final ver = b.getUint8(0);
    final n = b.getUint8(1);
    if (ver != version) {
      throw ParseFailure('frame version $ver', source: 'DATA');
    }
    if (n < 1 || n > maxSamples) {
      throw ParseFailure('frame with $n samples', source: 'DATA');
    }
    final want = headerBytes + n * sampleBytes;
    if (frame.length != want) {
      throw ParseFailure(
        'frame of ${frame.length} bytes, expected $want',
        source: 'DATA',
      );
    }
    final seq0 = b.getUint16(2, Endian.little);
    return [
      for (var k = 0; k < n; k++)
        GloveSample(
          (seq0 + k) & 0xFFFF,
          Int16List.fromList([
            for (var c = 0; c < AiSpec.channels; c++)
              b.getInt16(headerBytes + k * sampleBytes + c * 2, Endian.little),
          ]),
        ),
    ];
  }

  /// Encodes [samples] (consecutive `seq`) as one frame; used by the mock
  /// glove so mock data goes through [decode] like real BLE data.
  static Uint8List encode(List<GloveSample> samples) {
    if (samples.isEmpty || samples.length > maxSamples) {
      throw ArgumentError('1-$maxSamples samples per frame');
    }
    final out = ByteData(headerBytes + samples.length * sampleBytes)
      ..setUint8(0, version)
      ..setUint8(1, samples.length)
      ..setUint16(2, samples.first.seq & 0xFFFF, Endian.little);
    for (var k = 0; k < samples.length; k++) {
      final s = samples[k];
      if (s.seq != (samples.first.seq + k) & 0xFFFF) {
        throw ArgumentError('samples in a frame must have consecutive seq');
      }
      for (var c = 0; c < AiSpec.channels; c++) {
        out.setInt16(
          headerBytes + k * sampleBytes + c * 2,
          s.values[c],
          Endian.little,
        );
      }
    }
    return out.buffer.asUint8List();
  }

  /// Samples per frame for an MTU, as the firmware picks it:
  /// `min(5, ⌊(MTU − 3 − 4) / 22⌋)`; 0 means the MTU is too small to stream.
  static int samplesForMtu(int mtu) {
    final n = (mtu - 3 - headerBytes) ~/ sampleBytes;
    return n < 0 ? 0 : (n > 5 ? 5 : n);
  }
}
