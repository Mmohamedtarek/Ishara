// The recognition pipeline must reproduce the kit's numbers exactly
// (AI-SPEC v3.2.1 §8): test/test_vectors.json and mock/expected.json.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/ensemble.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/normalizer.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';

import '../support/kit.dart';

const _vectors = 'assets/kit/test/test_vectors.json';
const _expected = 'assets/kit/mock/expected.json';

Map<String, Object?> _event(DeciderEvent e) => {
  'event': e.kind.name,
  'word': e.label,
};

void main() {
  late ModelBundle bundle;
  late Ensemble ensemble;
  late Map<String, dynamic> tv;
  late GloveCalibration cal;

  setUpAll(() async {
    bundle = await loadKitBundle();
    ensemble = bundle.buildEnsemble();
    tv = readJson(_vectors);
    cal = GloveCalibration.parse(
      // The vectors' calibration object, re-encoded.
      readText(_vectors).isEmpty ? '' : _calJson(tv['calibration']),
    );
  });
  tearDownAll(() => ensemble.close());

  test('labels.txt matches the vectors', () {
    expect(bundle.labels.all, tv['labels']);
    expect(bundle.labels.length, 22);
    expect(bundle.labels.signs, hasLength(20));
  });

  group('normalize (1e-4)', () {
    test('every case: first row and window sum', () {
      final n = Normalizer(cal);
      final cases = (tv['normalize'] as Map)['cases'] as List;
      expect(cases, isNotEmpty);
      for (final (i, c) in cases.indexed) {
        final rows = intRows((c as Map)['raw_window']);
        final first = n.normalize(rows.first);
        final want = doubles(c['normalized_first_row']);
        for (var k = 0; k < 11; k++) {
          expect(first[k], closeTo(want[k], 1e-4), reason: 'case $i ch $k');
        }
        var sum = 0.0;
        for (final r in rows) {
          for (final v in n.normalize(r)) {
            sum += v;
          }
        }
        expect(
          sum,
          closeTo(c['normalized_sum'] as num, 1e-4),
          reason: 'case $i',
        );
      }
    });
  });

  group('models (1e-3)', () {
    test('every case: each model in decider.json order, and the average', () {
      final n = Normalizer(cal);
      final cases = (tv['model'] as Map)['cases'] as List;
      expect(cases, isNotEmpty);
      for (final (i, c) in cases.indexed) {
        final rows = intRows((c as Map)['raw_window']);
        final window = Float32List(100 * 11);
        for (final (r, raw) in rows.indexed) {
          n.normalizeInto(raw, window, r * 11);
        }
        final got = ensemble.predictAll(window);
        final each = c['probs_each'] as List;
        expect(got.each, hasLength(each.length));
        for (var m = 0; m < each.length; m++) {
          final want = doubles(each[m]);
          for (var k = 0; k < 22; k++) {
            expect(
              got.each[m][k],
              closeTo(want[k], 1e-3),
              reason: 'case $i model $m label $k',
            );
          }
        }
        final want = doubles(c['probs']);
        for (var k = 0; k < 22; k++) {
          expect(
            got.average[k],
            closeTo(want[k], 1e-3),
            reason: 'case $i avg $k',
          );
        }
      }
    });
  });

  test('decider: events at exactly the expected 0-based steps', () {
    final d = tv['decider'] as Map;
    final config = DeciderConfig.fromJson(
      (d['config'] as Map).cast<String, Object?>(),
    );
    final decider = Decider(bundle.labels, config);
    final got = <Map<String, Object?>>[];
    for (final (i, p) in (d['probs'] as List).indexed) {
      for (final e in decider.step(Float64List.fromList(doubles(p)))) {
        got.add({'step': i, ..._event(e)});
      }
    }
    expect(got, d['expected']);
  });

  test(
    'gaps: the BLE gap rule gives the expected events at the expected inputs',
    () {
      final g = tv['gaps'] as Map;
      final config = DeciderConfig.fromJson(
        (g['config'] as Map).cast<String, Object?>(),
      );
      final r = Recognizer(
        labels: bundle.labels,
        config: config,
        predict: ensemble.predict,
        calibration: GloveCalibration.parse(_calJson(g['calibration'])),
      );
      final got = <Map<String, Object?>>[];
      for (final (i, row) in intRows(g['input']).indexed) {
        for (final e in r.feed(row.first, row.sublist(1)).events) {
          got.add({'input': i, ..._event(e)});
        }
      }
      expect(got, g['expected']);
    },
  );

  group('mock/expected.json: every file through the full pipeline', () {
    final files = (readJson(_expected)['files'] as Map).cast<String, dynamic>();
    test('there are 88 files', () => expect(files, hasLength(88)));
    for (final MapEntry(key: name, value: want) in files.entries) {
      test(name, () {
        final rec = Recording.parse(
          readText('assets/kit/mock/$name'),
          name: name,
        );
        final r = Recognizer(
          labels: bundle.labels,
          config: bundle.config,
          predict: ensemble.predict,
          calibration: GloveCalibration.parse(rec.calibrationJson!),
        );
        final events = <Map<String, Object?>>[];
        final words = <Map<String, Object?>>[];
        for (var k = 0; k < rec.length; k++) {
          for (final s in r.feed(k % 65536, rec.sample(k)).steps) {
            for (final e in s.events) {
              events.add({
                'step': s.step,
                'sample': s.sampleCount,
                ..._event(e),
              });
              if (e.kind == DeciderEventKind.word ||
                  e.kind == DeciderEventKind.confirm) {
                words.add({'word': e.label, 'sample': s.sampleCount});
              }
            }
          }
        }
        expect(events, (want as Map)['events'], reason: '$name events');
        expect(words, want['words'], reason: '$name words');
      });
    }
  });
}

String _calJson(Object? cal) {
  final m = cal! as Map;
  String list(Object? l) => '[${(l! as List).join(',')}]';
  return '{"v":${m['v']},"open":${list(m['open'])},"fist":${list(m['fist'])},'
      '"gyro_bias_raw":${list(m['gyro_bias_raw'])},'
      '"roll_neutral":${m['roll_neutral']},"roll_min":${m['roll_min']},'
      '"roll_max":${m['roll_max']}}';
}
