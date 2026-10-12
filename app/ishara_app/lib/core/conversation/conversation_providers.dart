import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'conversation_providers.g.dart';

/// The Talk conversation, on the phone.
@Riverpod(keepAlive: true)
ConversationRepository conversationRepository(Ref ref) {
  final repo = LocalConversationRepository(ref.watch(keyValueStoreProvider));
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
