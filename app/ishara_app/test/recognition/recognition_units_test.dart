@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/ensemble.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';

import '../support/kit.dart';

const _cal =
    '{"v":2,"open":[2234.0,2608.0,2443.0,2412.0,2674.0],'
    '"fist":[1625.0,1661.0,1815.0,1560.0,1907.0],'
    '"gyro_bias_raw":[-205.5,302.9,-218.4],"roll_neutral":0.0,'
    '"roll_min":-45.0,"roll_max":45.0}';

String _labels([List<String> extra = const []]) =>
    ['one', 'two', ...extra, 'rest', 'other'].join('\n');

const _decider = '''
{"cnn":{"smooth":3,"confirm_rf":false,"active_s":4,"confirm_s":3.5,
"models":["a.tflite"],"confirm_on_rest":2,
"active":{"confidence":0.5,"hold":1,"max_null":0.3,"per_class":{}},
"tentative":{"confidence":0.6,"hold":1,"max_null":0.3,"per_class":{}},
"idle":{"confidence":0.85,"hold":3,"max_null":0.03,"per_class":{"two":0.9}}}}''';

void main() {
  group('roundHalfEven (C7: Python round)', () {
    test('matches Python', () {
      const cases = [
        (17.5, 18),
        (12.5, 12),
        (20.0, 20),
        (2.5, 2),
        (3.5, 4),
        (.5, 0),
        (1.5, 2),
        (2.49, 2),
        (2.51, 3),
        (0.0, 0),
        (7.0, 7),
      ];
      for (final (x, want) in cases) {
        expect(roundHalfEven(x), want, reason: '$x');
      }
    });

    test('decider.json of the kit: active 20 steps, confirm 18 steps', () {
      final c = DeciderConfig.parse(_decider);
      expect(c.activeSteps, 20);
      expect(c.confirmSteps, 18);
    });
  });

  group('Labels', () {
    test('parse and lookups', () {
      final l = Labels.parse('${_labels()}\n\n');
      expect(l.all, ['one', 'two', 'rest', 'other']);
      expect(l.signs, ['one', 'two']);
      expect(l.indexOf('rest'), 2);
      expect(l.indexOf('nope'), isNull);
      expect(l.nonWordIndexes, [2, 3]);
      expect(l.isWord('one'), isTrue);
      expect(l.isWord('other'), isFalse);
    });

    test('rejects empty, duplicates, missing non-words', () {
      for (final bad in ['', 'a\na\nrest\nother', 'a\nrest']) {
        expect(
          () => Labels.parse(bad),
          throwsA(isA<ParseFailure>()),
          reason: bad,
        );
      }
    });
  });

  group('DeciderConfig', () {
    test('reads only the spec keys (confirm_on_rest ignored, C8)', () {
      final c = DeciderConfig.parse(_decider);
      expect(c.smooth, 3);
      expect(c.models, ['a.tflite']);
      expect(c.idle.thresholdFor('two'), .9);
      expect(c.idle.thresholdFor('one'), .85);
      expect(c.active.maxNull, .3);
      c.validateAgainst(Labels.parse(_labels()));
    });

    test('per_class must name a real label', () {
      final c = DeciderConfig.parse(
        _decider.replaceFirst('"two":0.9', '"zzz":0.9'),
      );
      expect(
        () => c.validateAgainst(Labels.parse(_labels())),
        throwsA(isA<ParseFailure>()),
      );
    });

    test('broken files are ParseFailures', () {
      final broken = [
        'nope',
        '[]',
        '{"rf":{}}',
        _decider.replaceFirst('"smooth":3', '"smooth":0'),
        _decider.replaceFirst('"models":["a.tflite"]', '"models":[]'),
        _decider.replaceFirst('"active_s":4', '"active_s":-1'),
        _decider.replaceFirst('"hold":3', '"hold":0'),
        _decider.replaceFirst('"confidence":0.85', '"confidence":"x"'),
        _decider.replaceFirst('"per_class":{"two":0.9}', '"per_class":[1]'),
        _decider.replaceFirst(
          '"per_class":{"two":0.9}',
          '"per_class":{"two":"x"}',
        ),
        _decider.replaceFirst(RegExp(r'"idle":\{[^}]*\{[^}]*\}\}'), '"idle":1'),
      ];
      for (final (i, b) in broken.indexed) {
        expect(
          () => DeciderConfig.parse(b),
          throwsA(isA<ParseFailure>()),
          reason: 'case $i',
        );
      }
    });
  });

  group('GloveCalibration', () {
    test('parse keeps the JSON and ignores extra fields', () {
      final c = GloveCalibration.parse(
        _cal.replaceFirst('{', '{"fw":"0.3.0","gyroBias":[1,2,3],'),
      );
      expect(c.version, 2);
      expect(c.fist.last, 1907);
      expect(c.rollMax, 45);
      expect(c, GloveCalibration.parse(c.json));
      expect(c.hashCode, c.json.hashCode);
    });

    test('broken #CAL is a ParseFailure', () {
      for (final b in [
        'x',
        '[1]',
        _cal.replaceFirst('"v":2', '"v":"2"'),
        _cal.replaceFirst('"open":[2234.0,', '"open":['),
        _cal.replaceFirst('"roll_min":-45.0', '"roll_min":null'),
      ]) {
        expect(
          () => GloveCalibration.parse(b),
          throwsA(isA<ParseFailure>()),
          reason: b,
        );
      }
    });
  });

  group('Ensemble', () {
    test('average is the float32 mean, widened to double', () {
      final a = Float32List.fromList([.1, .2, .7]);
      final b = Float32List.fromList([.3, .3, .4]);
      final c = Float32List.fromList([.2, .1, .7]);
      final avg = Ensemble.average([a, b, c]);
      // numpy 2.5.3: np.mean([a, b, c], axis=0) on float32 arrays
      // (float32 rounding after each add).
      expect(avg, [
        0.20000000298023224,
        0.20000000298023224,
        0.5999999642372131,
      ]);
      expect(() => Ensemble([]), throwsArgumentError);
      expect(() => Ensemble.average([a, Float32List(2)]), throwsArgumentError);
    });
  });

  group('Recognizer', () {
    late Labels labels;
    late DeciderConfig config;
    setUp(() {
      labels = Labels.parse(_labels());
      config = DeciderConfig.parse(_decider);
    });

    test('needs a calibration; checks the sample size', () {
      final r = Recognizer(
        labels: labels,
        config: config,
        predict: (_) => Float64List(4),
      );
      expect(() => r.feed(0, List.filled(11, 0)), throwsStateError);
      r.setCalibration(GloveCalibration.parse(_cal));
      expect(() => r.feed(0, [1, 2]), throwsArgumentError);
    });

    test(
      'model runs at sample 100, 110, ... with the window in time order',
      () {
        final windows = <Float32List>[];
        final r = Recognizer(
          labels: labels,
          config: config,
          calibration: GloveCalibration.parse(_cal),
          predict: (w) {
            windows.add(Float32List.fromList(w));
            return Float64List.fromList([0, 0, 1, 0]);
          },
        );
        final runs = <int>[];
        for (var k = 0; k < 135; k++) {
          // ax (channel 5) carries the sample index: normalized = k / 8192.
          final raw = List.filled(11, 0)..[5] = k;
          for (final s in r.feed(k, raw).steps) {
            runs.add(s.sampleCount);
          }
        }
        expect(runs, [100, 110, 120, 130]);
        final last = windows.last;
        for (var i = 0; i < 100; i++) {
          expect(
            last[i * 11 + 5],
            closeTo((30 + i) / 8192, 1e-9),
            reason: 'row $i',
          );
        }
      },
    );

    test('gap rule: fill 1-5, reset > 5, drop duplicate / older, wrap', () {
      var runs = 0;
      final r = Recognizer(
        labels: labels,
        config: config,
        calibration: GloveCalibration.parse(_cal),
        predict: (_) {
          runs++;
          return Float64List.fromList([0, 0, 1, 0]);
        },
      );
      final raw = List.filled(11, 0);
      // seq 65530.. wraps to 0; 95 samples + a 5-gap fill -> 100 at seq 34.
      var seq = 65530;
      for (var i = 0; i < 95; i++) {
        expect(r.feed(seq, raw).steps, isEmpty);
        seq = (seq + 1) & 0xFFFF;
      }
      expect(
        r.feed(seq, raw).steps,
        isEmpty,
        reason: 'duplicate of seq-1? no: in order',
      );
      expect(
        r.feed(seq, raw),
        same(FeedResult.empty),
        reason: 'duplicate dropped',
      );
      expect(
        r.feed((seq - 3) & 0xFFFF, raw),
        same(FeedResult.empty),
        reason: 'older dropped',
      );
      // 96 samples so far; skip 4 -> 4 filled + 1 = 101, run at 100.
      final res = r.feed((seq + 5) & 0xFFFF, raw);
      expect(res.steps.single.sampleCount, 100);
      expect(runs, 1);
      // Gap of 6: reset, the next run needs 100 new samples.
      seq = (seq + 5 + 7) & 0xFFFF;
      expect(r.feed(seq, raw).resetCancel, isNull);
      for (var i = 0; i < 98; i++) {
        seq = (seq + 1) & 0xFFFF;
        expect(r.feed(seq, raw).steps, isEmpty);
      }
      seq = (seq + 1) & 0xFFFF;
      expect(r.feed(seq, raw).steps.single.sampleCount, 100);
    });

    test('reset forgets the sequence; a new calibration resets', () {
      final r = Recognizer(
        labels: labels,
        config: config,
        calibration: GloveCalibration.parse(_cal),
        predict: (_) => Float64List.fromList([0, 0, 1, 0]),
      );
      final raw = List.filled(11, 0);
      for (var k = 0; k < 50; k++) {
        r.feed(k, raw);
      }
      r.reset();
      expect(
        r.feed(9000, raw),
        same(FeedResult.empty),
        reason: 'first sample after reset accepted',
      );
      r.setCalibration(GloveCalibration.parse(_cal));
      expect(r.calibration, isNotNull);
    });

    test('FeedResult.events lists the gap cancel first', () {
      const c = DeciderEvent(DeciderEventKind.cancel, 'one');
      final step = RecognitionStep(
        step: 0,
        sampleCount: 100,
        smoothed: Float64List(4),
        events: const [DeciderEvent(DeciderEventKind.word, 'two')],
      );
      expect(
        FeedResult(steps: [step], resetCancel: c).events.map((e) => '$e'),
        ['cancel(one)', 'word(two)'],
      );
      expect(c, const DeciderEvent(DeciderEventKind.cancel, 'one'));
      expect(
        c.hashCode,
        const DeciderEvent(DeciderEventKind.cancel, 'one').hashCode,
      );
    });
  });

  test('Decider rejects a probability vector of the wrong size', () {
    final d = Decider(Labels.parse(_labels()), DeciderConfig.parse(_decider));
    expect(() => d.step(Float64List(3)), throwsArgumentError);
    expect(d.smoothed, isNull);
  });

  group('ModelBundle', () {
    test('missing file -> AssetFailure with the path', () async {
      await expectLater(
        ModelBundle.load((p) async => throw Exception('no $p')),
        throwsA(
          isA<AssetFailure>().having(
            (f) => f.path,
            'path',
            'assets/kit/model/labels.txt',
          ),
        ),
      );
    });

    test('a broken model file -> AssetFailure, nothing leaks', () async {
      final kit = await loadKitBundle();
      final broken = ModelBundle(
        labels: kit.labels,
        config: kit.config,
        models: {
          ...kit.models,
          'ishara_cnn_3.tflite': Uint8List.fromList(utf8.encode('nope')),
        },
      );
      expect(broken.buildEnsemble, throwsA(isA<AssetFailure>()));
    });

    test('a model with the wrong output size -> AssetFailure', () async {
      final kit = await loadKitBundle();
      expect(
        () => TfliteModel.fromBytes(
          kit.models.values.first,
          name: 'm',
          labels: 21,
        ),
        throwsA(isA<AssetFailure>()),
      );
    });
  });

  test(
    'IsolateRecognizer: practice file confirms its word off the main isolate',
    () async {
      final bundle = await loadKitBundle();
      final engine = await IsolateRecognizer.spawn(bundle);
      final rec = Recording.parse(
        readText('assets/kit/mock/A/practice/thanks.csv'),
      );
      final words = <String>[];
      final done = Completer<void>();
      final sub = engine.outputs.listen((o) {
        for (final r in o.results) {
          for (final e in r.events) {
            if (e.kind == DeciderEventKind.confirm ||
                e.kind == DeciderEventKind.word) {
              words.add(e.label);
            }
          }
          if (r.steps.any(
            (s) => s.sampleCount >= rec.length - rec.length % 10,
          )) {
            if (!done.isCompleted) done.complete();
          }
        }
      });
      engine
        ..feed([GloveSample(0, Int16List(11))]) // ignored: no calibration yet
        ..setCalibration(GloveCalibration.parse(rec.calibrationJson!))
        ..reset();
      for (var k = 0; k < rec.length; k += 5) {
        engine.feed([
          for (var j = k; j < k + 5 && j < rec.length; j++)
            GloveSample(j, Int16List.fromList(rec.sample(j))),
        ]);
      }
      await done.future.timeout(const Duration(seconds: 20));
      expect(words, ['thanks']);
      await sub.cancel();
      await engine.dispose();
    },
  );

  test('IsolateRecognizer: a model that fails to load fails spawn', () async {
    final kit = await loadKitBundle();
    final broken = ModelBundle(
      labels: kit.labels,
      config: kit.config,
      models: {'x.tflite': Uint8List(4)},
    );
    await expectLater(
      IsolateRecognizer.spawn(broken),
      throwsA(isA<AssetFailure>()),
    );
  });
}
