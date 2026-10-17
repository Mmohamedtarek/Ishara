import 'dart:convert';
import 'dart:math';

import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:meta/meta.dart';

/// The key-value store's keys before step 10 (S6-2, S7-1, step 8, step 9).
/// Versions: onboarding v1 (step 6), talk v1 (step 7) and v2 (step 9,
/// conversation ids), learn activity v1 (step 8), settings / phrases / sos
/// v1 (step 9).
abstract final class LegacyKeys {
  // prefs: copied as they are, same names (OnboardingStore, SettingsStore)
  static const onboarding = [
    'onboarding.version',
    'setup.role',
    'setup.spoken',
    'setup.signLanguage',
    'glove.id',
    'glove.name',
    'onboarding.done',
  ];
  static const settings = [
    'settings.version',
    'settings.language',
    'settings.theme',
    'settings.bigText',
    'settings.highContrast',
    'settings.vibrate',
    'settings.subtitles',
    'settings.signSpeed',
    'settings.character',
    'settings.developer',
  ];
  static const flags = [
    'device.id',
    'talk.privacySeen',
    'talk.newConversation',
  ];

  static const talkVersion = 'talk.version';
  static const talkMessages = 'talk.messages';
  static const phrasesVersion = 'phrases.version';
  static const phrases = 'phrases.all';
  static const activityVersion = 'learn.activity.version';
  static const activity = 'learn.activity';

  /// Damaged activity values the step 8 store had moved aside
  /// (`learn.activity.broken`, `.2`, `.3`…).
  static const activityBroken = 'learn.activity.broken';
  static const sosVersion = 'sos.version';
  static const contacts = 'sos.contacts';

  static bool isActivityBroken(String k) =>
      k == activityBroken || k.startsWith('$activityBroken.');
}

/// The parts of the old store, migrated one at a time (each in its own
/// database transaction).
enum LegacyPart { prefs, talk, phrases, activity, sos, other }

/// A value kept aside instead of used (never deleted).
@immutable
class KeptValue {
  const new({required this.key, required this.value, required this.reason});

  final String key;
  final String value;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is KeptValue &&
      other.key == key &&
      other.value == value &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(key, value, reason);
}

/// A Talk message with its stable id.
typedef StoredMessage = ({String id, TalkMessage message});

/// A Learn log entry with its id, kept exactly as written.
typedef ActivityRow = ({String id, String json});

/// Everything the old store holds, read (never changed) and sorted into
/// what goes to each table. Pure: the same store gives the same data,
/// except the new message ids.
class LegacyData {
  new _({
    required this.keys,
    required this.prefs,
    required this.messages,
    required this.phrases,
    required this.activity,
    required this.contacts,
    required this.kept,
  });

