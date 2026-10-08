// The app's copy of the AI team's Mobile Kit must be byte-identical to
// app/Ishara-Mobile-Kit/. If this fails, run app/tools/sync_kit.sh
// (never copy kit files by hand).
@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _parts = ['model', 'mock', 'test'];

/// Relative path -> sha256 of every file under [root]/[_parts].
Map<String, String> _hashes(String root) {
  final out = <String, String>{};
  for (final part in _parts) {
    final dir = Directory(p.join(root, part));
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: root)));
      out[rel] = sha256.convert(f.readAsBytesSync()).toString();
    }
  }
  return out;
}

void main() {
  // `flutter test` runs with the package root as the working directory.
  final kit = p.normalize(
    p.join(Directory.current.path, '..', 'Ishara-Mobile-Kit'),
  );
  const assets = 'assets/kit';

  test('the kit folder exists', () {
    for (final part in _parts) {
      expect(Directory(p.join(kit, part)).existsSync(), isTrue, reason: part);
    }
  });

  test('assets/kit has exactly the kit files, byte for byte', () {
    final want = _hashes(kit);
    final have = _hashes(assets);
    expect(want, isNotEmpty);
    expect(
      have.keys.toSet().difference(want.keys.toSet()),
      isEmpty,
      reason: 'files in assets/kit that the kit does not have',
    );
    expect(
      want.keys.toSet().difference(have.keys.toSet()),
      isEmpty,
      reason: 'kit files missing from assets/kit',
    );
    final changed = [
      for (final e in want.entries)
        if (have[e.key] != e.value) e.key,
    ];
    expect(changed, isEmpty, reason: 'files that differ from the kit');
  });

  test('pubspec.yaml declares every asset directory that holds files', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync().map((l) => l.trim());
    final declared = {
      for (final l in pubspec)
        if (l.startsWith('- assets/kit/')) l.substring(2),
    };
    final needed = {
      for (final rel in _hashes(assets).keys) '${p.posix.dirname(rel)}/',
    }.map((d) => 'assets/kit/$d').toSet();
    expect(declared, containsAll(needed));
  });
}
