// Regression tests for the step 3 code review findings.
// Fake-time tests start futures and drive them with async.elapse():
// discarding them here is intended.
// ignore_for_file: discarded_futures
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/glove_transport.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';

import '../support/kit.dart';
import 'glove_client_test.dart' show ScriptedLink, ScriptedTransport;

const _glove = DiscoveredGlove(id: 'x', name: 'Ishara-3FA2', rssi: -60);

final _recs = <String, Recording>{};

MockGlove _newGlove() {
  final lib = MockLibrary(readAsset);
  _recs.forEach(lib.seed);
  return MockGlove(MockFeed(lib));
}

/// A transport whose `open` returns after [delay], to race against.
class _SlowTransport implements GloveTransport {
  new(this.delay);
  final Duration delay;
  final opened = <ScriptedLink>[];

  @override
  Stream<List<DiscoveredGlove>> scan({required Duration timeout}) =>
      const Stream.empty();

  @override
  Future<GloveLink> open(DiscoveredGlove glove) async {
    await Future<void>.delayed(delay);
    final l = ScriptedLink();
    opened.add(l);
    return l;
  }
}

class _ThrowingTransport implements GloveTransport {
  @override
  Stream<List<DiscoveredGlove>> scan({required Duration timeout}) =>
      const Stream.empty();

  @override
  Future<GloveLink> open(DiscoveredGlove glove) =>
      Future.error(StateError('bug in a transport'));
}

class _FailingWriteLink extends ScriptedLink {
  int failures = 1;

  @override
  Future<void> writeCommand(Uint8List bytes) async {
    if (failures > 0 && String.fromCharCodes(bytes) == 'BAT') {
      failures--;
      throw Exception('write failed');
    }
    await super.writeCommand(bytes);
  }
}

