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
      // flato (HOME only): closed onto the thumb in the step 5 review
      for (final k in curl.keys.where((k) => k != 'flato')) {
        expect(_at(shapes, [k, 'curl']), curl[k], reason: k);
        expect(_at(shapes, [k, 'reach']), reach[k], reason: k);
        expect(_at(shapes, [k, 'spread']), isNull, reason: k);
      }
    });

    // A copy of a sign without what the step 5 review allowed to change:
    // the depth of body contacts (dz of landmark points, now measured on the
    // real surface) and an elbow direction E (option b).
    Map<String, dynamic> core(Object? sign) {
      final c = jsonDecode(jsonEncode(sign)) as Map<String, dynamic>;
      for (final f in c['frames'] as List<dynamic>) {
        for (final hand in const ['R', 'L']) {
          final k = (f as Map<String, dynamic>)[hand];
          if (k is! Map<String, dynamic>) continue;
          k.remove('E');
          final pt = k['P'] as List<dynamic>;
          if (pt.first is String) pt[3] = 0;
        }
      }
      return c;
    }

    test('6 prototype signs are byte-for-byte the prototype frames', () {
      final signs = _lib()['signs'] as Map<String, dynamic>;
      final p = proto['signs'] as Map<String, dynamic>;
      for (final k in const [
        'yes',
        'no',
        'help',
        'coffee',
        'doctor',
        'family',
      ]) {
        expect(signs[k], p[k], reason: k);
      }
    });

    test('contact signs differ only in contact depth (YOU: level '
        'pointing)', () {
      final signs = _lib()['signs'] as Map<String, dynamic>;
      final p = proto['signs'] as Map<String, dynamic>;
      for (final k in const ['hello', 'thanks', 'please', 'sorry', 'me']) {
        expect(core(signs[k]), core(p[k]), reason: k);
        expect(signs[k], isNot(p[k]), reason: '$k: contacts now touch');
      }
      // HOME and CALL: fixed in the step 5 review (option b, contacts);
      // pinned exactly, so any change to them is deliberate (see below).
      // YOU: points level at the other person (review), shorter push.
      final you = core(p['you']);
      for (final i in [0, 1]) {
        _put(you, ['frames', i, 'R', 'H'], [-0.05, 0.15, 1]);
      }
      _put(you, ['frames', 1, 'R', 'P', 2], 0.32);
      expect(core(signs['you']), you);
    });

    test('review-fixed HOME, CALL and the flat-O are pinned exactly', () {
      final lib = _lib();
      // Step 5 review round 2: HOME = flat-O at the mouth corner, then the
      // cheekbone, elbow low; CALL = Y hand beside the head, elbow down.
      // Changing these needs a new front + side review (sign rule 2).
      expect(_at(lib, ['signs', 'home']), jsonDecode(_homePinned));
      expect(_at(lib, ['signs', 'call']), jsonDecode(_callPinned));
      expect(_at(lib, ['shapes', 'flato']), jsonDecode(_flatoPinned));
    });

    test('decided changes: Q-A4 rename, Q-A3 held still, V-3 mouth', () {
      final signs = _lib()['signs'] as Map<String, dynamic>;
      final p = proto['signs'] as Map<String, dynamic>;
      // I LOVE YOU: same frames except the second keeps the first position.
      final ily = jsonDecode(jsonEncode(p['love'])) as Map<String, dynamic>;
      _put(ily, ['frames', 1, 'R', 'P'], _at(ily, ['frames', 0, 'R', 'P']));
      expect(signs['iloveyou'], ily);
      // WATER: same frames at the mouth instead of the chin (+ contact depth).
      final water = core(p['water']);
      final frames = water['frames'] as List<dynamic>;
      for (var i = 0; i < frames.length; i++) {
        if (_at(frames, [i, 'R']) == null) continue;
        expect(_at(frames, [i, 'R', 'P', 0]), 'chin');
        _put(frames, [i, 'R', 'P', 0], 'mouth');
      }
      expect(core(signs['water']), water);
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
        'tip must be one of': (j) => _put(j, ['shapes', 'w', 'tip'], 'toe'),
        'E (elbow direction)': (j) => _put(j, [...h0, 'R', 'E'], [0, 0, 0]),
        'unknown {Q}': (j) => _put(j, [...h0, 'R', 'Q'], 1),
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

// Pinned review values (JSON, as in library.json).
const _homePinned =
    '''{"frames": [{"t": 0, "R": {"P": ["mouth", 0.03, 0, 0.003], "at": "tip", "H": [-0.3, 0.35, -0.85], "N": [-0.9, -0.3, 0.2], "c": "flato", "E": [0.2, -1, 0.1]}}, {"t": 0.3, "R": {"P": ["mouth", 0.05, 0.02, 0.04], "at": "tip", "H": [-0.3, 0.35, -0.85], "N": [-0.9, -0.3, 0.2], "c": "flato", "E": [0.2, -1, 0.1]}}, {"t": 0.6, "R": {"P": ["cheek", 0.06, -0.03, 0.003], "at": "tip", "H": [-0.4, 0.35, -0.85], "N": [-0.85, -0.3, 0.3], "c": "flato", "E": [0.2, -1, 0.1]}}, {"t": 0.9}]}''';
const _callPinned =
    '''{"frames": [{"t": 0, "R": {"H": [-0.4, 0.25, 0.88], "N": [-0.88, 0, -0.4], "c": "y", "E": [0.25, -1, 0.1], "P": ["ear", 0.12, -0.11, 0.02]}}, {"t": 0.2, "R": {"H": [-0.4, 0.25, 0.88], "N": [-0.88, 0, -0.4], "c": "y", "E": [0.25, -1, 0.1], "P": ["ear", 0.132, -0.11, 0.02]}}, {"t": 0.4, "R": {"H": [-0.4, 0.25, 0.88], "N": [-0.88, 0, -0.4], "c": "y", "E": [0.25, -1, 0.1], "P": ["ear", 0.12, -0.11, 0.02]}}, {"t": 0.6, "R": {"H": [-0.4, 0.25, 0.88], "N": [-0.88, 0, -0.4], "c": "y", "E": [0.25, -1, 0.1], "P": ["ear", 0.132, -0.11, 0.02]}}, {"t": 0.85}]}''';
const _flatoPinned =
    '''{"curl": [58, 50, 48, 48, 48], "reach": 0.78, "spread": [0, -7, 0, 6, 12]}''';
