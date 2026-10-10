import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';

import '../support/kit.dart';

/// Kit v3.2.3 README: during CAL OPEN / FIST / TURN the mock plays
/// `calibration/<step>.csv` (looped if the step lasts longer), never
/// rest.csv; CAL SAVE / GETCAL answer with that file's #CAL.
void main() {
  test(
    'a step plays its file from the start, loops, then rest again',
    () async {
      final lib = MockLibrary(readAsset);
      final feed = MockFeed(lib);
      addTearDown(feed.dispose);
      await feed.prepare();
      final open = await lib.load(
        MockLibrary.calibrationFile(MockPerson.a, CalStep.open),
      );
      final rest = await lib.load(MockLibrary.restFile(MockPerson.a));

      feed
        ..take(7) // somewhere in rest
        ..startCalibrationStep(CalStep.open);
      final got = feed.take(open.length + 10);
      for (var i = 0; i < got.length; i++) {
        expect(got[i], open.sample(i % open.length), reason: 'sample $i');
      }
      feed.stopCalibrationStep();
      expect(feed.take(1).single, rest.sample(7)); // rest continues
    },
  );

  test('#CAL comes from the calibration files, per person', () async {
    final lib = MockLibrary(readAsset);
    final feed = MockFeed(lib);
    addTearDown(feed.dispose);
    for (final p in MockPerson.values) {
      await feed.setPerson(p);
      final files = [
        for (final s in CalStep.values)
          await lib.load(MockLibrary.calibrationFile(p, s)),
      ];
      expect(await feed.calibrationJson(), files.first.calibrationJson);
      // the kit's three files of a person carry the same #CAL
      expect(files.map((f) => f.calibrationJson).toSet(), hasLength(1));
    }
  });
}
