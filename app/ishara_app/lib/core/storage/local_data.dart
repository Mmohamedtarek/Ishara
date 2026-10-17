import 'package:drift/drift.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';

/// Every list the repositories hold, read once at start (the screens read
/// synchronously). The named values are read by `DriftKeyValueStore`.
class LocalData {
  const new({
    this.messages = const [],
    this.phrases = const [],
    this.activity = const [],
    this.contacts = const [],
    this.kept = const [],
  });

  /// The old store's data as the migration would store it: tests seed with
  /// it, and it is the fallback when the database can't open (nothing is
  /// removed from the old store then).
  factory fromLegacy(LegacyData d) => LocalData(
    messages: d.messages,
    phrases: d.phrases,
    activity: d.activity,
    contacts: d.contacts,
    kept: [for (final k in d.kept.values) ...k],
  );

  /// This data plus the old store's [parts] that couldn't move yet (shown
  /// this session; the next start moves them, newer rows win).
  LocalData withLegacy(LegacyData d, Set<LegacyPart> parts) {
    bool has(LegacyPart p) => parts.contains(p);
    final phraseIds = {for (final p in phrases) p.id};
    final activityIds = {for (final a in activity) a.id};
    return LocalData(
      messages: has(LegacyPart.talk)
          ? ([...messages, ...d.messages]
              ..sort((a, b) => a.message.at.compareTo(b.message.at)))
          : messages,
      phrases: [
        ...phrases,
        if (has(LegacyPart.phrases))
          for (final p in d.phrases)
            if (!phraseIds.contains(p.id)) p,
      ],
      activity: [
        ...activity,
        if (has(LegacyPart.activity))
          for (final a in d.activity)
            if (!activityIds.contains(a.id)) a,
      ],
      contacts: has(LegacyPart.sos)
          ? {
              ...contacts,
              ...d.contacts,
            }.take(EmergencyContactsRepository.max).toList()
          : contacts,
      kept: [...kept, for (final p in parts) ...?d.kept[p]],
    );
  }

  static Future<LocalData> load(AppDatabase db) async {
    final messages =
        await (db.select(db.messages)..orderBy([
              (t) => OrderingTerm(expression: t.atUs),
              (t) => OrderingTerm(expression: t.seq),
            ]))
            .get();
    final phrases = await db.select(db.phrases).get();
    final activity = await (db.select(
      db.activityEntries,
    )..orderBy([(t) => OrderingTerm(expression: t.seq)])).get();
    final contacts = await (db.select(
      db.contacts,
    )..orderBy([(t) => OrderingTerm(expression: t.position)])).get();
    final kept = await (db.select(
      db.keptValues,
    )..orderBy([(t) => OrderingTerm(expression: t.id)])).get();
    return LocalData(
      messages: [for (final r in messages) ?_message(r)],
      phrases: [
        for (final r in phrases)
          if (r.lang == 'en' || r.lang == 'ar')
            LocalSavedPhrasesRepository.fromRow(r),
      ],
      activity: [for (final r in activity) (id: r.id, json: r.json)],
      contacts: [
        for (final r in contacts)
          EmergencyContact(name: r.name, phone: r.phone),
      ],
      kept: [
        for (final r in kept)
          KeptValue(key: r.key, value: r.value, reason: r.reason),
      ],
    );
  }

  static StoredMessage? _message(MessageRow r) {
    final side = MessageSide.values.asNameMap()[r.side];
    final at = DateTime.tryParse(r.at);
    if (side == null || at == null) return null;
    return (
      id: r.id,
      message: TalkMessage(
        side: side,
        text: r.content,
        at: at,
        conversation: r.conversation,
      ),
    );
  }

  final List<StoredMessage> messages;
  final List<SavedPhrase> phrases;
  final List<ActivityRow> activity;
  final List<EmergencyContact> contacts;
  final List<KeptValue> kept;
}
