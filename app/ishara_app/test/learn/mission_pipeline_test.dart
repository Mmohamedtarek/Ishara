// Fake-time tests start futures and drive them with async.elapse():
// discarding them here is intended.
// ignore_for_file: discarded_futures

// A whole "Start here" mission on the real mock glove: its practice
// recordings → BLE frames → GloveClient → recognizer (3 models, Decider) →
// RecognitionService → MissionController. Nothing fakes a word.
@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';

import '../support/fake_learn.dart';
import '../support/kit.dart';

final _recordings = <String, Recording>{};

/// The real glove, except that "Sign now" for [from] plays [to]'s practice
/// recording (the mutation check: the wrong sign must not pass).
class _SwapPractice implements GloveSource {
  new(this._inner, {this.from, this.to});

  final GloveSource _inner;
  final String? from;
  final String? to;

  @override
  void cuePractice(String label) =>
      _inner.cuePractice(label == from ? to! : label);

  @override
  GloveStatus get status => _inner.status;
  @override
  Stream<GloveStatus> get statusChanges => _inner.statusChanges;
  @override
  Stream<List<GloveSample>> get samples => _inner.samples;
  @override
  Stream<GloveEvent> get events => _inner.events;
  @override
  Stream<List<DiscoveredGlove>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => _inner.scan(timeout: timeout);
  @override
  Future<void> connect(DiscoveredGlove glove) => _inner.connect(glove);
  @override
  Future<void> disconnect() => _inner.disconnect();
  @override
  Future<GloveCalibration?> readCalibration() => _inner.readCalibration();
  @override
  Future<CalStepResult> calibrate(CalStep step) => _inner.calibrate(step);
  @override
  Future<GloveCalibration> saveCalibration() => _inner.saveCalibration();
  @override
  Future<void> cancelCalibration() => _inner.cancelCalibration();
  @override
  Future<BatteryEvent> readBattery() => _inner.readBattery();
  @override
  Future<void> dispose() => _inner.dispose();
}

/// Plays "Start here" to the end; returns the practice outcomes by label.
Map<String, PracticePhase> _mission(
  ModelBundle bundle,
  MockPerson person, {
  String? swapFrom,
  String? swapTo,
}) {
  final outcomes = <String, PracticePhase>{};
  fakeAsync((async) {
    final library = MockLibrary(readAsset);
    _recordings.forEach(library.seed);
    final feed = MockFeed(library, person: person);
    final glove = MockGlove(feed);
    final client = GloveClient(glove);
    final engine = InProcessRecognizer(bundle);
    final service = RecognitionService(
      source: client,
      engine: engine,
      labels: bundle.labels,
    );
    final rig = LearnRig(
      source: _SwapPractice(client, from: swapFrom, to: swapTo),
      recognition: service,
    );
    final c = ProviderContainer(overrides: rig.overrides);
    client.connect(glove.device);
    async
      ..flushMicrotasks()
      ..elapse(const Duration(seconds: 2));
    expect(client.status.phase, GlovePhase.ready);
    const id = 'start';
    final sub = c.listen(missionControllerProvider(id), (_, _) {});
    async.flushMicrotasks();
    MissionController ctl() => c.read(missionControllerProvider(id).notifier);
    MissionState s() => c.read(missionControllerProvider(id));
    expect(s().block, isNull);
    async.elapse(const Duration(seconds: 3)); // idle, hand at rest
    while (s().result == null) {
      final step = s().step!;
      if (step is QuizStep) {
        ctl()
          ..pick(step.label)
          ..check()
          ..next();
        continue;
      }
      // "Sign now": the mock plays practice/<label>.csv; wait for the window
      while (s().practice!.phase == PracticePhase.ready ||
          s().practice!.phase == PracticePhase.retry) {
        ctl().signNow();
        async
          ..elapse(const Duration(milliseconds: 8200))
          ..elapse(const Duration(seconds: 2)); // the clip's tail, rest
      }
      outcomes[step.label] = s().practice!.phase;
      ctl().next();
    }
    final events = c.read(activityRepositoryProvider).events;
    for (final e in events.where((e) => e.type == ActivityType.practice)) {
      if (e.passed) {
        expect(e.prob, inExclusiveRange(0, 1), reason: e.label);
      }
    }
    sub.close();
    c.dispose();
    service.dispose();
    client.dispose();
    engine.dispose();
    feed.dispose();
    rig.dispose();
    async.flushMicrotasks();
  });
  return outcomes;
}

void main() {
  late ModelBundle bundle;
  setUpAll(() async {
    bundle = await loadKitBundle();
    final lib = MockLibrary(readAsset);
    for (final p in MockPerson.values) {
      for (final f in [
        ...MockLibrary.baseFiles(p),
        for (final l in ['hello', 'thanks', 'please', 'yes', 'no'])
          MockLibrary.practiceFile(p, l),
      ]) {
        _recordings[f] ??= await lib.load(f);
      }
    }
  });

  for (final person in MockPerson.values) {
    test('person ${person.dir}: every practice step of "Start here" passes '
        'through the real pipeline, first try', () {
      final out = _mission(bundle, person);
      expect(out, {
        for (final l in ['hello', 'thanks', 'please', 'yes', 'no'])
          l: PracticePhase.passed,
      });
    });

    test("person ${person.dir}: mutation: the mock plays another sign's "
        'practice file → that step fails (3 attempts), the others pass', () {
      final out = _mission(
        bundle,
        person,
        swapFrom: 'please',
        swapTo: 'thanks',
      );
      expect(out['please'], PracticePhase.failed);
      expect(
        {
          for (final e in out.entries)
            if (e.key != 'please') e.value,
        },
        {PracticePhase.passed},
      );
    });
  }
}
