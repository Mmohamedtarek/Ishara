import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_providers.g.dart';

/// The phone's key-value store. In memory unless `main` overrides it with
/// the opened [SharedPrefsKeyValueStore] (tests keep the memory one).
@Riverpod(keepAlive: true)
KeyValueStore keyValueStore(Ref ref) => MemoryKeyValueStore();

@Riverpod(keepAlive: true)
OnboardingStore onboardingStore(Ref ref) =>
    OnboardingStore(ref.watch(keyValueStoreProvider));

/// The onboarding answers and state the screens use.
@immutable
class Profile {
  const new({
    this.role = UserRole.sign,
    this.spoken = SpokenLanguage.ar,
    this.glove,
    this.onboardingDone = false,
  });

  final UserRole role;
  final SpokenLanguage spoken;
  final PairedGlove? glove;
  final bool onboardingDone;

  Profile copyWith({
    UserRole? role,
    SpokenLanguage? spoken,
    PairedGlove? glove,
    bool clearGlove = false,
    bool? onboardingDone,
  }) => Profile(
    role: role ?? this.role,
    spoken: spoken ?? this.spoken,
    glove: clearGlove ? null : glove ?? this.glove,
    onboardingDone: onboardingDone ?? this.onboardingDone,
  );
}

/// Loads the saved answers at start and saves every change (S6-2).
@Riverpod(keepAlive: true)
class ProfileController extends _$ProfileController {
  OnboardingStore get _store => ref.read(onboardingStoreProvider);

  @override
  Profile build() {
    final s = ref.watch(onboardingStoreProvider);
    return Profile(
      role: s.role,
      spoken: s.spoken,
      glove: s.glove,
      onboardingDone: s.done,
    );
  }

  Future<void> setRole(UserRole role) async {
    state = state.copyWith(role: role);
    await _store.saveRole(role);
  }

  Future<void> setSpoken(SpokenLanguage spoken) async {
    state = state.copyWith(spoken: spoken);
    await _store.saveSpoken(spoken);
  }

  Future<void> setGlove(PairedGlove glove) async {
    state = state.copyWith(glove: glove);
    await _store.saveGlove(glove);
  }

  Future<void> forgetGlove() async {
    state = state.copyWith(clearGlove: true);
    await _store.forgetGlove();
  }

  /// Onboarding reached Ready: from now on the app starts on Talk.
  Future<void> finishOnboarding() async {
    state = state.copyWith(onboardingDone: true);
    await _store.saveDone(done: true);
  }
}