void main() {
  late ModelBundle bundle;
  setUpAll(() async {
    bundle = await loadKitBundle();
    final lib = MockLibrary(readAsset);
    for (final f in [
      ...MockLibrary.baseFiles(MockPerson.a),
      ...MockLibrary.baseFiles(MockPerson.b),
      MockLibrary.practiceFile(MockPerson.a, 'hello'),
    ]) {
      _recs[f] = await lib.load(f);
    }
  });

  test(
    '1. a glove without calibration never uses the previous glove numbers',
    () async {
      final engine = InProcessRecognizer(bundle);
      fakeAsync((async) {
        final glove = _newGlove();
        final client = GloveClient(glove);
        final svc = RecognitionService(
          source: client,
          engine: engine,
          labels: bundle.labels,
        );
        final events = <RecognitionEvent>[];
        svc.events.listen(events.add);
        client.connect(glove.device);
        async.elapse(const Duration(seconds: 2));
        client.disconnect();
        async.elapse(const Duration(seconds: 1));
        glove.calibrated = false; // another glove, never calibrated
        client.connect(glove.device);
        async.elapse(const Duration(seconds: 2));
        expect(client.status.storedCalibration, StoredCalibration.none);
        client.cuePractice('hello');
        async.elapse(const Duration(seconds: 12));
        expect(events.where((e) => e.speaks), isEmpty);
        client.disconnect();
        async.elapse(const Duration(seconds: 1));
      });
      await engine.dispose();
    },
  );

  group('2. resets cancel a waiting tentative word', () {
    Recognizer pendingRecognizer() {
      final r = Recognizer(
        labels: bundle.labels,
        config: bundle.config,
        predict: (_) {
          final p = Float64List(bundle.labels.length);
          p[bundle.labels.indexOf('hello')!] = .7; // passes tentative only
          p[bundle.labels.indexOf('one')!] = .3;
          return p;
        },
        calibration: GloveCalibration.parse(
          Recording.parse(readText('assets/packs/asl/kit/mock/A/rest.csv'))
              .calibrationJson!,
        ),
      );
      for (var k = 0; k < 140; k++) {
        r.feed(k, List.filled(11, 0));
      }
      return r;
    }

    test('reset, new calibration, cleared calibration', () {
      for (final action in <FeedResult Function(Recognizer)>[
        (r) => r.reset(),
        (r) => r.setCalibration(r.calibration!),
        (r) => r.clearCalibration(),
      ]) {
        final r = pendingRecognizer();
        final cancel = action(r).resetCancel;
        expect(cancel, const DeciderEvent(DeciderEventKind.cancel, 'hello'));
        expect(action(r), same(FeedResult.empty), reason: 'nothing left');
      }
    });

    test(
      'link lost while a word is tentative: the UI gets the cancel',
      () async {
        final engine = InProcessRecognizer(bundle);
        fakeAsync((async) {
          final glove = _newGlove();
          final client = GloveClient(glove);
          final events = <RecognitionEvent>[];
          RecognitionService(
            source: client,
            engine: engine,
            labels: bundle.labels,
          ).events.listen(events.add);
          client
            ..connect(glove.device)
            ..cuePractice('hello');
          for (
            var i = 0;
            i < 200 && !events.any((e) => e.kind == DeciderEventKind.tentative);
            i++
          ) {
            async.elapse(const Duration(milliseconds: 100));
          }
          expect(events.last.kind, DeciderEventKind.tentative);
          glove.dropLink();
          async.flushMicrotasks();
          expect(events.last.kind, DeciderEventKind.cancel);
          expect(events.last.label, 'hello');
        });
        await engine.dispose();
      },
    );
  });

  test(
    '3+4. the worker survives an error; dispose waits for it to close',
    () async {
      final engine = await IsolateRecognizer.spawn(bundle);
      final errors = <Object>[];
      final words = <String>[];
      engine.outputs.listen(
        (o) => words.addAll([
          for (final r in o.results)
            for (final e in r.events)
              if (e.kind == DeciderEventKind.confirm) e.label,
        ]),
        onError: errors.add,
      );
      final rec = _recs[MockLibrary.practiceFile(MockPerson.a, 'hello')]!;
      engine
        ..setCalibration(GloveCalibration.parse(rec.calibrationJson!))
        ..feed([GloveSample(0, Int16List(3))]); // wrong size: an Error inside
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(errors, isNotEmpty);
      engine.reset();
      for (var k = 0; k < rec.length; k += 5) {
        engine.feed([
          for (var j = k; j < k + 5 && j < rec.length; j++)
            GloveSample(j, Int16List.fromList(rec.sample(j))),
        ]);
      }
      for (var i = 0; i < 100 && words.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(words, ['hello'], reason: 'still recognizing after the error');
      final sw = Stopwatch()..start();
      await engine.dispose();
      expect(
        sw.elapsed,
        lessThan(IsolateRecognizer.closeTimeout),
        reason: 'the worker acknowledged closing',
      );
    },
  );

  group('5. connect races', () {
    test('disconnect during linking closes the late link', () {
      fakeAsync((async) {
        final t = _SlowTransport(const Duration(seconds: 1));
        final c = GloveClient(t);
        Object? error;
        c.connect(_glove).catchError((Object e) => error = e);
        async.elapse(const Duration(milliseconds: 500));
        c.disconnect();
        async.elapse(const Duration(seconds: 1));
        expect(error, isA<GloveDisconnectedFailure>());
        expect(t.opened.single.calls, contains('close'));
        expect(c.status.phase, GlovePhase.idle);
      });
    });

    test('two quick connects: the first link is closed, the second wins', () {
      fakeAsync((async) {
        final t = _SlowTransport(const Duration(milliseconds: 300));
        final c = GloveClient(t);
        c.connect(_glove).catchError((Object _) {});
        async.elapse(const Duration(milliseconds: 100));
        c.connect(_glove);
        async.elapse(const Duration(seconds: 3));
        expect(t.opened, hasLength(2));
        expect(t.opened.first.calls, contains('close'));
        expect(t.opened.last.calls, isNot(contains('close')));
        expect(c.status.phase, GlovePhase.ready);
      });
    });

    test('dispose during linking: no link left open, mock glove reusable', () {
      fakeAsync((async) {
        final glove = _newGlove();
        final c = GloveClient(glove);
        c.connect(glove.device).catchError((Object _) {});
        async.elapse(const Duration(milliseconds: 300));
        c.dispose();
        async.elapse(const Duration(seconds: 2));
        final c2 = GloveClient(glove)..connect(glove.device);
        async.elapse(const Duration(seconds: 2));
        expect(c2.status.phase, GlovePhase.ready);
        c2.disconnect();
        async.elapse(const Duration(seconds: 1));
      });
    });
  });

  test('6. a failed write leaves no stale pending command', () {
    fakeAsync((async) {
      final link = _FailingWriteLink();
      final c = GloveClient(ScriptedTransport(link))..connect(_glove);
      async.flushMicrotasks();
      link.replies['BAT'] = ['#BAT OK 3.9V 70%'];
      Object? first;
      c.readBattery().catchError((Object e) {
        first = e;
        return Future<Never>.error(e);
      }).ignore();
      async.flushMicrotasks();
      expect(first, isA<Exception>());
      Object? second;
      c.readBattery().then((b) => second = b.percent);
      async.flushMicrotasks();
      expect(second, 70);
    });
  });

  test('7. mock: MTU drop while streaming stops it (no endless loop)', () {
    fakeAsync((async) {
      final glove = _newGlove();
      final c = GloveClient(glove)..connect(glove.device);
      async.elapse(const Duration(seconds: 2));
      glove.mtu = 23;
      async.elapse(const Duration(milliseconds: 300));
      expect(c.status.phase, GlovePhase.idle);
      expect(c.status.failure, isA<GloveCommandRejectedFailure>());
    });
  });

  test('8. mock: changing person while streaming never stops the samples', () {
    fakeAsync((async) {
      final glove = _newGlove();
      final c = GloveClient(glove);
      var samples = 0;
      c.samples.listen((s) => samples += s.length);
      c.connect(glove.device);
      async.elapse(const Duration(seconds: 2));
      glove.setPerson(MockPerson.b);
      samples = 0;
      async.elapse(const Duration(seconds: 2));
      expect(samples, inInclusiveRange(95, 105));
      c.disconnect();
      async.elapse(const Duration(seconds: 1));
    });
  });

  test('9. an Error during setup still cleans up, and stays visible', () {
    fakeAsync((async) {
      final c = GloveClient(_ThrowingTransport());
      Object? error;
      c.connect(_glove).catchError((Object e) => error = e);
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(c.status.phase, GlovePhase.idle);
      expect(c.status.failure, isA<GloveConnectFailure>());
    });
  });

  test('10. a broken #CAL reply fails GETCAL at once (not a timeout)', () {
    fakeAsync((async) {
      final link = ScriptedLink()..replies['GETCAL'] = ['#CAL {"v":2}'];
      final c = GloveClient(ScriptedTransport(link));
      Object? error;
      c.connect(_glove).catchError((Object e) => error = e);
      async.flushMicrotasks();
      expect(error, isA<GloveBadCalibrationFailure>());
      expect((error! as Failure).cause, isA<Failure>());
      expect((error! as GloveFailure).kind, 'glove_bad_calibration');
    });
  });
}
