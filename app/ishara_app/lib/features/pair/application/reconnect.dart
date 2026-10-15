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
Future<bool> reconnectPairedGlove(Ref ref) => reconnectToPairedGlove(ref);

/// One attempt to find and connect the paired glove (start-up, Talk and
/// Learn after the glove drops: S7-19, S8-1). Never asks for permissions,
/// never throws. Callers while an attempt runs share it: Talk (alive in its
/// tab) and a mission both react to the same drop, and one scan is enough.
Future<bool> reconnectToPairedGlove(Ref ref) {
  final source = ref.read(gloveSourceProvider);
  final running = _attempts[source];
  if (running != null) return running;
  final attempt = _reconnect(ref);
  _attempts[source] = attempt;
  return attempt.whenComplete(() => _attempts[source] = null);
}

final _attempts = Expando<Future<bool>>('reconnect attempts');

/// The attempt running for a glove source, if any (the UI shows
/// "Reconnecting…" while it runs).
bool reconnecting(GloveSource source) => _attempts[source] != null;

Future<bool> _reconnect(Ref ref) async {
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
