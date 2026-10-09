@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';

import '../support/kit.dart';

const _libraryPath = 'assets/packs/asl/avatar/library.json';
const _fixture = 'test/fixtures/prototype_avatar_library.json';

Map<String, dynamic> _lib() => readJson(_libraryPath);

AvatarLibrary _parse(Map<String, dynamic> j) =>
    AvatarLibrary.parse(jsonEncode(j), language: SignLanguage.asl);

/// Reads the value at [path] (map keys and list indexes) in decoded JSON.
Object? _at(Object? root, List<Object> path) {
  var v = root;
  for (final k in path) {
    v = switch ((v, k)) {
      (final Map<String, dynamic> m, final String key) => m[key],
      (final List<dynamic> l, final int i) => l[i],
      _ => throw ArgumentError('bad path $path'),
    };
  }
  return v;
}

/// Sets (or, with [remove], deletes) the value at [path].
void _put(
  Object root,
  List<Object> path,
  Object? value, {
  bool remove = false,
}) {
  final parent = _at(root, path.sublist(0, path.length - 1));
  final k = path.last;
  switch ((parent, k)) {
    case (final Map<String, dynamic> m, final String key):
      if (remove) {
        m.remove(key);
      } else {
        m[key] = value;
      }
    case (final List<dynamic> l, final int i):
      l[i] = value;
    default:
      throw ArgumentError('bad path $path');
  }
}

Matcher _parseFailure(String part) => throwsA(
  isA<ParseFailure>().having((f) => f.message, 'message', contains(part)),
);

