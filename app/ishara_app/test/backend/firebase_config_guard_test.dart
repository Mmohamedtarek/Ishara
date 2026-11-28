import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Step 10b: the repo is public. The Firebase project's config files and the
/// release signing details (v1.0) stay on the developer's machine (the
/// repo's `.gitignore` files), and no Google API key or keystore is ever
/// committed. Nothing here prints a file's contents.
void main() {
  /// The config files, at the places they would be put.
  const configFiles = [
    'app/ishara_app/android/app/google-services.json',
    'app/ishara_app/ios/Runner/GoogleService-Info.plist',
    'app/ishara_app/lib/firebase_options.dart',
    'app/ishara_app/firebase.defines.json',
    'firebase/.firebaserc',
    'app/ishara_app/android/key.properties',
    'app/ishara_app/android/app/upload-keystore.jks',
    'ishara-release.jks',
    'ishara-release.keystore',
  ];

  String git(List<String> args, {Set<int> ok = const {0}}) {
    final r = Process.runSync('git', args, workingDirectory: '../..');
    expect(
      ok,
      contains(r.exitCode),
      reason: 'git ${args.join(' ')}: ${r.stderr}',
    );
    return r.stdout as String;
  }

  test('no Firebase config file is tracked', () {
    final tracked = git(['ls-files'])
        .split('\n')
        .where(
          (p) => configFiles.any((c) => p.split('/').last == c.split('/').last),
        )
        .toList();
    expect(tracked, isEmpty);
  });

  test('a tracked .gitignore (not only a local exclude) ignores each one', () {
    for (final f in configFiles) {
      // -v names the rule that matched; .gitignore rules win over
      // .git/info/exclude, so a local exclude alone would show here (the
      // deepest .gitignore wins, e.g. android/.gitignore for key.properties)
      final out = git(['check-ignore', '-v', '--no-index', f], ok: {0, 1});
      expect(
        out,
        matches(RegExp(r'^([^\s:]+/)?\.gitignore:')),
        reason: '$f is not ignored',
      );
    }
  });

  test('no keystore is tracked', () {
    final keystores = git(['ls-files', '*.jks', '*.keystore', '*.p12']);
    expect(keystores.trim(), isEmpty);
  });

  test('no tracked file holds a Google API key', () {
    // -l: file names only, never the matching text
    final files = git(['grep', '-lE', 'AIza[0-9A-Za-z_-]{35}'], ok: {0, 1});
    expect(files.trim(), isEmpty);
  });

  // The project id comes from the developer's own google-services.json, so
  // it is written nowhere in git, this test included. Without the file (CI)
  // there is nothing to look for.
  final services = File('android/app/google-services.json');
  test(
    "no tracked file names the real project's id",
    () {
      final info =
          (jsonDecode(services.readAsStringSync())
                  as Map<String, Object?>)['project_info']
              as Map<String, Object?>?;
      final id = info?['project_id'];
      expect(id, isA<String>(), reason: 'google-services.json: no project_id');
      // -F: the id as plain text; -l: file names only, never the id
      final files = git(['grep', '-lF', id! as String], ok: {0, 1});
      expect(files.trim(), isEmpty);
    },
    skip: services.existsSync()
        ? false
        : 'no google-services.json on this machine (CI): nothing to check',
  );
}
