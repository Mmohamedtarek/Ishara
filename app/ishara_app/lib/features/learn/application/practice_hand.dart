import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/live_hand.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'practice_hand.g.dart';

/// The practice step's live hand (prototype `.split` panes): finger bend
/// from the glove's raw samples and its own `#CAL`. Display only:
/// recognition never uses it (`LiveHand`). [revision] ticks per batch.
class PracticeHand {
  final hand = LiveHand();
  final revision = ValueNotifier<int>(0);
}

@riverpod
PracticeHand practiceHand(Ref ref) {
  final glove = ref.watch(gloveSourceProvider);
  final h = PracticeHand();
  void useCal() {
    final cal = glove.status.calibration;
    if (cal != null) h.hand.useCalibration(cal);
  }

  useCal();
  final subs = [
    glove.samples.listen((batch) {
      batch.forEach(h.hand.add);
      h.revision.value++;
    }),
    glove.statusChanges.listen((_) => useCal()),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      unawaited(s.cancel());
    }
    h.revision.dispose();
  });
  return h;
}
