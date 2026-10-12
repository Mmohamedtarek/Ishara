import 'package:flutter/services.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'keep_screen_on.g.dart';

/// Keeps the screen on (S7-5: only while Talk is visible and the app is in
/// the foreground).
abstract interface class KeepScreenOn {
  Future<void> set({required bool on});
}

/// The app's own channel (`MainActivity` / `AppDelegate`: the window's
/// keep-screen-on flag / the idle timer); no package (user, 2026-10-13).
class PlatformKeepScreenOn implements KeepScreenOn {
  const new();

  static const _channel = MethodChannel('ishara/screen');
  static final _log = Log('screen');

  @override
  Future<void> set({required bool on}) async {
    try {
      await _channel.invokeMethod<void>('keepOn', on);
    } on Object catch (e) {
      // Tests and platforms without the channel: the screen just sleeps.
      _log.info('keep_on_unavailable', {'error': e.runtimeType.toString()});
    }
  }
}

@Riverpod(keepAlive: true)
KeepScreenOn keepScreenOn(Ref ref) => const PlatformKeepScreenOn();
