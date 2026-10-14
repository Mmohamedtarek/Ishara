import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/live_hand.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';

import '../support/kit.dart';

var _seq = 0;
GloveSample _s({
  List<int> flex = const [0, 0, 0, 0, 0],
  int ay = 0,
  int az = 8192,
  int gx = 0,
  int gy = 0,
  int gz = 0,
}) => GloveSample(_seq++, Int16List.fromList([...flex, 0, ay, az, gx, gy, gz]));

void main() {
  test('still: every gyro axis under 3 °/s std over the last 2 s', () {
    final h = LiveHand();
    expect(h.still, isNull);
    for (var i = 0; i < 100; i++) {
      h.add(_s(gx: i.isEven ? 100 : -100)); // std 100 counts = 1.53 °/s
    }
    expect(h.still, isTrue);
    for (var i = 0; i < 100; i++) {
      h.add(_s(gz: i.isEven ? 250 : -250)); // 3.82 °/s on z
    }
    expect(h.still, isFalse);
    // only the last 100 samples count: back to still
    for (var i = 0; i < 100; i++) {
      h.add(_s());
    }
    expect(h.still, isTrue);
  });

  test('roll: accel roll at rest, the firmware filter while turning', () {
    final h = LiveHand();
    // 30° of roll from gravity: ay = sin, az = cos
    final ay = (8192 * math.sin(30 * math.pi / 180)).round();
    final az = (8192 * math.cos(30 * math.pi / 180)).round();
    h.add(_s(ay: ay, az: az));
    expect(h.rotation, closeTo(30, .05));
    // turning at 100 °/s on gyro X with the accel unchanged: the filter moves
    // 98 % with the gyro each sample
    h.add(_s(ay: ay, az: az, gx: 6550));
    final acc = LiveHand.accelRollDeg(ay.toDouble(), az.toDouble());
    final predicted = acc + 100 * .02;
    expect(h.rotation, closeTo(predicted + .02 * (acc - predicted), 1e-9));
  });

  test('wrap keeps angles in (-180, 180]', () {
    expect(LiveHand.wrap(190), -170);
    expect(LiveHand.wrap(-190), 170);
    expect(LiveHand.wrap(180), 180);
    expect(LiveHand.wrap(-180), 180);
  });

  test('finger bars from captured open / fist medians; weak fingers have '
      'none', () {
    final h = LiveHand();
    expect(h.fingers, isNull);
    final open = StepCapture(h);
    for (final f in [
      [1000, 1000, 1000, 1000, 1000],
      [1010, 990, 1000, 1000, 1000],
      [1020, 1000, 1000, 1000, 1000],
    ]) {
      open.add(_s(flex: f, gx: 13, gy: -7, gz: 2));
    }
    open.applyAsOpen();
    final fist = StepCapture(h)
      ..add(_s(flex: [3010, 2000, 3000, 1200, 1000]))
      ..applyAsFist();
    expect(h.weakFingers, [3, 4]); // 200 and 0 counts apart
    h.add(_s(flex: [2010, 1500, 4000, 1100, 900]));
    expect(h.fingers, [.5, .5, 1.0, null, null]);
    expect(fist.length, 1);
    h.resetReferences();
    expect(h.fingers, isNull);
  });

  test('OPEN gives the gyro bias and the neutral roll', () {
    final h = LiveHand();
    final ay = (8192 * math.sin(-20 * math.pi / 180)).round();
    final az = (8192 * math.cos(-20 * math.pi / 180)).round();
    final open = StepCapture(h);
    for (var i = 0; i < 10; i++) {
      open.add(_s(ay: ay, az: az, gx: 40));
    }
    open.applyAsOpen();
    // at neutral and still (gyro = bias): rotation 0, it doesn't drift
    for (var i = 0; i < 50; i++) {
      h.add(_s(ay: ay, az: az, gx: 40));
    }
    expect(h.rotation, closeTo(0, .05));
  });

  test('a stored calibration gives the references', () {
    final h = LiveHand()
      ..useCalibration(
        GloveCalibration.parse(
          '{"v":2,"open":[0,0,0,0,0],"fist":[1000,1000,1000,1000,100],'
          '"gyro_bias_raw":[0,0,0],"roll_neutral":10,"roll_min":-40,'
          '"roll_max":50}',
        ),
      )
      ..add(_s(flex: [250, 500, 750, 1000, 50]));
    expect(h.fingers, [.25, .5, .75, 1.0, null]);
    expect(h.rotation, closeTo(-10, .05));
  });

  // Kit v3.2.3: calibration/turn.csv is a symmetric ±42° sweep (roll =
  // atan2(ay, az), gyro X turning with it, the raw gyro bias included). The
  // app's live roll, from the start of the TURN step, must show it. Before
  // TURN the mock glove plays rest.csv (≈ −93° roll), as on the device.
  for (final person in MockPerson.values) {
    for (final restSamples in [0, 37, 100, 411]) {
      test("person ${person.dir}: TURN shows turn.csv's ±42° "
          '(after $restSamples rest samples)', () async {
        final lib = MockLibrary(readAsset);
        Future<Recording> rec(String f) => lib.load('${person.dir}/$f');
        final open = await rec('calibration/open.csv');
        final rest = await rec('rest.csv');
        final turn = await rec('calibration/turn.csv');
        var seq = 0;
        GloveSample at(Recording r, int i) =>
            GloveSample(seq++, Int16List.fromList(r.sample(i % r.length)));

        // OPEN, captured on the phone (bias and neutral roll)
        final hand = LiveHand()..restartStillWindow();
        final cap = StepCapture(hand);
        for (var i = 0; i < 100; i++) {
          final s = at(open, i);
          hand.add(s);
          cap.add(s);
        }
        cap.applyAsOpen();
        for (var i = 0; i < restSamples; i++) {
          hand.add(at(rest, i));
        }
        // TURN starts (CalibrationController.capture)
        hand
          ..restartStillWindow()
          ..restartRoll();
        final seen = <double>[];
        for (var i = 0; i < 150; i++) {
          hand.add(at(turn, i));
          seen.add(hand.rotation!);
        }
        final lo = seen.reduce(math.min);
        final hi = seen.reduce(math.max);
        expect(lo, closeTo(-42, 3));
        expect(hi, closeTo(42, 3));
      });
    }
  }
}
