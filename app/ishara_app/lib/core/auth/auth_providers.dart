import 'package:firebase_auth/firebase_auth.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/auth/firebase_auth_repository.dart';
import 'package:ishara_app/core/backend/backend.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_providers.g.dart';

/// Where accounts and the sync go (`main` overrides it with the started
/// backend; tests keep the fakes).
@Riverpod(keepAlive: true)
Backend backend(Ref ref) => Backend.fake;

/// The account service: the local fake (S6-1) or Firebase (step 10b).
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  switch (ref.watch(backendProvider)) {
    case Backend.fake:
      final repo = FakeAuthRepository();
      ref.onDispose(repo.dispose);
      return repo;
    case Backend.unavailable:
      return const UnavailableAuthRepository();
    case Backend.firebase || Backend.emulator:
      break;
  }
  return FirebaseAuthRepository(
    FirebaseAuth.instance,
    language: () => ref.read(appSettingsControllerProvider).language.name,
  );
}