  /// Reads [kv]. Damaged values and entries go to [kept], never dropped.
  factory read(KeyValueStore kv, {Random? random}) {
    final r = random ?? Random.secure();
    final keys = <LegacyPart, List<String>>{
      for (final p in LegacyPart.values) p: [],
    };
    final prefs = <String, Object>{};
    final kept = <LegacyPart, List<KeptValue>>{
      for (final p in LegacyPart.values) p: [],
    };
    const prefKeys = {
      ...LegacyKeys.onboarding,
      ...LegacyKeys.settings,
      ...LegacyKeys.flags,
    };
    for (final k in kv.keys.toList()..sort()) {
      final v = kv.read(k);
      if (v == null) continue;
      final part = switch (k) {
        _ when prefKeys.contains(k) => LegacyPart.prefs,
        LegacyKeys.talkVersion || LegacyKeys.talkMessages => LegacyPart.talk,
        LegacyKeys.phrasesVersion || LegacyKeys.phrases => LegacyPart.phrases,
        LegacyKeys.activityVersion ||
        LegacyKeys.activity => LegacyPart.activity,
        _ when LegacyKeys.isActivityBroken(k) => LegacyPart.activity,
        LegacyKeys.sosVersion || LegacyKeys.contacts => LegacyPart.sos,
        _ => LegacyPart.other,
      };
      keys[part]!.add(k);
      switch (part) {
        case LegacyPart.prefs:
          prefs[k] = v;
        case LegacyPart.other:
          kept[part]!.add(
            KeptValue(key: k, value: jsonEncode(v), reason: 'unknown key'),
          );
        case _ when LegacyKeys.isActivityBroken(k):
          kept[part]!.add(
            KeptValue(key: k, value: '$v', reason: 'damaged (kept by step 8)'),
          );
        case _:
          break;
      }
    }

    // A list value: its entries, or null when the value is damaged (then
    // kept aside whole).
    List<Object?>? list(LegacyPart part, String key, {String? keptAs}) {
      final v = kv.read(key);
      if (v == null) return const [];
      if (v is String) {
        try {
          final l = jsonDecode(v);
          if (l is List<Object?>) return l;
        } on FormatException {
          // kept below
        }
      }
      kept[part]!.add(
        KeptValue(
          key: keptAs ?? key,
          value: v is String ? v : jsonEncode(v),
          reason: 'damaged',
        ),
      );
      return null;
    }

    void keepEntry(LegacyPart part, String key, int i, Object? e, String why) =>
        kept[part]!.add(
          KeptValue(key: '$key[$i]', value: jsonEncode(e), reason: why),
        );

    String id(int bytes) => [
      for (var i = 0; i < bytes; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();

    // Talk (v1: no conversation; v2: with it). Same reader as the old store.
    final messages = <StoredMessage>[];
    final talk = list(LegacyPart.talk, LegacyKeys.talkMessages) ?? const [];
    for (var i = 0; i < talk.length; i++) {
      final m = TalkMessage.fromJson(talk[i]);
      if (m == null) {
        keepEntry(
          LegacyPart.talk,
          LegacyKeys.talkMessages,
          i,
          talk[i],
          'unreadable',
        );
      } else {
        messages.add((id: id(8), message: m));
      }
    }

    // Saved phrases (tombstones included).
    final phrases = <SavedPhrase>[];
    final rawPhrases = list(LegacyPart.phrases, LegacyKeys.phrases) ?? const [];
    for (var i = 0; i < rawPhrases.length; i++) {
      final p = SavedPhrase.fromJson(rawPhrases[i]);
      if (p == null) {
        keepEntry(
          LegacyPart.phrases,
          LegacyKeys.phrases,
          i,
          rawPhrases[i],
          'unreadable',
        );
      } else if (phrases.any((q) => q.id == p.id)) {
        keepEntry(
          LegacyPart.phrases,
          LegacyKeys.phrases,
          i,
          rawPhrases[i],
          'duplicate id',
        );
      } else {
        phrases.add(p);
      }
    }

    // The Learn log: every entry stays, readable or not (a newer app's
    // event), exactly as written. A damaged whole value is kept aside
    // under the step 8 name (`learn.activity.broken`, then `.2`…).
    final activity = <ActivityRow>[];
    var brokenKey = LegacyKeys.activityBroken;
    for (var n = 2; kv.read(brokenKey) != null; n++) {
      brokenKey = '${LegacyKeys.activityBroken}.$n';
    }
    final rawActivity =
        list(LegacyPart.activity, LegacyKeys.activity, keptAs: brokenKey) ??
        const [];
    for (var i = 0; i < rawActivity.length; i++) {
      final e = rawActivity[i];
      final json = jsonEncode(e);
      final eid =
          e is Map && e['id'] is String && (e['id'] as String).isNotEmpty
          ? e['id'] as String
          : 'unread:$i';
      final same = activity.where((a) => a.id == eid);
      if (same.isEmpty) {
        activity.add((id: eid, json: json));
      } else if (same.first.json != json) {
        keepEntry(
          LegacyPart.activity,
          LegacyKeys.activity,
          i,
          e,
          'duplicate id',
        );
      }
      // an exact copy of an entry already read is the same event: one row
    }

    // Emergency contacts (at most 3 were ever used).
    final contacts = <EmergencyContact>[];
    final rawContacts = list(LegacyPart.sos, LegacyKeys.contacts) ?? const [];
    for (var i = 0; i < rawContacts.length; i++) {
      final c = EmergencyContact.fromJson(rawContacts[i]);
      if (c == null) {
        keepEntry(
          LegacyPart.sos,
          LegacyKeys.contacts,
          i,
          rawContacts[i],
          'unreadable',
        );
      } else if (contacts.length >= EmergencyContactsRepository.max) {
        keepEntry(
          LegacyPart.sos,
          LegacyKeys.contacts,
          i,
          rawContacts[i],
          'over the limit',
        );
      } else {
        contacts.add(c);
      }
    }

    return LegacyData._(
      keys: keys,
      prefs: prefs,
      messages: messages,
      phrases: phrases,
      activity: activity,
      contacts: contacts,
      kept: kept,
    );
  }

  /// The old keys of each part (to remove after its copy is committed).
  final Map<LegacyPart, List<String>> keys;
  final Map<String, Object> prefs;
  final List<StoredMessage> messages;
  final List<SavedPhrase> phrases;
  final List<ActivityRow> activity;
  final List<EmergencyContact> contacts;
  final Map<LegacyPart, List<KeptValue>> kept;

  bool get isEmpty => keys.values.every((k) => k.isEmpty);
}
