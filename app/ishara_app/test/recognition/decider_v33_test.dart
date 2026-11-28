// AI-SPEC v3.3: each new rule on its own, with small hand-made probability
// streams (pair_level and a word signed alone, §5; the glove restart, §4),
// and the defaults (a v3.2.1 config still gives the v3.2.1 events).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';

import '../support/kit.dart';

/// Labels `one, two, rest, other`; a vector is `[one, two, rest, other]`.
final _labels = Labels.parse('one\ntwo\nrest\nother');

/// A small config: smooth 1 so each vector is the averaged output.
/// idle 0.85 / null 0.03, tentative 0.6 / null 0.3, active 0.5 / null 0.3,
/// all hold 1; confirm_s 3.5 s = 18 steps.
DeciderConfig _config([Map<String, Object?> v33 = const {}]) =>
    DeciderConfig.fromJson({
      'smooth': 1,
      'active_s': 4,
      'confirm_s': 3.5,
      'models': const ['a.tflite'],
      'idle': const {'confidence': 0.85, 'hold': 1, 'max_null': 0.03},
      'tentative': const {'confidence': 0.6, 'hold': 1, 'max_null': 0.3},
      'active': const {'confidence': 0.5, 'hold': 1, 'max_null': 0.3},
      ...v33,
    });

/// Runs [stream] through a fresh Decider: `'<0-based step> <event>(<word>)'`.
List<String> _run(DeciderConfig config, List<List<double>> stream) {
  final d = Decider(_labels, config);
  return [
    for (final (i, p) in stream.indexed)
      for (final e in d.step(Float64List.fromList(p))) '$i $e',
  ];
}

const _rest = [0.0, 0.0, 1.0, 0.0];
const _other = [0.0, 0.0, 0.0, 1.0];

// ONE passes tentative, not idle (0.7 < 0.85).
const _oneTentative = [0.7, 0.1, 0.1, 0.1];

// TWO passes active (0.55 >= 0.5) but not tentative (0.55 < 0.6).
const _twoActiveOnly = [0.25, 0.55, 0.1, 0.1];

// TWO passes tentative (0.65), not idle.
const _twoTentative = [0.15, 0.65, 0.1, 0.1];

// TWO passes idle (0.9, null 0.02).
const _twoIdle = [0.08, 0.9, 0.01, 0.01];

// ONE for a word signed alone: conf 0.8 (passes tentative, not idle),
// null 0.02 (<= rest_null 0.03).
const _oneClear = [0.8, 0.18, 0.01, 0.01];

