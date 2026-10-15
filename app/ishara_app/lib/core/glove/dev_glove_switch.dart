import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dev_glove_switch.g.dart';

/// Settings › Developer (S9-3, debug / profile builds only): which glove
/// the app uses, mock or real. Only `lib/core/glove/` knows the sources;
/// screens see a name and a toggle.
class DevGloveSwitch {
  const new(this._ref);
  final Ref _ref;

  /// Never in a release build (DECISIONS 2026-10-09).
  static bool get available => !kReleaseMode;

  /// `mock` or `ble`.
  String get current => _ref.read(activeGloveKindProvider).name;

  void toggle() {
    if (!available) return;
    final now = _ref.read(activeGloveKindProvider);
    _ref
        .read(gloveSourceOverrideProvider.notifier)
        .set(
          now == GloveSourceKind.mock
              ? GloveSourceKind.ble
              : GloveSourceKind.mock,
        );
  }
}

@riverpod
DevGloveSwitch devGloveSwitch(Ref ref) {
  ref.watch(activeGloveKindProvider);
  return DevGloveSwitch(ref);
}
