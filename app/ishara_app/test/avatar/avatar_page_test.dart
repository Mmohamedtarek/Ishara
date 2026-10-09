@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/kit.dart';

/// The bundled avatar page (assets/avatar/): offline, locked down, and the
/// ported engine (not a rewrite).
void main() {
  final html = readText('assets/avatar/index.html');
  final engine = readText('assets/avatar/engine.js');

  test('the CSP allows only this server, and its hash pins the import map', () {
    final csp = RegExp('http-equiv="Content-Security-Policy" content="([^"]+)"')
        .firstMatch(html)!
        .group(1)!;
    expect(csp, contains("default-src 'none'"));
    expect(csp, contains("connect-src 'self' blob: data:"));
    expect(csp, isNot(contains('unsafe-inline')));
    expect(csp, isNot(contains("'unsafe-eval'")));
    expect(csp, isNot(contains('http')));
    final map = RegExp('<script type="importmap">(.*?)</script>')
        .firstMatch(html)!
        .group(1)!;
    final hash = base64Encode(sha256.convert(utf8.encode(map)).bytes);
    expect(csp, contains("'sha256-$hash'"));
    expect(jsonDecode(map), {
      'imports': {
        'three': './three/build/three.module.js',
        'three/addons/': './three/examples/jsm/',
      },
    });
    // the only other scripts are files from this server
    expect(
      RegExp('<script').allMatches(html).length,
      2,
      reason: 'import map + engine.js',
    );
    expect(html, contains('<script src="engine.js"></script>'));
  });

  test('no network: no remote URL in the page or the engine', () {
    for (final (name, src) in [('index.html', html), ('engine.js', engine)]) {
      expect(
        RegExp(r'https?://(?!www\.w3\.org)').hasMatch(src),
        isFalse,
        reason: name,
      );
    }
    expect(engine, isNot(contains('cdn.')));
    expect(engine, isNot(contains('__ISHARA_GLB')));
  });

  test('the engine maps no words (Q-A5, sign rule 7)', () {
    // code, not the comment that explains what was removed
    for (final gone in [
      'var ALIASES',
      'function poseNameFor',
      'WORD_MAP =',
      'window.ISHARA_WORDS',
      'signFor:',
      'function norm(',
      // labels are pack data (the greeting comes from library.json)
      "'hello'",
    ]) {
      expect(engine, isNot(contains(gone)), reason: gone);
    }
  });

  test('vendored three.js is 0.186.0 (as the prototype) and unedited', () {
    expect(readText('assets/avatar/three/VERSION').trim(), 'three@0.186.0');
    expect(readText('assets/avatar/three/LICENSE'), contains('MIT License'));
    final sums = readText('assets/avatar/three/SHA256SUMS').trim().split('\n');
    expect(sums, hasLength(6));
    for (final line in sums) {
      final [sum, path] = line.split(RegExp(r'\s+'));
      final bytes = File('assets/avatar/three/$path').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), sum, reason: path);
    }
    final proto = File('../../design/prototype.html').readAsStringSync();
    expect(proto, contains('three@0.186.0'));
  });

  test('every avatar asset folder is declared in pubspec.yaml', () {
    final pubspec = readText('pubspec.yaml');
    final dirs = {
      for (final f in Directory('assets/avatar').listSync(recursive: true))
        if (f is File) '${f.parent.path}/',
    };
    for (final d in [...dirs, 'assets/packs/asl/avatar/']) {
      expect(pubspec, contains('    - $d\n'), reason: d);
    }
  });
}
