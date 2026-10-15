import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/features/history/domain/history.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'history_providers.g.dart';

/// The feed's conversations, newest first (S9-4, S9-5).
@riverpod
List<Conversation> historyConversations(Ref ref) =>
    History.group(ref.watch(conversationProvider).value ?? const []);

/// History's actions on starred phrases (kept: widgets only read it, and
/// its work goes on after the tap).
@Riverpod(keepAlive: true)
HistoryActions historyActions(Ref ref) => HistoryActions(ref);

class HistoryActions {
  const new(this._ref);
  final Ref _ref;

  SavedPhrasesRepository get _phrases =>
      _ref.read(savedPhrasesRepositoryProvider);

  bool isStarred(String text) => _phrases.find(text) != null;

  /// Stars or unstars [text]; returns whether it is starred now.
  Future<bool> toggleStar(String text) async {
    if (isStarred(text)) {
      await _phrases.unstar(text);
      return false;
    }
    await _phrases.star(text);
    return true;
  }

  /// Speaks a saved phrase in the spoken-language voice (S7-17, S7-23).
  /// Without a voice for that language nothing is spoken (S7-11).
  Future<void> speak(String text) async {
    final tts = _ref.read(textToSpeechProvider);
    final language = _ref.read(profileControllerProvider).spoken;
    if (!await tts.setLanguage(language)) return;
    await tts.speak(text);
  }
}
