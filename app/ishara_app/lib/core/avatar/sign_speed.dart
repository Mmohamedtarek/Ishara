import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sign_speed.g.dart';

/// How fast the avatar signs. The avatar card's speed button cycles 1x →
/// 0.5x → 1.5x (prototype `speeds`). In memory until the Avatar studio
/// saves it (step 9, Q-A2).
@Riverpod(keepAlive: true)
class SignSpeed extends _$SignSpeed {
  /// The prototype's cycle, in order.
  static const steps = [1.0, .5, 1.5];

  @override
  double build() => steps.first;

  /// The next speed in [steps].
  void cycle() => state = steps[(steps.indexOf(state) + 1) % steps.length];
}
