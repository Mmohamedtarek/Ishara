import 'dart:async';
import 'dart:convert';

import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:meta/meta.dart';

/// Who said a Talk message.
enum MessageSide {
  /// The other person: heard by the mic and signed by the avatar.
  them,

  /// The user: signed with the glove (or typed) and spoken.
  me,
}

/// One message of the Talk feed.
@immutable
class TalkMessage {
  const new({required this.side, required this.text, required this.at});

  final MessageSide side;
  final String text;

  /// When it was said (local time).
  final DateTime at;

  Map<String, Object> toJson() => {
    'side': side.name,
    'text': text,
    'at': at.toIso8601String(),
  };

  static TalkMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final side = MessageSide.values.asNameMap()[j['side']];
    final text = j['text'];
    final at = j['at'] is String ? DateTime.tryParse(j['at'] as String) : null;
    if (side == null || text is! String || at == null) return null;
    return TalkMessage(side: side, text: text, at: at);
  }

  @override
  bool operator ==(Object other) =>
      other is TalkMessage &&
      other.side == side &&
      other.text == text &&
      other.at == at;

  @override
  int get hashCode => Object.hash(side, text, at);
}

/// The Talk conversation (Q-B4: history stays on the phone). History
/// (step 8) reads it; the local database (step 10) replaces the storage.
abstract interface class ConversationRepository {
  /// Every message, oldest first.
  List<TalkMessage> get messages;

  /// [messages] after each change.
  Stream<List<TalkMessage>> get changes;

  Future<void> add(TalkMessage message);
}

/// The conversation in the phone's key-value store (S6-2 pattern), one
/// versioned JSON list.
///
/// **Migration (step 10):** the database reads [export] and calls [clear],
/// like `OnboardingStore`; the database step adds the migration test.
class LocalConversationRepository implements ConversationRepository {
  new(this._kv) : _messages = _load(_kv);

  final KeyValueStore _kv;
  final List<TalkMessage> _messages;
  final _changes = StreamController<List<TalkMessage>>.broadcast();

  static const schemaVersion = 1;
  static const kVersion = 'talk.version';
  static const kMessages = 'talk.messages';

  /// The oldest messages are dropped past this many (the key-value store
  /// is meant for small values; the database in step 10 lifts the limit).
  static const maxMessages = 500;

  static final _log = Log('conversation');

  static List<TalkMessage> _load(KeyValueStore kv) {
    final raw = kv.getString(kMessages);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) throw const FormatException('not a list');
      return [for (final j in list) ?TalkMessage.fromJson(j)];
    } on FormatException catch (e) {
      // A broken value must not stop Talk: start empty, keep the log.
      _log.warn('load_failed', {'error': e.message});
      return [];
    }
  }

  @override
  List<TalkMessage> get messages => List.unmodifiable(_messages);

  @override
  Stream<List<TalkMessage>> get changes => _changes.stream;

  @override
  Future<void> add(TalkMessage message) async {
    _messages.add(message);
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    _changes.add(messages);
    await _kv.setInt(kVersion, schemaVersion);
    await _kv.setString(
      kMessages,
      jsonEncode([for (final m in _messages) m.toJson()]),
    );
  }

  /// Every stored value by key, for the database migration.
  Map<String, Object> export() => {
    if (_kv.getInt(kVersion) case final int v) kVersion: v,
    if (_kv.getString(kMessages) case final String v) kMessages: v,
  };

  /// Removes every value (after a successful migration).
  Future<void> clear() async {
    _messages.clear();
    _changes.add(messages);
    await _kv.remove(kVersion);
    await _kv.remove(kMessages);
  }

  Future<void> dispose() => _changes.close();
}
