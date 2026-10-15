import 'package:ishara_app/core/catalogue/word_normalizer.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:meta/meta.dart';

/// One conversation of the feed (S9-4), as History lists it.
@immutable
class Conversation {
  const new({required this.key, required this.messages});

  /// The conversation id (or `day:…` for messages from before step 9).
  final String key;

  /// Oldest first.
  final List<TalkMessage> messages;

  /// Its title time (Q-B4: date and time of the first message).
  DateTime get start => messages.first.at;
  DateTime get end => messages.last.at;
}

/// What a title's day says (the UI words it in the app language).
enum DayMarker { today, yesterday, date }

/// History's rules: grouping, titles, search.
abstract final class History {
  /// The feed's conversations, newest first; each one's messages in order.
  static List<Conversation> group(List<TalkMessage> messages) {
    final byKey = <String, List<TalkMessage>>{};
    for (final m in messages) {
      (byKey[m.conversationKey] ??= []).add(m);
    }
    final out = [
      for (final e in byKey.entries)
        Conversation(
          key: e.key,
          messages: List<TalkMessage>.unmodifiable(
            <TalkMessage>[...e.value]..sort((a, b) => a.at.compareTo(b.at)),
          ),
        ),
    ]..sort((a, b) => b.start.compareTo(a.start));
    return List.unmodifiable(out);
  }

  /// "Today", "Yesterday" or a date, for [at] seen [now] (both local
  /// times). Calendar days, so a 23-hour day doesn't skip one.
  static DayMarker marker(DateTime at, DateTime now) {
    final day = DateTime.utc(at.year, at.month, at.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    return switch (days) {
      0 => DayMarker.today,
      1 => DayMarker.yesterday,
      _ => DayMarker.date,
    };
  }

  /// Search folding: case, Arabic diacritics, alef / hamza forms, ة / ه,
  /// ى / ي (the catalogue's normalizer; punctuation becomes a space).
  static String fold(String text) => WordNormalizer.normalize(text);

  /// The first sentence of [c] that contains [query] (folded), or null.
  /// An empty query matches every conversation (its first sentence).
  static TalkMessage? match(Conversation c, String query) {
    final q = fold(query);
    if (q.isEmpty) return c.messages.first;
    for (final m in c.messages) {
      if (fold(m.text).contains(q)) return m;
    }
    return null;
  }

  /// The conversations that match [query], newest first.
  static List<(Conversation, TalkMessage)> search(
    List<Conversation> all,
    String query,
  ) => [
    for (final c in all)
      if (match(c, query) case final m?) (c, m),
  ];
}
