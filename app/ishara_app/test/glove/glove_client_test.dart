// Fake-time tests start futures and drive them with async.elapse():
// discarding them here is intended.
// ignore_for_file: discarded_futures
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/glove_transport.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';

import '../support/kit.dart';

// ------------------------------------------------------------ scripted link

/// A link whose glove side is scripted by the test; it records every call.
class ScriptedLink implements GloveLink {
  new({this.info = '{"proto":1,"fw":"0.3.0","board":"xiao"}'});

  String info;
  final calls = <String>[];
  final events = StreamController<Uint8List>.broadcast(sync: true);
  final data = StreamController<Uint8List>.broadcast(sync: true);
  final _closed = Completer<void>();

  /// Replies per command (null = no reply).
  final Map<String, List<String>?> replies = {
    'GETCAL': ['#CAL NONE'],
    'STREAM 1': ['#OK STREAM'],
    'STREAM 0': ['#OK STREAM'],
  };
  List<String> onSubscribeEvents = ['#BAT NO_BATTERY (USB)'];

  void line(String l) => events.add(Uint8List.fromList(utf8.encode('$l\n')));

  @override
  int get mtu => 247;

  @override
  Future<Uint8List> readInfo() async {
    calls.add('readInfo');
    return Uint8List.fromList(utf8.encode(info));
  }

  @override
  Stream<Uint8List> get eventNotifications => events.stream;

  @override
  Stream<Uint8List> get dataNotifications => data.stream;

  @override
  Future<void> subscribeEvents() async {
    calls.add('subscribeEvents(listening=${events.hasListener})');
    onSubscribeEvents.forEach(line);
  }

  @override
  Future<void> subscribeData() async {
    calls.add('subscribeData(listening=${data.hasListener})');
  }

  @override
  Future<void> writeCommand(Uint8List bytes) async {
    final cmd = utf8.decode(bytes);
    calls.add('write $cmd');
    replies[cmd]?.forEach(line);
  }

  @override
  Future<void> get closed => _closed.future;

  void drop() {
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> close() async {
    calls.add('close');
    drop();
  }
}

class ScriptedTransport implements GloveTransport {
  new(this.link);
  final ScriptedLink link;
  Exception? openError;

  @override
  Stream<List<DiscoveredGlove>> scan({required Duration timeout}) async* {
    yield [const DiscoveredGlove(id: 'x', name: 'Ishara-3FA2', rssi: -60)];
  }