void main() {
  group('DeciderConfig v3.3 keys', () {
    test('absent keys give the v3.2.1 behaviour', () {
      final c = _config();
      expect(c.pairLevel, DeciderLevel.active);
      expect(c.confirmOnRest, 0);
      expect(c.restConf, 0);
      expect(c.restRun, 0);
      expect(c.restNull, 1);
    });

    test('reads the kit values', () {
      final c = _config({
        'pair_level': 'tentative',
        'confirm_on_rest': 2,
        'rest_conf': 0.7,
        'rest_run': 3,
        'rest_null': 0.03,
      });
      expect(c.pairLevel, DeciderLevel.tentative);
      expect(c.confirmOnRest, 2);
      expect(c.restConf, .7);
      expect(c.restRun, 3);
      expect(c.restNull, .03);
      expect(_config({'pair_level': 'idle'}).pairLevel, DeciderLevel.idle);
      expect(_config({'pair_level': 'active'}).pairLevel, DeciderLevel.active);
    });

    test('bad values are ParseFailures', () {
      for (final bad in <Map<String, Object?>>[
        {'pair_level': 'loose'},
        {'pair_level': 1},
        {'confirm_on_rest': -1},
        {'confirm_on_rest': 1.5},
        {'rest_run': '3'},
        {'rest_conf': 'x'},
        {'rest_null': true},
      ]) {
        expect(
          () => _config(bad),
          throwsA(isA<ParseFailure>()),
          reason: '$bad',
        );
      }
    });

    test('the kit decider.json has the v3.3 keys', () {
      final c = DeciderConfig.parse(
        readText('assets/packs/asl/kit/model/decider.json'),
      );
      expect(c.pairLevel, DeciderLevel.tentative);
      expect(c.confirmOnRest, greaterThan(0));
    });
  });

  group('pair_level (§5)', () {
    test('"tentative": a second word that passes only active does not '
        'confirm the pending word', () {
      final c = _config({'pair_level': 'tentative'});
      expect(_run(c, [_oneTentative, _twoActiveOnly]), ['0 tentative(one)']);
    });

    test('"tentative": a second word that passes tentative confirms both', () {
      final c = _config({'pair_level': 'tentative'});
      expect(_run(c, [_oneTentative, _twoTentative]), [
        '0 tentative(one)',
        '1 confirm(one)',
        '1 word(two)',
      ]);
    });

    test('default ("active", v3.2.1): passing active is enough', () {
      expect(_run(_config(), [_oneTentative, _twoActiveOnly]), [
        '0 tentative(one)',
        '1 confirm(one)',
        '1 word(two)',
      ]);
    });

    test('"idle": the second word must pass idle', () {
      final c = _config({'pair_level': 'idle'});
      expect(_run(c, [_oneTentative, _twoTentative]), ['0 tentative(one)']);
      expect(_run(c, [_oneTentative, _twoIdle]), [
        '0 tentative(one)',
        '1 confirm(one)',
        '1 word(two)',
      ]);
    });
  });

  group('a word signed alone (§5)', () {
    final alone = <String, Object?>{
      'confirm_on_rest': 2,
      'rest_conf': 0.7,
      'rest_run': 3,
      'rest_null': 0.03,
    };
    // rest, ONE x3, rest x2: peak 0.8, best run 3, lowest null 0.02.
    final signedAlone = [_rest, _oneClear, _oneClear, _oneClear, _rest, _rest];

    test('confirmed after confirm_on_rest rest steps when all hold', () {
      expect(_run(_config(alone), signedAlone), [
        '1 tentative(one)',
        '5 confirm(one)',
      ]);
    });

    test('not before confirm_on_rest rest steps in a row', () {
      expect(_run(_config(alone), signedAlone.sublist(0, 5)), [
        '1 tentative(one)',
      ]);
      // `other` breaks the rest run: rest, other, rest is not 2 in a row.
      expect(
        _run(_config(alone), [
          ...signedAlone.sublist(0, 4),
          _rest,
          _other,
          _rest,
        ]),
        ['1 tentative(one)'],
      );
      // ... and a third rest after that completes it.
      expect(
        _run(_config(alone), [
          ...signedAlone.sublist(0, 4),
          _rest,
          _other,
          _rest,
          _rest,
        ]),
        ['1 tentative(one)', '7 confirm(one)'],
      );
    });

    test('not when the peak conf is below rest_conf', () {
      const weak = [0.65, 0.33, 0.01, 0.01]; // tentative, peak 0.65 < 0.7
      expect(_run(_config(alone), [_rest, weak, weak, weak, _rest, _rest]), [
        '1 tentative(one)',
      ]);
      // rest_conf 0.65 accepts it: the check is >=.
      expect(
        _run(_config({...alone, 'rest_conf': 0.65}), [
          _rest,
          weak,
          weak,
          weak,
          _rest,
          _rest,
        ]),
        ['1 tentative(one)', '5 confirm(one)'],
      );
    });

    test('not when the best tentative run is shorter than rest_run', () {
      // Two clear steps only.
      expect(
        _run(_config(alone), [_rest, _oneClear, _oneClear, _rest, _rest]),
        ['1 tentative(one)'],
      );
      // Three steps, but the middle one fails tentative (0.55 < 0.6):
      // the run restarts, best = 1.
      const dip = [0.55, 0.43, 0.01, 0.01];
      expect(
        _run(_config(alone), [_rest, _oneClear, dip, _oneClear, _rest, _rest]),
        ['1 tentative(one)'],
      );
    });

    test('not when null never got as low as rest_null', () {
      const noisy = [0.8, 0.15, 0.025, 0.025]; // null 0.05 > 0.03
      expect(_run(_config(alone), [_rest, noisy, noisy, noisy, _rest, _rest]), [
        '1 tentative(one)',
      ]);
    });

    test('off by default (v3.2.1): the word is cancelled after confirm_s', () {
      final stream = [...signedAlone, for (var i = 0; i < 20; i++) _rest];
      // tentative at step 1, pending_until = 2 + 18 = 20 (1-based): cancel at
      // 0-based step 20.
      expect(_run(_config(), stream), ['1 tentative(one)', '20 cancel(one)']);
    });

    test('a confirmed word is said: the next word inside active_s uses the '
        'active level', () {
      final d = Decider(_labels, _config(alone));
      final events = <String>[];
      for (final p in [...signedAlone, _twoActiveOnly]) {
        events.addAll(d.step(Float64List.fromList(p)).map((e) => '$e'));
      }
      expect(events, ['tentative(one)', 'confirm(one)', 'word(two)']);
      expect(d.pending, isNull);
    });
  });

  test('defaults: the v3.2.1 config reproduces the kit v3.2.3 Decider '
      'vectors', () {
    final v = readJson('test/fixtures/kit_v3_2_3_decider_vectors.json');
    final config = DeciderConfig.fromJson(
      (v['config'] as Map).cast<String, Object?>(),
    );
    expect(config.pairLevel, DeciderLevel.active);
    expect(config.confirmOnRest, 0);
    final d = Decider(Labels.parse((v['labels'] as List).join('\n')), config);
    final got = <Map<String, Object?>>[];
    for (final (i, p) in (v['probs'] as List).indexed) {
      for (final e in d.step(Float64List.fromList(doubles(p)))) {
        got.add({'step': i, 'event': e.kind.name, 'word': e.label});
      }
    }
    expect(got, v['expected']);
    expect(got, isNotEmpty);
  });

  group('glove restart (§4)', () {
    const cal =
        '{"v":2,"open":[2234.0,2608.0,2443.0,2412.0,2674.0],'
        '"fist":[1625.0,1661.0,1815.0,1560.0,1907.0],'
        '"gyro_bias_raw":[-205.5,302.9,-218.4],"roll_neutral":0.0,'
        '"roll_min":-45.0,"roll_max":45.0}';
    final raw = List.filled(11, 0);

    /// A recognizer whose model says ONE (tentative level) on every run.
    Recognizer recognizer() => Recognizer(
      labels: _labels,
      config: _config(),
      calibration: GloveCalibration.parse(cal),
      predict: (_) => Float64List.fromList(_oneTentative),
    );

    /// Feeds seq 0..99: one run at sample 100, ONE becomes tentative.
    void fill(Recognizer r) {
      for (var s = 0; s < 99; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty));
      }
      expect(r.feed(99, raw).events.map((e) => '$e'), ['tentative(one)']);
    }

    test('10 dropped in a row stay dropped; the 11th is a real gap', () {
      final r = recognizer();
      fill(r);
      // The glove restarted: its seq starts again at 0 (older than 100).
      for (var s = 0; s < 10; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty), reason: 'drop $s');
      }
      final restart = r.feed(10, raw);
      expect(
        restart.resetCancel,
        const DeciderEvent(DeciderEventKind.cancel, 'one'),
      );
      expect(restart.steps, isEmpty);
      // Window cleared, counter 0, Decider reset: the 11th sample was pushed
      // as sample 1, so the next run comes 99 samples later, as step 0.
      for (var s = 11; s < 109; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty), reason: 'seq $s');
      }
      final next = r.feed(109, raw);
      expect(next.steps.single.sampleCount, 100);
      expect(next.steps.single.step, 0);
      expect(next.events.map((e) => '$e'), ['tentative(one)']);
    });

    test('a sample that is not dropped resets the count', () {
      final r = recognizer();
      fill(r);
      for (var s = 0; s < 10; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty));
      }
      expect(r.feed(100, raw), same(FeedResult.empty), reason: 'in order');
      for (var s = 0; s < 10; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty), reason: 'drop $s');
      }
      // Still the same stream: sample 110 runs the model, nothing reset.
      for (var s = 101; s < 109; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty));
      }
      final run = r.feed(109, raw);
      expect(run.resetCancel, isNull);
      expect(run.steps.single.sampleCount, 110);
      expect(run.steps.single.step, 1);
    });

    test('a filled gap (1-5) also resets the count', () {
      final r = recognizer();
      fill(r);
      for (var s = 0; s < 10; s++) {
        r.feed(s, raw);
      }
      // seq 102: 2 missing, filled; not dropped.
      expect(r.feed(102, raw).resetCancel, isNull);
      for (var s = 0; s < 10; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty), reason: 'drop $s');
      }
    });

    test('duplicates count as dropped too', () {
      final r = recognizer();
      fill(r);
      for (var i = 0; i < 10; i++) {
        expect(r.feed(99, raw), same(FeedResult.empty));
      }
      expect(r.feed(99, raw).resetCancel, isNotNull);
    });

    test('reset() starts the count again', () {
      final r = recognizer();
      fill(r);
      for (var s = 0; s < 10; s++) {
        r.feed(s, raw);
      }
      r
        ..reset()
        ..feed(500, raw); // first sample after a reset: accepted as is
      for (var s = 0; s < 10; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty), reason: 'drop $s');
      }
      // The 10 drops changed nothing: seq 501..599 are samples 2..100.
      for (var s = 501; s < 599; s++) {
        expect(r.feed(s, raw), same(FeedResult.empty), reason: 'seq $s');
      }
      expect(r.feed(599, raw).steps.single.sampleCount, 100);
    });
  });

  test('the fixture is the v3.2.1 decider section', () {
    final v = readJson('test/fixtures/kit_v3_2_3_decider_vectors.json');
    final keys = (v['config'] as Map).keys.toSet();
    expect(
      keys.intersection({
        'pair_level',
        'confirm_on_rest',
        'rest_conf',
        'rest_run',
        'rest_null',
      }),
      isEmpty,
    );
    expect(jsonEncode(v['labels']), contains('"rest","other"'));
  });
}
