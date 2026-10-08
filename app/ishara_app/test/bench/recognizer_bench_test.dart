// Time per recognizer step (3 models + Decider) on this machine.
// Budget: < 20 ms per step on a mid-range phone (measured in the
// performance step). Run: flutter test --run-skipped --tags bench test/bench
@Tags(['bench'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/recognition/calibration.dart';
import 'package:ishara_app/core/recognition/recognizer.dart';

import '../support/kit.dart';

void main() {
  test('recognizer step time', () async {
    final bundle = await loadKitBundle();
    final ensemble = bundle.buildEnsemble();
    final rec = Recording.parse(readText('assets/kit/mock/A/everyday.csv'));
    final times = <int>[];
    final sw = Stopwatch();
    final r = Recognizer(
      labels: bundle.labels,
      config: bundle.config,
      calibration: GloveCalibration.parse(rec.calibrationJson!),
      predict: (w) {
        sw
          ..reset()
          ..start();
        final p = ensemble.predict(w);
        times.add((sw..stop()).elapsedMicroseconds);
        return p;
      },
    );
    final total = Stopwatch()..start();
    for (var k = 0; k < rec.length; k++) {
      r.feed(k, rec.sample(k));
    }
    total.stop();
    times.sort();
    final mean = times.reduce((a, b) => a + b) / times.length;
    final p95 = times[(times.length * .95).floor()];
    String ms(num micros) => (micros / 1000).toStringAsFixed(3);
    final perStep = total.elapsedMicroseconds / times.length;
    // The benchmark's output is its result.
    // ignore: avoid_print
    print(
      'steps ${times.length}, model mean ${ms(mean)} ms, p95 ${ms(p95)} ms, '
      'max ${ms(times.last)} ms; whole step ${ms(perStep)} ms',
    );
    expect(p95, lessThan(20000));
    ensemble.close();
  });
}
