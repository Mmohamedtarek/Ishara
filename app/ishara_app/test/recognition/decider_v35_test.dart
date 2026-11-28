// AI-SPEC v3.5: `rest_per_class`, a word's own conditions for a word signed
// alone (§5), as live.py and the kit's verify_kit.py apply it:
//   rc = rest_per_class.get(pending, {})
//   pending_peak >= rc.get("conf", rest_conf)
//   pending_best >= rc.get("run", rest_run)
//   pending_null <= rc.get("null", rest_null)
// `confirm_on_rest` stays global. Small hand-made probability streams, as in
// decider_v33_test.dart.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';

import '../support/kit.dart';

/// Labels `one, two, rest, other`; a vector is `[one, two, rest, other]`.
final _labels = Labels.parse('one\ntwo\nrest\nother');

/// The v3.3 single-word rule as in the kit (confirm after 2 rests, global
/// conf 0.7, run 3, null 0.03), plus [extra]. smooth 1, every level hold 1:
/// idle 0.85 / null 0.03, tentative 0.6 / null 0.3, active 0.5 / null 0.3.
DeciderConfig _config([Map<String, Object?> extra = const {}]) =>
    DeciderConfig.fromJson({
      'smooth': 1,
      'active_s': 4,
      'confirm_s': 3.5,
      'models': const ['a.tflite'],
      'idle': const {'confidence': 0.85, 'hold': 1, 'max_null': 0.03},
      'tentative': const {'confidence': 0.6, 'hold': 1, 'max_null': 0.3},
      'active': const {'confidence': 0.5, 'hold': 1, 'max_null': 0.3},
      'confirm_on_rest': 2,
      'rest_conf': 0.7,
      'rest_run': 3,
      'rest_null': 0.03,
      ...extra,
    });

/// The kit's v3.5 entry for `one`.
const Map<String, Object?> _kitOne = {
  'one': {'null': 0.05, 'conf': 0.6, 'run': 1},
};

/// Runs [stream] through a fresh Decider: `'<0-based step> <event>(<word>)'`.
List<String> _run(DeciderConfig config, List<List<double>> stream) {
  final d = Decider(_labels, config);
  return [
    for (final (i, p) in stream.indexed)
      for (final e in d.step(Float64List.fromList(p))) '$i $e',
  ];
}

const _rest = [0.0, 0.0, 1.0, 0.0];

/// rest, the word once, rest, rest: peak = the word's prob, best run 1,
/// lowest null = rest + other of [v].
List<List<double>> _alone(List<double> v) => [_rest, v, _rest, _rest];

// ONE, weaker than the global conditions, inside the kit's own ones:
// conf 0.65 (>= 0.6, < 0.7), one step (>= 1, < 3), null 0.04 (<= 0.05,
// > 0.03). It passes tentative (0.65 >= 0.6, null 0.04 <= 0.3), not idle.
const _oneWeak = [0.65, 0.31, 0.02, 0.02];

// The same for TWO, which has no entry.
const _twoWeak = [0.31, 0.65, 0.02, 0.02];

