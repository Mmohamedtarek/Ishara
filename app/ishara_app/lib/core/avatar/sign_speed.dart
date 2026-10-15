import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sign_speed.g.dart';

/// How fast the avatar signs: the speed the Avatar studio saved (1x until
/// then). The avatar card's speed button cycles 1x → 0.5x → 1.5x
/// (prototype `speeds`) for this session; only the studio's Save keeps it
/// (S7-3, Q-A2).
@Riverpod(keepAlive: true)
class SignSpeed extends _$SignSpeed {
  /// The prototype's cycle, in order.
  static const steps = [1.0, .5, 1.5];

  @override
  double build() {
    final saved = ref.watch(settingsStoreProvider).signSpeed;
    return steps.contains(saved) ? saved! : steps.first;
  }

  /// The next speed in [steps] (this session).
  void cycle() => state = next(state);

  static double next(double speed) =>
      steps[(steps.indexOf(speed) + 1) % steps.length];

  /// The Avatar studio's Save.
  Future<void> save(double speed) async {
    state = speed;
    await ref.read(settingsStoreProvider).setSignSpeed(speed);
  }
}
