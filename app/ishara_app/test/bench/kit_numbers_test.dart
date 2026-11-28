// Words the app's own recognizer gives on a kit's mock files, to compare kit
// versions (e.g. v3.2.3 against v3.3). Not a check: it writes numbers.
//
//   ISHARA_KIT=<kit folder with model/>   (default: the synced kit)
//   ISHARA_MOCK=<folder with A/ and B/>   (default: <kit>/mock)
//   ISHARA_RULES=v3.2.1                   (optional: drop the v3.3 Decider
//                                          keys, to see what the rules add)
//   ISHARA_OUT=<file.json>                (default: print)
//   flutter test --run-skipped --tags bench test/bench/kit_numbers_test.dart
@Tags(['bench'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';
import 'package:path/path.dart' as p;

import '../support/kit.dart';

void main() {
  test('kit numbers', () async {
    final env = Platform.environment;
    final kit = env['ISHARA_KIT'] ?? 'assets/packs/asl/kit';
    final mock = env['ISHARA_MOCK'] ?? p.join(kit, 'mock');
    final bundle = await ModelBundle.load(readAsset, dir: p.join(kit, 'model'));
    var config = bundle.config;
    if (env['ISHARA_RULES'] == 'v3.2.1') {
      // The same decider.json without the v3.3 keys (their defaults).
      final root =
          jsonDecode(readText(p.join(kit, 'model', 'decider.json'))) as Map;
      final cnn = (root['cnn'] as Map).cast<String, Object?>()
        ..removeWhere(
          (k, _) => const {
            'pair_level',
            'confirm_on_rest',
            'rest_conf',
            'rest_run',
            'rest_null',
          }.contains(k),
        );
      config = DeciderConfig.fromJson(cnn);
    }
    final ensemble = bundle.buildEnsemble();
    addTearDown(ensemble.close);
    final out = <String, Object?>{};
    final files =
        Directory(mock)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.csv'))
            .where((f) => !f.path.contains('${p.separator}calibration'))
            .map((f) => p.relative(f.path, from: mock))
            .toList()
          ..sort();
    for (final name in files) {
      final rec = Recording.parse(readText(p.join(mock, name)), name: name);
      final r = Recognizer(
        labels: bundle.labels,
        config: config,
        predict: ensemble.predict,
        calibration: GloveCalibration.parse(rec.calibrationJson!),
      );
      final events = <List<Object>>[];
      for (var k = 0; k < rec.length; k++) {
        for (final s in r.feed(k % 65536, rec.sample(k)).steps) {
          var top = 0;
          for (var i = 1; i < s.smoothed.length; i++) {
            if (s.smoothed[i] > s.smoothed[top]) top = i;
          }
          for (final e in s.events) {
            // The Learn match % (Q-L4) and the step's top label.
            final i = bundle.labels.indexOf(e.label)!;
            events.add([
              k + 1,
              e.kind.name,
              e.label,
              (s.smoothed[i] * 100).round(),
              bundle.labels.all[top],
            ]);
          }
        }
      }
      out[name] = {
        'samples': rec.length,
        'words': [
          for (final e in events)
            if (e[1] == DeciderEventKind.word.name ||
                e[1] == DeciderEventKind.confirm.name)
              e[2],
        ],
        'events': events,
      };
    }
    final json = const JsonEncoder.withIndent(' ').convert(out);
    final path = env['ISHARA_OUT'];
    if (path == null) {
      // The benchmark's output is its result.
      // ignore: avoid_print
      print(json);
    } else {
      File(path).writeAsStringSync(json);
    }
    expect(out, isNotEmpty);
  });
}
