@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';

import '../support/kit.dart';

/// Records what the service asks of the engine; outputs are pushed by tests.
class _FakeEngine implements RecognizerEngine {
  final calls = <String>[];
  final out = StreamController<EngineOutput>.broadcast(sync: true);

  @override
  Stream<EngineOutput> get outputs => out.stream;

  @override
  void setCalibration(GloveCalibration cal) => calls.add('cal');

  @override
  void clearCalibration() => calls.add('clear');

  @override
  void reset() => calls.add('reset');

  @override
  void feed(List<GloveSample> samples) => calls.add('feed ${samples.length}');

  @override
  Future<void> dispose() => out.close();
}

class _FakeSource implements GloveSource {
  final statusCtl = StreamController<GloveStatus>.broadcast(sync: true);
  final eventsCtl = StreamController<GloveEvent>.broadcast(sync: true);
  final samplesCtl = StreamController<List<GloveSample>>.broadcast(sync: true);
  GloveStatus current = const GloveStatus();

  void emit(GloveStatus s) {
    current = s;
    statusCtl.add(s);
  }

  @override
  GloveStatus get status => current;
  @override
  Stream<GloveStatus> get statusChanges => statusCtl.stream;
  @override
  Stream<GloveEvent> get events => eventsCtl.stream;
  @override
  Stream<List<GloveSample>> get samples => samplesCtl.stream;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _calJson =
    '{"v":2,"open":[1,2,3,4,5],"fist":[9,9,9,9,9],"gyro_bias_raw":[0,0,0],'
    '"roll_neutral":0,"roll_min":-45,"roll_max":45}';

void main() {
  group('RecognitionService', () {
    final labels = Labels.parse('one\ntwo\nrest\nother');

    test('calibration and resets follow the connection (no stale numbers)', () {
      final src = _FakeSource();
      final engine = _FakeEngine();
      RecognitionService(source: src, engine: engine, labels: labels);
      final cal = GloveCalibration.parse(_calJson);
      src
        ..emit(GloveStatus(phase: GlovePhase.ready, calibration: cal))
        ..emit(
          GloveStatus(phase: GlovePhase.ready, calibration: cal),
        ) // no change
        ..emit(const GloveStatus())
        ..emit(const GloveStatus(phase: GlovePhase.ready)); // reconnect, no cal
      src.eventsCtl.add(CalibrationEvent(cal));
      src.samplesCtl.add([GloveSample(0, Int16List(11))]);
      expect(engine.calls, [
        'clear', // start: no calibration known
        'cal', // ready with #CAL
        'reset', // streaming stopped: cancels a waiting word
        'clear', // reconnect with #CAL NONE: no old numbers
        'cal', // new #CAL
        'feed 1',
      ]);
    });

    test('a calibration known at start is applied', () {
      final src = _FakeSource()
        ..current = GloveStatus(
          phase: GlovePhase.ready,
          calibration: GloveCalibration.parse(_calJson),
        );
      final engine = _FakeEngine();
      RecognitionService(source: src, engine: engine, labels: labels);
      src.emit(src.current); // already ready: no extra reset
      expect(engine.calls, ['cal']);
    });

    test('maps engine output to events with the label probability', () async {
      final engine = _FakeEngine();
      final svc = RecognitionService(
        source: _FakeSource(),
        engine: engine,
        labels: labels,
      );
      final events = <RecognitionEvent>[];
      final ticks = <RecognitionTick>[];
      svc.events.listen(events.add);
      svc.ticks.listen(ticks.add);
      engine.out.add(
        EngineOutput([
          FeedResult(
            resetCancel: const DeciderEvent(DeciderEventKind.cancel, 'one'),
            steps: [
              RecognitionStep(
                step: 4,
                sampleCount: 140,
                smoothed: Float64List.fromList([.1, .8, .05, .05]),
                events: const [
                  DeciderEvent(DeciderEventKind.word, 'two'),
                  DeciderEvent(DeciderEventKind.tentative, 'one'),
                ],
              ),
            ],
          ),
        ], modelMicros: 25000),
      );
      expect(events.map((e) => (e.kind, e.label, e.step, e.probability)), [
        (DeciderEventKind.cancel, 'one', -1, null),
        (DeciderEventKind.word, 'two', 4, .8),
        (DeciderEventKind.tentative, 'one', 4, .1),
      ]);
      expect(events.map((e) => e.speaks), [false, true, false]);
      expect(ticks.single.step, 4);
      expect(svc.slowRuns, 1, reason: '25 ms for one run is over budget');
      engine.out.addError(const GloveDisconnectedFailure());
      engine.out.addError(StateError('x'));
      await svc.dispose();
    });
  });

  group('providers', () {
    test('GLOVE flag: mock | ble; default mock in debug, ble in release', () {
      expect(
        gloveKindFromEnvironment(define: 'mock', release: true),
        GloveSourceKind.mock,
      );
      expect(gloveKindFromEnvironment(define: 'ble'), GloveSourceKind.ble);
      expect(gloveKindFromEnvironment(), GloveSourceKind.mock);
      expect(gloveKindFromEnvironment(release: true), GloveSourceKind.ble);
      expect(
        gloveKindFromEnvironment(define: 'xyz', release: true),
        GloveSourceKind.ble,
      );
    });

    test('developer switch overrides the flag; mock controls only on mock', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(activeGloveKindProvider), GloveSourceKind.mock);
      expect(c.read(mockGloveProvider), isA<MockGlove>());
      expect(c.read(gloveSourceProvider), isA<GloveClient>());
      c.read(gloveSourceOverrideProvider.notifier).set(GloveSourceKind.ble);
      expect(c.read(activeGloveKindProvider), GloveSourceKind.ble);
      expect(c.read(mockGloveProvider), isNull);
      expect(c.read(gloveSourceProvider), isA<GloveClient>());
    });

    test(
      'until a BLE library is chosen, BLE says unsupported (never fakes)',
      () async {
        const t = PendingBleTransport();
        await expectLater(
          t.scan(timeout: const Duration(seconds: 1)),
          emitsError(isA<BluetoothUnavailableFailure>()),
        );
        await expectLater(
          t.open(const DiscoveredGlove(id: 'a', name: 'Ishara-0000', rssi: 0)),
          throwsA(isA<BluetoothUnavailableFailure>()),
        );
      },
    );
  });

  group('MockFeed', () {
    late Map<String, Recording> recs;
    setUpAll(() async {
      final lib = MockLibrary(readAsset);
      recs = {
        for (final f in [
          MockLibrary.restFile(MockPerson.a),
          MockLibrary.restFile(MockPerson.b),
          MockLibrary.practiceFile(MockPerson.a, 'yes'),
        ])
          f: await lib.load(f),
      };
    });

    MockFeed feed() {
      final lib = MockLibrary(readAsset);
      recs.forEach(lib.seed);
      return MockFeed(lib);
    }

    test('rest loops when idle; clips play after their idle time', () async {
      final f = feed();
      expect(() => f.take(1), throwsStateError);
      await f.prepare();
      final rest = recs[MockLibrary.restFile(MockPerson.a)]!;
      final yes = recs[MockLibrary.practiceFile(MockPerson.a, 'yes')]!;
      final first = f.take(rest.length + 3);
      expect(first[rest.length], rest.sample(0), reason: 'rest loops');
      final states = <MockFeedState>[];
      f.states.listen(states.add);
      await f.play([
        MockClip(
          MockLibrary.practiceFile(MockPerson.a, 'yes'),
          idleBefore: const Duration(milliseconds: 100),
        ),
      ]);
      expect(f.state.queued, 1);
      final next = f.take(5 + yes.length + 1);
      expect(next[5], yes.sample(0), reason: '5 idle samples = 100 ms');
      expect(next[5 + yes.length - 1], yes.sample(yes.length - 1));
      expect(states.last.clip, isNull, reason: 'back to rest after the clip');
      await f.dispose();
    });

    test('clear stops; person change switches calibration', () async {
      final f = feed();
      await f.play([MockClip(MockLibrary.practiceFile(MockPerson.a, 'yes'))]);
      await f.prepare();
      f.take(3);
      expect(f.state.clip, isNotNull);
      await f.clear();
      expect(f.state.clip, isNull);
      final a = await f.calibrationJson();
      await f.setPerson(MockPerson.b);
      expect(f.person, MockPerson.b);
      expect(await f.calibrationJson(), isNot(a));
      expect(MockPerson.b.dir, 'B');
      await f.dispose();
    });

    test('a practice cue on the real-glove path is a no-op', () {
      fakeAsync((async) {
        final c = GloveClient(const PendingBleTransport())..cuePractice('yes');
        async.flushMicrotasks();
        expect(c.status.phase, GlovePhase.idle);
      });
    });
  });
}
