@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_events.dart';

import '../support/kit.dart';

Uint8List _hex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

void main() {
  group('FrameCodec (BLE-CONTRACT §4)', () {
    test('decodes every frame of mock/ble_frames.txt to the same numbers', () {
      final lines = readText('assets/packs/asl/kit/mock/ble_frames.txt')
          .split('\n');
      var frames = 0;
      var checked = 0;
      List<GloveSample>? current;
      var k = 0;
      for (final line in lines) {
        if (line.startsWith('#') || line.trim().isEmpty) continue;
        if (!line.startsWith(' ')) {
          if (current != null) {
            expect(k, current.length, reason: 'samples in frame');
          }
          current = FrameCodec.decode(_hex(line.trim()));
          frames++;
          k = 0;
          continue;
        }
        final nums = line.trim().split(RegExp(r'\s+')).map(int.parse).toList();
        expect(current, isNotNull);
        final s = current![k++];
        expect(s.seq, nums.first, reason: 'seq of sample $checked');
        expect(s.values, nums.sublist(1), reason: 'values of sample $checked');
        checked++;
      }
      expect(frames, 10);
      expect(checked, 50);
    });

    test('encode is the inverse of decode', () {
      final hex = readText('assets/packs/asl/kit/mock/ble_frames.txt')
          .split('\n')
          .firstWhere((l) => RegExp('^[0-9a-f]').hasMatch(l))
          .trim();
      final bytes = _hex(hex);
      expect(bytes, hasLength(114));
      expect(FrameCodec.encode(FrameCodec.decode(bytes)), bytes);
    });

    test('seq wraps 65535 -> 0 inside a frame', () {
      final f = FrameCodec.encode([
        for (var i = 0; i < 3; i++)
          GloveSample((65534 + i) & 0xFFFF, Int16List(11)..[0] = i),
      ]);
      expect(FrameCodec.decode(f).map((s) => s.seq), [65534, 65535, 0]);
    });

    test('rejects bad frames', () {
      final good = FrameCodec.encode([GloveSample(7, Int16List(11))]);
      Uint8List edit(void Function(Uint8List b) f) =>
          Uint8List.fromList(good)..apply(f);
      for (final bad in [
        Uint8List(3),
        edit((b) => b[0] = 2), // version
        edit((b) => b[1] = 0), // n = 0
        edit((b) => b[1] = 11), // n > 10
        edit((b) => b[1] = 2), // length doesn't match n
        Uint8List.fromList([...good, 0]),
      ]) {
        expect(() => FrameCodec.decode(bad), throwsA(isA<ParseFailure>()));
      }
    });

    test('encode checks its input', () {
      expect(() => FrameCodec.encode([]), throwsArgumentError);
      expect(
        () => FrameCodec.encode([
          GloveSample(1, Int16List(11)),
          GloveSample(3, Int16List(11)),
        ]),
        throwsArgumentError,
      );
    });

    test('samples per frame from the MTU, as the firmware picks it', () {
      expect(FrameCodec.samplesForMtu(247), 5);
      expect(FrameCodec.samplesForMtu(185), 5);
      expect(FrameCodec.samplesForMtu(51), 2);
      expect(FrameCodec.samplesForMtu(50), 1);
      expect(FrameCodec.samplesForMtu(29), 1);
      expect(FrameCodec.samplesForMtu(28), 0);
      expect(FrameCodec.samplesForMtu(23), 0);
      expect(FrameCodec.samplesForMtu(2), 0);
    });

    test('sample equality', () {
      final a = GloveSample(1, Int16List.fromList(List.filled(11, 3)));
      final b = GloveSample(1, Int16List.fromList(List.filled(11, 3)));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == GloveSample(2, a.values), isFalse);
    });
  });

  group('GloveEventParser (BLE-CONTRACT §6)', () {
    test('#CAL {json} with extra fields', () {
      final json = [
        '"fw":"0.3.0"',
        '"v":2',
        '"open":[1,2,3,4,5]',
        '"fist":[6,7,8,9,10]',
        '"gyro_bias_raw":[0.5,-1,2]',
        '"roll_neutral":0',
        '"roll_min":-45',
        '"roll_max":45',
        '"gyroBias":[9,9,9]',
        '"gravity":[0,0,1]',
      ].join(',');
      final e = GloveEventParser.parse('#CAL {$json}')! as CalibrationEvent;
      expect(e.calibration.open, [1, 2, 3, 4, 5]);
      expect(e.calibration.gyroBiasRaw, [0.5, -1, 2]);
      expect(e.calibration.version, 2);
    });

    test('#CAL missing a contract key is a ParseFailure', () {
      expect(
        () => GloveEventParser.parse('#CAL {"v":2,"open":[1,2,3,4,5]}'),
        throwsA(isA<ParseFailure>()),
      );
      expect(
        () => GloveEventParser.parse('#CAL {nope'),
        throwsA(isA<ParseFailure>()),
      );
    });

    test('all contract lines', () {
      expect(GloveEventParser.parse('#CAL NONE'), isA<NoCalibrationEvent>());
      final ok = GloveEventParser.parse('#CALSTEP OPEN OK')! as CalStepEvent;
      expect([ok.step, ok.ok, ok.reason], [CalStep.open, true, null]);
      final fail =
          GloveEventParser.parse('#CALSTEP TURN FAIL RANGE')! as CalStepEvent;
      expect([fail.step, fail.ok, fail.reason], [CalStep.turn, false, 'RANGE']);
      final usb =
          GloveEventParser.parse('#BAT NO_BATTERY (USB)')! as BatteryEvent;
      expect(
        [usb.level, usb.volts, usb.percent],
        [BatteryLevel.usb, null, null],
      );
      final b = GloveEventParser.parse('#BAT OK 3.92V 78%')! as BatteryEvent;
      expect([b.level, b.volts, b.percent], [BatteryLevel.ok, 3.92, 78]);
      final low = GloveEventParser.parse('#BAT LOW 3.38V')! as BatteryEvent;
      expect(
        [low.level, low.volts, low.percent],
        [BatteryLevel.low, 3.38, null],
      );
      expect(
        (GloveEventParser.parse('#OK STREAM')! as OkEvent).command,
        'STREAM',
      );
      final err =
          GloveEventParser.parse('#ERR CAL MISSING OPEN')! as ErrorEvent;
      expect([err.command, err.reason], ['CAL', 'MISSING OPEN']);
      final mtu = GloveEventParser.parse('#ERR STREAM MTU')! as ErrorEvent;
      expect([mtu.command, mtu.reason], ['STREAM', 'MTU']);
      expect(GloveEventParser.parse('#PONG'), isA<PongEvent>());
      expect(GloveEventParser.parse('#MPU FAIL'), isA<MpuFailEvent>());
      expect(
        (GloveEventParser.parse('#FLEX WEAK 3')! as FlexWeakEvent).finger,
        3,
      );
      expect(GloveEventParser.parse('#CALSTEP FIST OK\r'), isA<CalStepEvent>());
    });

    test('unknown or malformed lines are ignored (null)', () {
      for (final l in [
        '#HELLO world',
        '#BAT OK',
        '#BAT MAYBE 3V',
        '#FLEX WEAK 7',
        '#FLEX WEAK x',
        '#CALSTEP WAVE OK',
        '#CALSTEP OPEN MAYBE',
        '#OK',
        '#ERR X',
        'plain text',
        '',
      ]) {
        expect(GloveEventParser.parse(l), isNull, reason: l);
      }
    });

    test('CalStep wire names', () {
      expect(CalStep.values.map((s) => s.wire), ['OPEN', 'FIST', 'TURN']);
      expect(CalStep.fromWire('FIST'), CalStep.fist);
      expect(CalStep.fromWire('fist'), isNull);
    });
  });

  group('LineAssembler', () {
    test('joins a line split across notifications', () {
      final a = LineAssembler();
      const line = '#CAL {"v":2,"open":[1,2,3,4,5],"fist":[6,7,8,9,10]}\n';
      final bytes = utf8.encode(line);
      expect(a.add(bytes.sublist(0, 20)), isEmpty);
      expect(a.add(bytes.sublist(20, 40)), isEmpty);
      expect(a.add(bytes.sublist(40)), [line.trim()]);
    });

    test('several lines in one notification, CRLF, blank lines', () {
      final a = LineAssembler();
      expect(a.add(utf8.encode('#OK STREAM\r\n\n#PONG\n#BAT')), [
        '#OK STREAM',
        '#PONG',
      ]);
      expect(a.add(utf8.encode(' LOW 3.38V\n')), ['#BAT LOW 3.38V']);
    });

    test('multi-byte UTF-8 split across notifications', () {
      final a = LineAssembler();
      final bytes = utf8.encode('#X é\n');
      expect(a.add(bytes.sublist(0, 4)), isEmpty);
      expect(a.add(bytes.sublist(4)), ['#X é']);
    });

    test('clear drops a half line; overlong lines are dropped', () {
      final a = LineAssembler()
        ..add(utf8.encode('#PO'))
        ..clear();
      expect(a.add(utf8.encode('NG\n')), ['NG']);
      final b = LineAssembler()
        ..add(List.filled(LineAssembler.maxLineBytes + 1, 65));
      expect(b.add(utf8.encode('#PONG\n')), ['#PONG']);
    });
  });
}

extension on Uint8List {
  void apply(void Function(Uint8List b) f) => f(this);
}