void main() {
  group('DeciderConfig rest_per_class', () {
    test('absent: no word has its own conditions (v3.3)', () {
      final c = _config();
      expect(c.restPerClass, isEmpty);
      expect(c.restConfFor('one'), .7);
      expect(c.restRunFor('one'), 3);
      expect(c.restNullFor('one'), .03);
    });

    test('reads each field; a missing word or field uses the global value', () {
      final c = _config({
        'rest_per_class': {
          ..._kitOne,
          'two': {'conf': 0.9},
        },
      });
      expect(c.restConfFor('one'), .6);
      expect(c.restRunFor('one'), 1);
      expect(c.restNullFor('one'), .05);
      // two: conf only
      expect(c.restConfFor('two'), .9);
      expect(c.restRunFor('two'), 3);
      expect(c.restNullFor('two'), .03);
      // not listed
      expect(c.restConfFor('three'), .7);
      expect(c.restRunFor('three'), 3);
      expect(c.restNullFor('three'), .03);
      expect(
        _config({'rest_per_class': <String, Object?>{}}).restPerClass,
        isEmpty,
      );
    });

    test('bad values are ParseFailures', () {
      for (final bad in <Object?>[
        'one',
        [_kitOne],
        {'one': 0.6},
        {'one': <Object?>[]},
        {
          'one': {'conf': 'x'},
        },
        {
          'one': {'null': true},
        },
        {
          'one': {'run': -1},
        },
        {
          'one': {'run': 1.5},
        },
        {
          'one': {'run': '1'},
        },
        // a misspelt key must not fall back to the global value silently
        {
          'one': {'nul': 0.05},
        },
        {
          'one': {'rest_conf': 0.6},
        },
      ]) {
        expect(
          () => _config({'rest_per_class': bad}),
          throwsA(isA<ParseFailure>()),
          reason: '$bad',
        );
      }
    });

    test('labels are checked against labels.txt and must be words', () {
      _config({'rest_per_class': _kitOne}).validateAgainst(_labels);
      for (final label in ['three', 'rest', 'other']) {
        expect(
          () => _config({
            'rest_per_class': {
              label: {'conf': 0.6},
            },
          }).validateAgainst(_labels),
          throwsA(isA<ParseFailure>()),
          reason: label,
        );
      }
    });

    test('the kit decider.json: one has its own conditions, no other word', () {
      final c =
          DeciderConfig.parse(
            readText('assets/packs/asl/kit/model/decider.json'),
          )..validateAgainst(
            Labels.parse(readText('assets/packs/asl/kit/model/labels.txt')),
          );
      expect(c.restPerClass.keys, ['one']);
      expect(c.restConfFor('one'), .6);
      expect(c.restRunFor('one'), 1);
      expect(c.restNullFor('one'), .05);
    });
  });

  group('a word signed alone with rest_per_class (§5)', () {
    final kit = _config({'rest_per_class': _kitOne});

    test('the word with an entry is confirmed under its own conditions', () {
      expect(_run(kit, _alone(_oneWeak)), [
        '1 tentative(one)',
        '3 confirm(one)',
      ]);
    });

    test('a word without an entry keeps the global conditions', () {
      expect(_run(kit, _alone(_twoWeak)), ['1 tentative(two)']);
    });

    test('without rest_per_class the same ONE is not confirmed (v3.3)', () {
      expect(_run(_config(), _alone(_oneWeak)), ['1 tentative(one)']);
    });

    test('the bounds are inclusive: conf >=, run >=, null <=', () {
      // conf exactly 0.6, null exactly 0.05
      const edge = [0.6, 0.35, 0.025, 0.025];
      expect(_run(kit, _alone(edge)), ['1 tentative(one)', '3 confirm(one)']);
    });

    test('each of its conditions still has to hold', () {
      // conf 0.62 < its 0.65
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'null': 0.05, 'conf': 0.65, 'run': 1},
            },
          }),
          _alone(const [0.62, 0.34, 0.02, 0.02]),
        ),
        ['1 tentative(one)'],
      );
      // one step < its run 2
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'null': 0.05, 'conf': 0.6, 'run': 2},
            },
          }),
          _alone(_oneWeak),
        ),
        ['1 tentative(one)'],
      );
      // null 0.04 > its 0.035
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'null': 0.035, 'conf': 0.6, 'run': 1},
            },
          }),
          _alone(_oneWeak),
        ),
        ['1 tentative(one)'],
      );
    });

    test('a field it does not give uses the global value', () {
      // conf and run its own, null global (0.03 < 0.04): not confirmed
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'conf': 0.6, 'run': 1},
            },
          }),
          _alone(_oneWeak),
        ),
        ['1 tentative(one)'],
      );
      // ... with null 0.02 it is
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'conf': 0.6, 'run': 1},
            },
          }),
          _alone(const [0.65, 0.33, 0.01, 0.01]),
        ),
        ['1 tentative(one)', '3 confirm(one)'],
      );
      // run global (3): one step is not enough
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'conf': 0.6, 'null': 0.05},
            },
          }),
          _alone(_oneWeak),
        ),
        ['1 tentative(one)'],
      );
      // conf global (0.7): 0.65 is not enough
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'run': 1, 'null': 0.05},
            },
          }),
          _alone(_oneWeak),
        ),
        ['1 tentative(one)'],
      );
    });

    test('stricter own conditions apply too', () {
      // clear for the global rule (0.8 x3, null 0.02), but one asks 0.9
      const clear = [0.8, 0.18, 0.01, 0.01];
      final stream = [_rest, clear, clear, clear, _rest, _rest];
      expect(_run(_config(), stream), ['1 tentative(one)', '5 confirm(one)']);
      expect(
        _run(
          _config({
            'rest_per_class': {
              'one': {'conf': 0.9},
            },
          }),
          stream,
        ),
        ['1 tentative(one)'],
      );
    });

    test('confirm_on_rest stays global: still 2 rest steps in a row', () {
      expect(_run(kit, [_rest, _oneWeak, _rest]), ['1 tentative(one)']);
      // off globally = off for every word
      expect(
        _run(
          _config({'rest_per_class': _kitOne, 'confirm_on_rest': 0}),
          _alone(_oneWeak),
        ),
        ['1 tentative(one)'],
      );
    });
  });
}
