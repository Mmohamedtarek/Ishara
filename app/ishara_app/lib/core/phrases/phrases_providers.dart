import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'phrases_providers.g.dart';

/// Starred sentences, on the phone (the sync comes with step 10b).
@Riverpod(keepAlive: true)
SavedPhrasesRepository savedPhrasesRepository(Ref ref) {
  final repo = LocalSavedPhrasesRepository(
    ref.watch(appDatabaseProvider),
    initial: ref.watch(localDataProvider).phrases,
  );
  ref.onDispose(repo.dispose);
  return repo;
}

/// The live phrases for the UI (starts with the current list).
@Riverpod(keepAlive: true)
Stream<List<SavedPhrase>> savedPhrases(Ref ref) async* {
  final repo = ref.watch(savedPhrasesRepositoryProvider);
  yield repo.phrases;
  yield* repo.changes;
}
