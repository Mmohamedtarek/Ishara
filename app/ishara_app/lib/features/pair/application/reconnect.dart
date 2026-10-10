import 'dart:async';

import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reconnect.g.dart';

/// At start-up, after onboarding: looks for the paired glove (S6-2) and
/// connects to it. Never asks for permissions (no prompt at start-up) and
/// never throws: Talk shows the glove's state (step 7). Completes with
/// whether the glove is connected.
@Riverpod(keepAlive: true)
Future<bool> reconnectPairedGlove(Ref ref) async {
  final log = Log('reconnect');
  final paired = ref.read(profileControllerProvider).glove;
  if (paired == null) return false;
  final source = ref.read(gloveSourceProvider);
  if (source.status.isConnected) return true;
  if (!await ref.read(glovePermissionsProvider).granted()) {
    log.info('skipped_no_permission');
    return false;
  }
  try {
    DiscoveredGlove? found;
    // leaving the loop cancels the scan: the radio stops before connecting
    await for (final list in source.scan()) {
      found = list.where((g) => g.id == paired.id).firstOrNull;
      if (found != null) break;
    }
    if (found == null) {
      log.info('not_found');
      return false;
    }
    await source.connect(found);
    if (source.status.mpuFail) {
      // as in pairing (Q-K3 check 2): no motion sensor, no recognition
      log.info('mpu_fail');
      await source.disconnect();
      return false;
    }
    log.info('reconnected');
    return true;
  } on GloveFailure catch (f) {
    log.failure('reconnect_failed', f);
  }
  return false;
}
