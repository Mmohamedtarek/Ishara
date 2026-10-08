// Fake-time tests start futures and drive them with async.elapse():
// discarding them here is intended.
// ignore_for_file: discarded_futures

// Mock glove → BLE frames → GloveClient → Recognizer → RecognitionService,
// in fake time. Nothing here fakes words: the mock only produces samples.
@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';

import '../support/kit.dart';

/// Recordings parsed once (real file I/O can't run inside fake time).
final _recordings = <String, Recording>{};

Future<void> _preload(List<String> files) async {
  final lib = MockLibrary(readAsset);
  for (final f in files) {
    _recordings[f] ??= await lib.load(f);
  }
}

class _Rig {
  new(this.bundle, {MockPerson person = MockPerson.a}) {
    library = MockLibrary(readAsset);
    _recordings.forEach(library.seed);
    feed = MockFeed(library, person: person);
    glove = MockGlove(feed);
    client = GloveClient(glove);
    engine = InProcessRecognizer(bundle);
    service = RecognitionService(
      source: client,
      engine: engine,
      labels: bundle.labels,
    )..events.listen(events.add);
  }

  final ModelBundle bundle;
  late final MockLibrary library;
  late final MockFeed feed;
  late final MockGlove glove;
  late final GloveClient client;
  late final InProcessRecognizer engine;
  late final RecognitionService service;
  final events = <RecognitionEvent>[];

  void connect(FakeAsync async) {
    client.connect(glove.device);
    async
      ..flushMicrotasks()
      ..elapse(const Duration(seconds: 2));
    expect(client.status.phase, GlovePhase.ready);
  }

  List<String> spoken() => [
    for (final e in events)
      if (e.speaks) e.label,
  ];

  Future<void> close() async {
    await service.dispose();
    await client.dispose();
    await engine.dispose();
    await feed.dispose();
  }
}

void main() {
  late ModelBundle bundle;
  setUpAll(() async => bundle = await loadKitBundle());

  for (final person in MockPerson.values) {
    test('person ${person.dir}: "Sign now" confirms each of the 20 signs '
        'exactly once', () async {
      final labels = bundle.labels.signs;
      await _preload([
        MockLibrary.restFile(person),
        for (final l in labels) MockLibrary.practiceFile(person, l),
      ]);
      final failures = <String>[];
      final rigs = <_Rig>[];
      for (final label in labels) {
        fakeAsync((async) {
          final rig = _Rig(bundle, person: person);
          rigs.add(rig);
          rig.connect(async);
          async.elapse(const Duration(seconds: 3)); // idle, hand at rest
          rig.client.cuePractice(label);
          async.elapse(const Duration(seconds: 12)); // the clip is ~7.4 s
          final spoken = rig.spoken();
          if (spoken.length != 1 || spoken.single != label) {
            failures.add('$label -> $spoken');
          }
          final confirm = rig.events.firstWhere(
            (e) => e.speaks && e.label == label,
            orElse: () => const RecognitionEvent(
              kind: DeciderEventKind.cancel,
              label: '',
              step: 0,
              probability: null,
            ),
          );
          if (confirm.label == label) {
            expect(confirm.probability, inInclusiveRange(0, 1));
          }
          rig.client.disconnect();
          async.elapse(const Duration(seconds: 2));
        });
      }
      for (final r in rigs) {
        await r.close();
      }
      expect(failures, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test(
    'sentence demo "me + hungry" with idle between: both words, in order',
    () async {
      final files = [
        MockLibrary.restFile(MockPerson.a),
        MockLibrary.practiceFile(MockPerson.a, 'me'),
        MockLibrary.practiceFile(MockPerson.a, 'hungry'),
      ];
      await _preload(files);
      late _Rig rig;
      fakeAsync((async) {
        rig = _Rig(bundle)..connect(async);
        rig.feed.play([
          MockClip(files[1], idleBefore: const Duration(seconds: 1)),
          MockClip(files[2], idleBefore: const Duration(seconds: 2)),
        ]);
        async.elapse(const Duration(seconds: 25));
        expect(rig.spoken(), ['me', 'hungry']);
        rig.client.disconnect();
        async.elapse(const Duration(seconds: 2));
      });
      await rig.close();
    },
  );

  test('a 12-sample BLE gap right after a tentative word cancels it', () async {
    await _preload([
      MockLibrary.restFile(MockPerson.a),
      MockLibrary.practiceFile(MockPerson.a, 'hello'),
    ]);
    late _Rig rig;
    fakeAsync((async) {
      rig = _Rig(bundle)..connect(async);
      rig.client.cuePractice('hello');
      // Run until the tentative word appears, then lose 12 samples.
      for (
        var i = 0;
        i < 200 && !rig.events.any((e) => e.kind == DeciderEventKind.tentative);
        i++
      ) {
        async.elapse(const Duration(milliseconds: 100));
      }
      expect(rig.events.last.kind, DeciderEventKind.tentative);
      rig.glove.dropSamples(12);
      async.elapse(const Duration(milliseconds: 300));
      final cancel = rig.events.firstWhere(
        (e) => e.kind == DeciderEventKind.cancel,
      );
      expect(cancel.label, 'hello');
      expect(
        cancel.step,
        -1,
        reason: 'cancelled by the gap, not by a model run',
      );
      rig.client.disconnect();
      async.elapse(const Duration(seconds: 2));
    });
    await rig.close();
  });
}
