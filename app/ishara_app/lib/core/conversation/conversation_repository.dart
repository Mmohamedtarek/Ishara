import 'dart:async';
import 'dart:convert';
import 'dart:math';

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
  const new({
    required this.side,
    required this.text,
    required this.at,
    this.conversation,
  });

  final MessageSide side;
  final String text;

  /// When it was said (local time).
  final DateTime at;

  /// The conversation it belongs to (S9-4). Null for messages stored before
  /// step 9: they are grouped per local day ([conversationKey]).
  final String? conversation;

  /// The conversation id, or `day:yyyy-mm-dd` for older messages.
  String get conversationKey =>
      conversation ??
      'day:${at.year.toString().padLeft(4, '0')}-'
          '${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')}';

  TalkMessage inConversation(String id) =>
      TalkMessage(side: side, text: text, at: at, conversation: id);

  Map<String, Object> toJson() => {
    'side': side.name,
    'text': text,
    'at': at.toIso8601String(),
    'conversation': ?conversation,
  };

  static TalkMessage? fromJson(Object? j) {
    if (j is! Map) return null;
    final side = MessageSide.values.asNameMap()[j['side']];
    final text = j['text'];
    final at = j['at'] is String ? DateTime.tryParse(j['at'] as String) : null;
    final conversation = j['conversation'];
    if (side == null ||
        text is! String ||
        at == null ||
        (conversation != null && conversation is! String)) {
      return null;
    }
    return TalkMessage(
      side: side,
      text: text,
      at: at,
      conversation: conversation as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TalkMessage &&
      other.side == side &&
      other.text == text &&
      other.at == at &&
      other.conversation == conversation;

  @override
  int get hashCode => Object.hash(side, text, at, conversation);
}

/// S9-4: does a message at [at] start a new conversation after [last]?
/// Yes for the first message, after Clear ([cleared]), on a new local day,
/// or after more than [gap] with no message. Going to the background never
/// splits one.
bool startsNewConversation({
  required TalkMessage? last,
  required DateTime at,
  required bool cleared,
  required Duration gap,
}) {
  if (last == null || cleared) return true;
  final a = last.at;
  if (a.year != at.year || a.month != at.month || a.day != at.day) {
    return true;
  }
  return at.difference(a) > gap;
}

/// The Talk conversation (Q-B4: history stays on the phone). History reads
/// it; the local database (step 10) replaces the storage.
abstract interface class ConversationRepository {
  /// Every message, oldest first.
  List<TalkMessage> get messages;

  /// [messages] after each change.
  Stream<List<TalkMessage>> get changes;

  /// Adds [message] to the current conversation, or starts a new one
  /// (S9-4); the stored message carries its conversation id.
  Future<void> add(TalkMessage message);

  /// Talk's Clear: the next message starts a new conversation.
  Future<void> startNewConversation();

  /// Removes a conversation's messages (History); returns them for Undo.
  Future<List<TalkMessage>> deleteConversation(String key);

  /// Puts deleted messages back (Undo).
  Future<void> restore(List<TalkMessage> messages);

  /// Settings › Privacy › Clear history.
  Future<void> deleteAll();

  /// Every stored value by key (Privacy › Export, step 10 migration).
  Map<String, Object> export();
}

/// The conversation in the phone's key-value store (S6-2 pattern), one
/// versioned JSON list.
///
/// **Migration (step 10):** the database reads [export] and calls [clear],
/// like `OnboardingStore`; the database step adds the migration test.
class LocalConversationRepository implements ConversationRepository {
  /// [gap]: the S9-4 silence rule (from `app_rules.json`).
  new(this._kv, {required this._gap, Random? random})
    : _random = random ?? Random.secure(),
      _messages = _load(_kv);

  final KeyValueStore _kv;
  final Duration Function() _gap;
  final Random _random;
  final List<TalkMessage> _messages;
  final _changes = StreamController<List<TalkMessage>>.broadcast();

  static const schemaVersion = 2;
  static const kVersion = 'talk.version';
  static const kMessages = 'talk.messages';

  /// Set by Clear: the next message starts a new conversation (kept across
  /// a restart).
  static const kNewNext = 'talk.newConversation';

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

  String _newId() => [
    for (var i = 0; i < 8; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  @override
  Future<void> add(TalkMessage message) async {
    final last = _messages.isEmpty ? null : _messages.last;
    final fresh = startsNewConversation(
      last: last,
      at: message.at,
      cleared: _kv.getBool(kNewNext) ?? false,
      gap: _gap(),
    );
    final id = fresh
        ? _newId()
        : (last!.conversation ?? _newIdFor(last.conversationKey));
    _messages.add(message.inConversation(id));
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    await _kv.remove(kNewNext);
    await _save();
  }

  // An older (no id) conversation that goes on gets one id for all of it.
  String _newIdFor(String key) {
    final id = _newId();
    for (var i = 0; i < _messages.length; i++) {
      if (_messages[i].conversationKey == key) {
        _messages[i] = _messages[i].inConversation(id);
      }
    }
    return id;
  }

  @override
  Future<void> startNewConversation() => _kv.setBool(kNewNext, value: true);

  @override
  Future<List<TalkMessage>> deleteConversation(String key) async {
    final removed = [
      for (final m in _messages)
        if (m.conversationKey == key) m,
    ];
    if (removed.isEmpty) return const [];
    // The newest conversation gone: the next message never joins an older
    // one (it may have been cleared before, S9-4).
    final newest = identical(removed.last, _messages.last);
    _messages.removeWhere((m) => m.conversationKey == key);
    await _save();
    if (newest) await startNewConversation();
    return removed;
  }

  @override
  Future<void> restore(List<TalkMessage> messages) async {
    if (messages.isEmpty) return;
    _messages
      ..addAll(messages)
      ..sort((a, b) => a.at.compareTo(b.at));
    await _save();
  }

  @override
  Future<void> deleteAll() async {
    _messages.clear();
    await _save();
  }

  Future<void> _save() async {
    _changes.add(messages);
    await _kv.setInt(kVersion, schemaVersion);
    await _kv.setString(
      kMessages,
      jsonEncode([for (final m in _messages) m.toJson()]),
    );
  }

  @override
  Map<String, Object> export() => {
    if (_kv.getInt(kVersion) case final int v) kVersion: v,
    if (_kv.getString(kMessages) case final String v) kMessages: v,
    if (_kv.getBool(kNewNext) case final bool v) kNewNext: v,
  };

  /// Removes every value (after a successful migration).
  Future<void> clear() async {
    _messages.clear();
    _changes.add(messages);
    await _kv.remove(kVersion);
    await _kv.remove(kMessages);
    await _kv.remove(kNewNext);
  }

  Future<void> dispose() => _changes.close();
}
