import 'package:flutter/services.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'haptics.g.dart';

/// Settings › Vibrate (S9-1): a short pulse when a glove word is spoken, a
/// heard sentence starts signing or a practice step passes; a long one when
/// SOS is pressed. The phone's haptic feedback: no permission.
abstract interface class Haptics {
  Future<void> short();
  Future<void> long();
}

class PlatformHaptics implements Haptics {
  const new();

  @override
  Future<void> short() => HapticFeedback.mediumImpact();

  @override
  Future<void> long() async {
    // a long pulse: the system's vibrate, then two heavy impacts
    await HapticFeedback.vibrate();
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.heavyImpact();
  }
}

/// The phone's haptics (tests override it with a recorder).
@Riverpod(keepAlive: true)
Haptics haptics(Ref ref) => const PlatformHaptics();

/// Pulses only when Settings › Vibrate is on.
class Vibrate {
  const new(this._ref);
  final Ref _ref;

  bool get _on => _ref.read(appSettingsControllerProvider).vibrate;

  void short() {
    if (_on) _ref.read(hapticsProvider).short().ignore();
  }

  void long() {
    if (_on) _ref.read(hapticsProvider).long().ignore();
  }
}

/// [Vibrate] for the app (reads Settings › Vibrate each time).
@riverpod
Vibrate vibrate(Ref ref) => Vibrate(ref);
