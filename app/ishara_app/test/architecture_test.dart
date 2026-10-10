// Rules from the prompt that code review alone can miss.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where(
      (f) => !f.path.endsWith('.g.dart') && !f.path.endsWith('.freezed.dart'),
    )
    .where((f) => !f.path.contains('/l10n/gen/'));

void main() {
  test('only lib/core/glove/ knows which glove source is active', () {
    final forbidden = RegExp(
      r'GloveSourceKind|activeGloveKind|gloveSourceOverride|MockGlove\b|'
      r'mock_glove\.dart|mockGloveProvider|PendingBleTransport|ReactiveBleTransport|FlutterReactiveBleApi',
    );
    final offenders = [
      for (final f in _dartFiles('lib'))
        if (!f.path.startsWith('lib/core/glove/') &&
            forbidden.hasMatch(f.readAsStringSync()))
          f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('no model label is hard-coded in lib/ (they come from labels.txt)', () {
    final labels = File('assets/packs/asl/kit/model/labels.txt')
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    expect(labels, hasLength(22));
    final offenders = <String>[];
    for (final f in _dartFiles('lib')) {
      // Prototype icon names ('yes', 'no', 'sorry'…), generated: not words.
      if (f.path == 'lib/core/ui/ishara_icon_data.dart') continue;
      final src = f.readAsStringSync();
      for (final label in labels) {
        if (!RegExp('[\'"]$label[\'"]').hasMatch(src)) continue;
        // AI-SPEC §4 names the two non-words; that constant is allowed.
        // The avatar engine reserves "rest" for its ready pose (not a label).
        final allowed =
            ((label == 'rest' || label == 'other') &&
                f.path == 'lib/core/recognition/recognition_config.dart') ||
            (label == 'rest' &&
                f.path == 'lib/core/avatar/avatar_library.dart') ||
            // ICU `select` key for the avatar's gender, not a sign label
            (label == 'other' && f.path == 'lib/core/avatar/avatar_cast.dart');
        if (!allowed) offenders.add('${f.path}: "$label"');
      }
    }
    expect(offenders, isEmpty);
  });
}
