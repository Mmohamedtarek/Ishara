import 'package:ishara_app/core/config/app_rules.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'conversation_providers.g.dart';

/// The Talk conversation, on the phone.
@Riverpod(keepAlive: true)
ConversationRepository conversationRepository(Ref ref) {
  final rules = ref.watch(appRulesProvider);
  final repo = LocalConversationRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(keyValueStoreProvider),
    initial: ref.watch(localDataProvider).messages,
    // main loads the rules before the first frame
    gap: () => rules.requireValue.conversationGap,
  );
  ref.onDispose(repo.dispose);
  return repo;
}

/// The messages for the UI (starts with the current list).
@Riverpod(keepAlive: true)
Stream<List<TalkMessage>> conversation(Ref ref) async* {
  final repo = ref.watch(conversationRepositoryProvider);
  yield repo.messages;
  yield* repo.changes;
}