void main() {
  late AvatarLibrary library;
  late Map<String, dynamic> proto;

  setUpAll(() {
    library = AvatarLibrary.parse(
      readText(_libraryPath),
      language: SignLanguage.asl,
    );
    proto = readJson(_fixture);
  });

  group('the ASL library', () {
    test('preview pairs (Q-A6) and frame times', () {
      expect(library.previewPairs, [('five', 'four'), ('two', 'no')]);
      expect(library.greeting, 'hello'); // prototype: hello at 0.8x
      expect(_parse(_lib()..remove('greeting')).greeting, isNull);
      expect(library.lastFrameTime('hello'), .85);
      expect(() => library.lastFrameTime('x'), throwsArgumentError);
      final j = _lib()..remove('previewPairs');
      expect(_parse(j).previewPairs, isEmpty);
    });

    test('25 labels: the 15 ported signs + 10 new glove signs', () {
      expect(library.labels, hasLength(25));
      expect(library.labels, isNot(contains('rest')));
      expect(library.labels, isNot(contains('love')));
      expect(library.language, SignLanguage.asl);
      expect(library.shapes, contains('relax'));
    });

    test('durations follow the engine: (0.32 + last t + 0.25) / speed', () {
      // hello's last frame is at 0.85 s.
      expect(library.duration('hello'), const Duration(microseconds: 1420000));
      expect(
        library.duration('hello', speed: 2),
        const Duration(microseconds: 710000),
      );
      // speed is clamped to 0.4–2, as the engine does
      expect(
        library.duration('hello', speed: 9),
        library.duration('hello', speed: 2),
      );
      expect(
        library.duration('hello', speed: .1),
        library.duration('hello', speed: .4),
      );
      expect(
        library.duration('hello', speed: double.nan),
        library.duration('hello'),
      );
      expect(() => library.duration('nope'), throwsArgumentError);
    });
  });

  group('port fidelity (prototype engine data)', () {
    test('the fixture is the current prototype (sha256 of the data block)', () {
      final html = File('../../design/prototype.html').readAsStringSync();
      final a = html.indexOf('  var CURL = {');
      final b = html.indexOf('  // ---------- skeleton name aliases', a);
      expect(a, greaterThan(0));
      expect(
        sha256.convert(utf8.encode(html.substring(a, b))).toString(),
        proto['sha256'],
        reason: 'prototype changed: re-run tools/extract_avatar_library.mjs',
      );
    });

    test('prototype hand shapes are unchanged (curl, reach)', () {
      final shapes = _lib()['shapes'] as Map<String, dynamic>;
      final curl = proto['curl'] as Map<String, dynamic>;
      final reach = proto['reach'] as Map<String, dynamic>;
      for (final k in curl.keys) {
        expect(_at(shapes, [k, 'curl']), curl[k], reason: k);
        expect(_at(shapes, [k, 'reach']), reach[k], reason: k);
        expect(_at(shapes, [k, 'spread']), isNull, reason: k);
      }
    });

    test('13 prototype signs are byte-for-byte the prototype frames', () {
      final signs = _lib()['signs'] as Map<String, dynamic>;
      final p = proto['signs'] as Map<String, dynamic>;
      const changed = {'water', 'love', 'rest'};
      for (final k in p.keys.where((k) => !changed.contains(k))) {
        expect(signs[k], p[k], reason: k);
      }
    });

    test('decided changes only: Q-A4 rename, Q-A3 held still, V-3 mouth', () {
      final signs = _lib()['signs'] as Map<String, dynamic>;
      final p = proto['signs'] as Map<String, dynamic>;
      // I LOVE YOU: same frames except the second keeps the first position.
      final ily = jsonDecode(jsonEncode(p['love'])) as Map<String, dynamic>;
      _put(ily, ['frames', 1, 'R', 'P'], _at(ily, ['frames', 0, 'R', 'P']));
      expect(signs['iloveyou'], ily);
      // WATER: same frames at the mouth instead of the chin.
      final water = jsonDecode(jsonEncode(p['water'])) as Map<String, dynamic>;
      final frames = water['frames'] as List<dynamic>;
      for (var i = 0; i < frames.length; i++) {
        if (_at(frames, [i, 'R']) == null) continue;
        expect(_at(frames, [i, 'R', 'P', 0]), 'chin');
        _put(frames, [i, 'R', 'P', 0], 'mouth');
      }
      expect(signs['water'], water);
    });

    test('the ready pose matches the engine copy', () {
      final engine = readText('assets/avatar/engine.js');
      expect(
        engine,
        contains(
          'var READY_R = { P:[.1,1.0,.27], H:[-.3,.05,.95], '
          "N:[-.5,-.85,.1], c:'relax' };",
        ),
      );
      expect(_at(proto, ['ready', 'R']), {
        'P': [.1, 1.0, .27],
        'H': [-.3, .05, .95],
        'N': [-.5, -.85, .1],
        'c': 'relax',
      });
    });
  });

  group('validation', () {
    test('a library of another language is refused', () {
      expect(
        () => AvatarLibrary.parse(
          readText(_libraryPath),
          language: SignLanguage.arsl,
        ),
        _parseFailure('not arsl'),
      );
    });

    test('broken data is refused with a reason', () {
      const h0 = ['signs', 'hello', 'frames', 0];
      final cases = <String, void Function(Map<String, dynamic>)>{
        'no shapes': (j) => j['shapes'] = <String, dynamic>{},
        'needs shape "relax"': (j) =>
            _put(j, ['shapes', 'relax'], null, remove: true),
        'curl must be 5 numbers': (j) => _put(j, ['shapes', 'b', 'curl'], [1]),
        'curl must be 5 numbers 0-100': (j) =>
            _put(j, ['shapes', 'b', 'curl'], [1, 2, 3, 4, 101]),
        'reach must be': (j) => _put(j, ['shapes', 'b', 'reach'], 0),
        'spread must be': (j) =>
            _put(j, ['shapes', 'b', 'spread'], [0, 40, 0, 0, 0]),
        'no signs': (j) => j['signs'] = <String, dynamic>{},
        'not a sign label': (j) =>
            _put(j, ['signs', 'rest'], _at(j, ['signs', 'hello'])),
        'has no frames': (j) =>
            _put(j, ['signs', 'hello', 'frames'], <dynamic>[]),
        't must start at 0': (j) => _put(j, [...h0, 't'], .1),
        't must start at 0 and increase': (j) =>
            _put(j, ['signs', 'hello', 'frames', 1, 't'], 0),
        'needs the right hand': (j) =>
            _put(j, [...h0, 'R'], null, remove: true),
        'P must be': (j) => _put(j, [...h0, 'R', 'P'], ['nose', 0, 0, 0]),
        'H must be a non-zero direction': (j) =>
            _put(j, [...h0, 'R', 'H'], [0, 0, 0]),
        'N must be': (j) => _put(j, [...h0, 'R', 'N'], [1, 'x', 0]),
        'at must be': (j) => _put(j, [...h0, 'R', 'at'], 'elbow'),
        'unknown shape': (j) => _put(j, [...h0, 'R', 'c'], 'zz'),
        'head must be': (j) => _put(j, [...h0, 'head'], [1]),
        'unknown {x}': (j) => _put(j, [...h0, 'x'], 1),
        'frame 2': (j) => _put(j, ['signs', 'hello', 'frames', 2], 'x'),
        'sign hello is not an object': (j) => _put(j, ['signs', 'hello'], 1),
        'shape b is not an object': (j) => _put(j, ['shapes', 'b'], 1),
        'is not an object': (j) =>
            _put(j, ['signs', 'help', 'frames', 0, 'L'], 'left'),
        'previewPairs must be a list': (j) => j['previewPairs'] = 'five',
        'greeting must name a sign': (j) => j['greeting'] = 'wave',
        'must name two signs': (j) => j['previewPairs'] = [
          ['five', 'six'],
        ],
        'must name two signs of the library': (j) => j['previewPairs'] = [
          ['five'],
        ],
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final j = _lib();
        value(j);
        expect(() => _parse(j), _parseFailure(key), reason: key);
      }
      expect(
        () => AvatarLibrary.parse('[', language: SignLanguage.asl),
        _parseFailure('not JSON'),
      );
      expect(
        () => AvatarLibrary.parse('[]', language: SignLanguage.asl),
        _parseFailure('root'),
      );
    });

    test('valid variations are accepted', () {
      final j = _lib();
      _put(j, ['signs', 'hello', 'frames', 0, 'R', 'P'], [0.1, 1.2, 0.3]);
      _put(
        j,
        ['signs', 'hello', 'frames', 0, 'L'],
        {
          'P': ['chest', 0, 0, 0],
          'H': [0, 1, 0],
          'N': [0, 0, 1],
          'c': 'open',
          'at': 'palm',
        },
      );
      expect(_parse(j).has('hello'), isTrue);
    });
  });

  group('cast', () {
    late AvatarCast cast;
    setUpAll(
      () => cast = AvatarCast.parse(readText('assets/avatar/cast.json')),
    );

    test('Nour (default) and Sara, from the prototype CAST', () {
      expect(cast.characters.map((c) => c.id), ['nour', 'sara']);
      expect(cast.defaultId, 'nour');
      expect(cast.byId('sara').feminine, isTrue);
      expect(cast.byId('nour').feminine, isFalse);
      expect(cast.byId('sara').name(arabic: true), 'سارة');
      expect(cast.byId('nour').name(arabic: false), 'Nour');
      expect(cast.byId('nobody').id, 'nour');
      expect(cast.byId(null).id, 'nour');
    });

    test('every character file exists', () {
      final j = readJson('assets/avatar/cast.json');
      for (final id in (j['characters'] as Map<String, dynamic>).keys) {
        final f = File('assets/avatar/${_at(j, ['characters', id, 'src'])}');
        expect(f.existsSync(), isTrue, reason: f.path);
        // glTF binary magic
        expect(utf8.decode(f.readAsBytesSync().sublist(0, 4)), 'glTF');
      }
    });

    test('broken cast data is refused', () {
      String with_(void Function(Map<String, dynamic>) f) {
        final j = readJson('assets/avatar/cast.json');
        f(j);
        return jsonEncode(j);
      }

      for (final (bad, why) in [
        ('{', 'not JSON'),
        ('[]', 'root'),
        (with_((j) => j['characters'] = <String, dynamic>{}), 'no characters'),
        (with_((j) => _put(j, ['characters', 'nour'], 1)), 'character nour'),
        (
          with_((j) => _put(j, ['characters', 'nour', 'en'], '')),
          '"en" must be text',
        ),
        (with_((j) => _put(j, ['characters', 'nour', 'kind'], 'rig')), 'kind'),
        (
          with_((j) => _put(j, ['characters', 'nour', 'src'], '../x.glb')),
          'src',
        ),
        (with_((j) => j['default'] = 'omar'), 'default'),
      ]) {
        expect(() => AvatarCast.parse(bad), _parseFailure(why), reason: why);
      }
    });
  });
}