  @override
  Future<GloveLink> open(DiscoveredGlove glove) async {
    link.calls.add('open');
    final e = openError;
    if (e != null) throw e;
    return link;
  }
}

const _glove = DiscoveredGlove(id: 'x', name: 'Ishara-3FA2', rssi: -60);

const _calJson =
    '{"v":2,"open":[2234.0,2608.0,2443.0,2412.0,2674.0],'
    '"fist":[1625.0,1661.0,1815.0,1560.0,1907.0],'
    '"gyro_bias_raw":[-205.5,302.9,-218.4],"roll_neutral":0.0,'
    '"roll_min":-45.0,"roll_max":45.0}';

void main() {
  group('connection setup (BLE-CONTRACT §3)', () {
    test('runs the steps in contract order and ends streaming', () {
      fakeAsync((async) {
        final link = ScriptedLink();
        final c = GloveClient(ScriptedTransport(link));
        final phases = <GlovePhase>[];
        c.statusChanges.listen((s) => phases.add(s.phase));
        c.connect(_glove);
        async.flushMicrotasks();
        expect(link.calls, [
          'open',
          'readInfo',
          'subscribeEvents(listening=true)', // listening before subscribing
          'subscribeData(listening=true)',
          'write GETCAL',
          'write STREAM 1',
        ]);
        expect(c.status.phase, GlovePhase.ready);
        expect(c.status.info!.board, 'xiao');
        expect(c.status.battery!.level, BatteryLevel.usb);
        expect(c.status.storedCalibration, StoredCalibration.none);
        expect(
          phases.toSet(),
          containsAll([
            GlovePhase.linking,
            GlovePhase.checkingSensors,
            GlovePhase.readingCalibration,
            GlovePhase.ready,
          ]),
        );
        expect(
          phases.indexOf(GlovePhase.linking),
          lessThan(phases.indexOf(GlovePhase.checkingSensors)),
        );
      });
    });

    test('proto != 1: protocol failure, no streaming, link closed', () {
      fakeAsync((async) {
        final link = ScriptedLink(info: '{"proto":2,"fw":"9.0.0"}');
        final c = GloveClient(ScriptedTransport(link));
        Object? error;
        c.connect(_glove).catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isA<GloveProtocolMismatchFailure>());
        expect((error! as GloveProtocolMismatchFailure).proto, 2);
        expect(link.calls, isNot(contains('write STREAM 1')));
        expect(link.calls.last, 'close');
        expect(c.status.phase, GlovePhase.idle);
        expect(c.status.failure, isA<GloveProtocolMismatchFailure>());
      });
    });

    test('INFO that is not JSON, or not an object, fails cleanly', () {
      for (final info in ['nope', '[1]']) {
        fakeAsync((async) {
          final c = GloveClient(ScriptedTransport(ScriptedLink(info: info)));
          Object? error;
          c.connect(_glove).catchError((Object e) => error = e);
          async.flushMicrotasks();
          expect(error, isA<GloveConnectFailure>(), reason: info);
        });
      }
    });

    test('unknown INFO fields are ignored, missing ones default', () {
      fakeAsync((async) {
        final link = ScriptedLink(info: '{"proto":1,"future":{"x":1}}');
        final c = GloveClient(ScriptedTransport(link))..connect(_glove);
        async.flushMicrotasks();
        expect(c.status.phase, GlovePhase.ready);
        expect(c.status.info!.firmware, '');
        expect(c.status.info!.rateHz, 50);
      });
    });

    test('transport failure keeps its type', () {
      fakeAsync((async) {
        final t = ScriptedTransport(ScriptedLink())
          ..openError = const GloveConnectFailure('no services');
        final c = GloveClient(t);
        Object? error;
        c.connect(_glove).catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isA<GloveConnectFailure>());
        expect(c.status.failure, isA<GloveConnectFailure>());
      });
    });

    test('no #BAT: setup waits at most firstBatteryWait, then goes on', () {
      fakeAsync((async) {
        final link = ScriptedLink()..onSubscribeEvents = [];
        final c = GloveClient(ScriptedTransport(link))..connect(_glove);
        async.flushMicrotasks();
        expect(c.status.phase, GlovePhase.checkingSensors);
        async.elapse(const Duration(seconds: 2));
        expect(c.status.phase, GlovePhase.ready);
        expect(c.status.battery, isNull);
      });
    });

    test('#MPU FAIL after subscribing is reported in the status', () {
      fakeAsync((async) {
        final link = ScriptedLink()
          ..onSubscribeEvents = ['#BAT OK 3.92V 78%', '#MPU FAIL'];
        final c = GloveClient(ScriptedTransport(link))..connect(_glove);
        async.flushMicrotasks();
        expect(c.status.mpuFail, isTrue);
        expect(c.status.battery!.percent, 78);
      });
    });

    test('GETCAL timeout fails the connection with a timeout failure', () {
      fakeAsync((async) {
        final link = ScriptedLink()..replies['GETCAL'] = null;
        final c = GloveClient(ScriptedTransport(link));
        Object? error;
        c.connect(_glove).catchError((Object e) => error = e);
        async.elapse(const Duration(seconds: 2));
        expect(error, isA<GloveCommandTimeoutFailure>());
        expect((error! as GloveCommandTimeoutFailure).command, 'GETCAL');
        expect(c.status.phase, GlovePhase.idle);
      });
    });

    test('STREAM 1 refused (#ERR STREAM MTU) fails with the reason', () {
      fakeAsync((async) {
        final link = ScriptedLink()..replies['STREAM 1'] = ['#ERR STREAM MTU'];
        final c = GloveClient(ScriptedTransport(link));
        Object? error;
        c.connect(_glove).catchError((Object e) => error = e);
        async.flushMicrotasks();
        final f = error! as GloveCommandRejectedFailure;
        expect([f.error.command, f.error.reason], ['STREAM', 'MTU']);
      });
    });
  });

  group('while connected', () {
    late ScriptedLink link;
    late GloveClient c;

    void connect(FakeAsync async) {
      link = ScriptedLink()..replies['GETCAL'] = ['#CAL $_calJson'];
      c = GloveClient(ScriptedTransport(link))..connect(_glove);
      async.flushMicrotasks();
      expect(c.status.phase, GlovePhase.ready);
    }

    test('GETCAL #CAL sets the calibration', () {
      fakeAsync((async) {
        connect(async);
        expect(c.status.storedCalibration, StoredCalibration.present);
        expect(c.status.calibration!.open.first, 2234);
      });
    });

    test('DATA frames become samples; bad frames are dropped and counted', () {
      fakeAsync((async) {
        connect(async);
        final got = <List<GloveSample>>[];
        c.samples.listen(got.add);
        final frame = FrameCodec.encode([
          GloveSample(10, Int16List(11)..[0] = 1),
          GloveSample(11, Int16List(11)..[0] = 2),
        ]);
        link.data
          ..add(frame)
          ..add(Uint8List.fromList([9, 9, 9]));
        expect(got.single.map((s) => s.seq), [10, 11]);
        expect(c.badFrames, 1);
      });
    });

    test('a #CAL line split across notifications arrives once', () {
      fakeAsync((async) {
        connect(async);
        final got = <GloveEvent>[];
        c.events.listen(got.add);
        final bytes = utf8.encode('#CAL $_calJson\n');
        for (var i = 0; i < bytes.length; i += 20) {
          link.events.add(
            Uint8List.fromList(
              bytes.sublist(i, (i + 20).clamp(0, bytes.length)),
            ),
          );
        }
        expect(got.whereType<CalibrationEvent>(), hasLength(1));
      });
    });

    test('unknown and broken lines are ignored', () {
      fakeAsync((async) {
        connect(async);
        final got = <GloveEvent>[];
        c.events.listen(got.add);
        link
          ..line('#NEWTHING 1 2 3')
          ..line('#CAL {"v":2}')
          ..line('#PONG');
        expect(got.single, isA<PongEvent>());
        expect(c.status.phase, GlovePhase.ready);
      });
    });

    test('unsolicited #ERR STREAM MTU is reported as a failure', () {
      fakeAsync((async) {
        connect(async);
        link.line('#ERR STREAM MTU');
        async.flushMicrotasks();
        expect(c.status.failure, isA<GloveCommandRejectedFailure>());
        expect(c.status.phase, GlovePhase.idle, reason: 'streaming stopped');
        expect(link.calls.last, 'close');
      });
    });

    test('battery state changes update the status', () {
      fakeAsync((async) {
        connect(async);
        link.line('#BAT LOW 3.38V');
        expect(c.status.battery!.level, BatteryLevel.low);
      });
    });

    test(
      'commands: BAT, PING, CAL CANCEL; replies are matched per command',
      () {
        fakeAsync((async) {
          connect(async);
          link.replies
            ..['BAT'] = ['#BAT OK 4.01V 90%']
            ..['PING'] =
                ['#BAT LOW 3.3V', '#PONG'] // a #BAT isn't PING's reply
            ..['CAL CANCEL'] = ['#OK CAL'];
          BatteryEvent? bat;
          c.readBattery().then((b) => bat = b);
          var pong = false;
          c.ping().then((_) => pong = true);
          var cancelled = false;
          c.cancelCalibration().then((_) => cancelled = true);
          async.flushMicrotasks();
          expect(bat!.percent, 90);
          expect(pong, isTrue);
          expect(cancelled, isTrue);
        });
      },
    );

    test('calibration step: reply after capture, weak fingers attached', () {
      fakeAsync((async) {
        connect(async);
        link.replies['CAL FIST'] = null;
        CalStepResult? r;
        c.calibrate(CalStep.fist).then((v) => r = v);
        async.elapse(const Duration(seconds: 2));
        link
          ..line('#FLEX WEAK 1')
          ..line('#FLEX WEAK 4')
          ..line('#CALSTEP FIST OK');
        async.flushMicrotasks();
        expect(r!.ok, isTrue);
        expect(r!.weakFingers, [1, 4]);
      });
    });

    test('calibration step failure and rejection', () {
      fakeAsync((async) {
        connect(async);
        link.replies
          ..['CAL TURN'] = ['#CALSTEP TURN FAIL RANGE']
          ..['CAL SAVE'] = ['#ERR CAL MISSING OPEN'];
        CalStepResult? r;
        c.calibrate(CalStep.turn).then((v) => r = v);
        Object? saveError;
        c.saveCalibration().catchError((Object e) {
          saveError = e;
          return Future<Never>.error(e);
        }).ignore();
        async.flushMicrotasks();
        expect([r!.ok, r!.reason], [false, 'RANGE']);
        expect(
          (saveError! as GloveCommandRejectedFailure).error.reason,
          'MISSING OPEN',
        );
      });
    });

    test('CAL SAVE returns the new calibration', () {
      fakeAsync((async) {
        connect(async);
        link.replies['CAL SAVE'] = ['#CAL $_calJson'];
        Object? cal;
        c.saveCalibration().then((v) => cal = v);
        async.flushMicrotasks();
        expect(cal, isNotNull);
      });
    });

    test('link lost: pending command fails, status says disconnected', () {
      fakeAsync((async) {
        connect(async);
        link.replies['BAT'] = null;
        Object? error;
        c.readBattery().catchError((Object e) {
          error = e;
          return const BatteryEvent(BatteryLevel.usb);
        });
        async.flushMicrotasks();
        link.drop();
        async.flushMicrotasks();
        expect(error, isA<GloveDisconnectedFailure>());
        expect(c.status.phase, GlovePhase.idle);
        expect(c.status.failure, isA<GloveDisconnectedFailure>());
        Object? after;
        c.readBattery().catchError((Object e) {
          after = e;
          return const BatteryEvent(BatteryLevel.usb);
        });
        async.flushMicrotasks();
        expect(after, isA<GloveDisconnectedFailure>());
      });
    });

    test('disconnect: STREAM 0, close, no failure', () {
      fakeAsync((async) {
        connect(async);
        c.disconnect();
        async.flushMicrotasks();
        expect(link.calls.sublist(link.calls.length - 2), [
          'write STREAM 0',
          'close',
        ]);
        expect(c.status.phase, GlovePhase.idle);
        expect(c.status.failure, isNull);
        expect(c.status.device, _glove);
      });
    });

    test('scan sets scanning, then idle', () {
      fakeAsync((async) {
        final c = GloveClient(ScriptedTransport(ScriptedLink()));
        final phases = <GlovePhase>[];
        c.statusChanges.listen((s) => phases.add(s.phase));
        List<DiscoveredGlove>? found;
        c.scan().listen((l) => found = l);
        async.flushMicrotasks();
        expect(found, [_glove]);
        expect(phases, [GlovePhase.scanning, GlovePhase.idle]);
      });
    });
  });

  group('with the mock glove', () {
    late Map<String, Recording> recs;
    setUpAll(() async {
      final lib = MockLibrary(readAsset);
      recs = {
        for (final p in MockPerson.values)
          MockLibrary.restFile(p): await lib.load(MockLibrary.restFile(p)),
      };
    });

    MockGlove newGlove() {
      final lib = MockLibrary(readAsset);
      recs.forEach(lib.seed);
      return MockGlove(MockFeed(lib));
    }

    test(
      'streams exactly 50 samples per second in 5-sample frames, seq in order',
      () {
        fakeAsync((async) {
          final glove = newGlove();
          final c = GloveClient(glove);
          final frames = <List<GloveSample>>[];
          c.samples.listen(frames.add);
          c.connect(glove.device);
          async.elapse(const Duration(seconds: 1));
          frames.clear();
          async.elapse(const Duration(seconds: 10));
          final all = frames.expand((f) => f).toList();
          expect(all.length, inInclusiveRange(495, 505));
          expect(frames.every((f) => f.length == 5), isTrue);
          for (var i = 1; i < all.length; i++) {
            expect(all[i].seq, (all[i - 1].seq + 1) & 0xFFFF);
          }
          c.disconnect();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test(
      'scan finds Ishara-M0CK after the delay; switched off = not found',
      () {
        fakeAsync((async) {
          final glove = newGlove();
          final c = GloveClient(glove);
          final lists = <List<DiscoveredGlove>>[];
          c.scan(timeout: const Duration(seconds: 5)).listen(lists.add);
          async.elapse(const Duration(seconds: 6));
          expect(lists.last.single.name, 'Ishara-M0CK');
          expect(IsharaUuids.namePattern.hasMatch('Ishara-3FA2'), isTrue);

          glove.advertising = false;
          lists.clear();
          c.scan(timeout: const Duration(seconds: 5)).listen(lists.add);
          async.elapse(const Duration(seconds: 6));
          expect(lists.last, isEmpty);
        });
      },
    );

    test('full calibration flow, with FLEX WEAK and a failing step', () {
      fakeAsync((async) {
        final glove = newGlove()
          ..calibrated = false
          ..weakFingers = [2]
          ..failNextStep[CalStep.turn] = 'RANGE';
        final c = GloveClient(glove)..connect(glove.device);
        async.elapse(const Duration(seconds: 1));
        expect(c.status.storedCalibration, StoredCalibration.none);
        final results = <CalStepResult>[];
        Future<void> step(CalStep s) => c.calibrate(s).then(results.add);
        step(CalStep.open);
        async.elapse(const Duration(seconds: 2));
        step(CalStep.fist);
        async.elapse(const Duration(seconds: 2));
        step(CalStep.turn);
        async.elapse(const Duration(seconds: 3));
        expect(results.map((r) => [r.step, r.ok, r.reason, r.weakFingers]), [
          [CalStep.open, true, null, <int>[]],
          [
            CalStep.fist,
            true,
            null,
            [2],
          ],
          [CalStep.turn, false, 'RANGE', <int>[]],
        ]);
        Object? saveError;
        c.saveCalibration().catchError((Object e) {
          saveError = e;
          return Future<Never>.error(e);
        }).ignore();
        async.flushMicrotasks();
        expect(
          (saveError! as GloveCommandRejectedFailure).error.reason,
          'MISSING TURN',
        );
        step(CalStep.turn);
        async.elapse(const Duration(seconds: 3));
        Object? saved;
        c.saveCalibration().then((v) => saved = v);
        async.flushMicrotasks();
        expect(saved, isNotNull);
        expect(c.status.storedCalibration, StoredCalibration.present);
        c.disconnect();
        async.elapse(const Duration(seconds: 1));
      });
    });

    test(
      'MPU missing: #MPU FAIL at subscribe, OPEN/TURN fail at once with MPU',
      () {
        fakeAsync((async) {
          final glove = newGlove()..mpuFail = true;
          final c = GloveClient(glove)..connect(glove.device);
          async.elapse(const Duration(seconds: 1));
          expect(c.status.mpuFail, isTrue);
          CalStepResult? r;
          c.calibrate(CalStep.open).then((v) => r = v);
          async.flushMicrotasks();
          expect([r!.ok, r!.reason], [false, 'MPU']);
          c.disconnect();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test('drop link, reconnect, CAL CANCEL during a step', () {
      fakeAsync((async) {
        final glove = newGlove();
        final c = GloveClient(glove)..connect(glove.device);
        async.elapse(const Duration(seconds: 1));
        glove.dropLink();
        async.flushMicrotasks();
        expect(c.status.failure, isA<GloveDisconnectedFailure>());
        c.connect(glove.device);
        async.elapse(const Duration(seconds: 1));
        expect(c.status.phase, GlovePhase.ready);
        CalStepResult? r;
        c.calibrate(CalStep.open).then((v) => r = v);
        async.elapse(const Duration(milliseconds: 500));
        c.cancelCalibration();
        async.flushMicrotasks();
        expect([r!.ok, r!.reason], [false, 'CANCELLED']);
        c.disconnect();
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('battery change and person change are reported', () {
      fakeAsync((async) {
        final glove = newGlove();
        final c = GloveClient(glove)..connect(glove.device);
        async.elapse(const Duration(seconds: 1));
        final cal0 = c.status.calibration!;
        glove.setBattery('#BAT LOW 3.38V');
        expect(c.status.battery!.level, BatteryLevel.low);
        glove.setPerson(MockPerson.b);
        async.flushMicrotasks();
        expect(c.status.calibration, isNot(cal0));
        c.disconnect();
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('second central is refused; unknown commands get #ERR', () {
      fakeAsync((async) {
        final glove = newGlove();
        final c = GloveClient(glove)..connect(glove.device);
        async.elapse(const Duration(seconds: 1));
        Object? error;
        glove.open(glove.device).catchError((Object e) {
          error = e;
          return Future<GloveLink>.error(e);
        }).ignore();
        async.elapse(const Duration(seconds: 1));
        expect(error, isA<GloveConnectFailure>());
        final got = <GloveEvent>[];
        c.events.listen(got.add);
        // Through the client's link: a raw command the client never sends.
        c.disconnect();
        async.elapse(const Duration(seconds: 1));
      });
    });
  });
}
