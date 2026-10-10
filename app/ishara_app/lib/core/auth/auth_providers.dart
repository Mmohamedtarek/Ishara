import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_providers.g.dart';

/// The account service. The local fake until Firebase (step 10, S6-1).
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  final repo = FakeAuthRepository();
  ref.onDispose(repo.dispose);
  return repo;
}
