import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
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

/// The Talk conversation (Q-B4: history stays on the phone, never synced).
/// History reads it.
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

  /// Every stored value by key (Privacy › Export).
  Map<String, Object> export();
}

/// The conversation in the phone's database (`messages`, step 10a). Every
/// message is read at start (History reads them synchronously); there is
/// no size limit any more (2026-10-12).
class LocalConversationRepository implements ConversationRepository {
  /// `initial`: the stored messages, oldest first (`LocalData`). The
  /// key-value store holds Clear's "next message starts a new conversation"
  /// flag. `gap`: the S9-4 silence rule (from `app_rules.json`).
  new(
    this._db,
    this._kv, {
    required this._gap,
    List<StoredMessage> initial = const [],
    Random? random,
  }) : _random = random ?? Random.secure(),
       _rows = [...initial];

  final AppDatabase _db;
  final KeyValueStore _kv;
  final Duration Function() _gap;
  final Random _random;
  final List<StoredMessage> _rows;
  final _changes = StreamController<List<TalkMessage>>.broadcast();

  /// The message JSON's shape in the export (talk v2: with conversation
  /// ids), unchanged since step 9.
  static const schemaVersion = 2;
  static const kVersion = 'talk.version';
  static const kMessages = 'talk.messages';

  /// Set by Clear: the next message starts a new conversation (kept across
  /// a restart).
  static const kNewNext = 'talk.newConversation';

  @override
  List<TalkMessage> get messages =>
      List.unmodifiable([for (final r in _rows) r.message]);

  @override
  Stream<List<TalkMessage>> get changes => _changes.stream;

  String _newId(int bytes) => [
    for (var i = 0; i < bytes; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  static MessagesCompanion _row(StoredMessage r) => MessagesCompanion.insert(
    id: r.id,
    conversation: Value(r.message.conversation),
    side: r.message.side.name,
    content: r.message.text,
    at: r.message.at.toIso8601String(),
    atUs: r.message.at.microsecondsSinceEpoch,
  );

  @override
  Future<void> add(TalkMessage message) async {
    final last = _rows.isEmpty ? null : _rows.last.message;
    final fresh = startsNewConversation(
      last: last,
      at: message.at,
      cleared: _kv.getBool(kNewNext) ?? false,
      gap: _gap(),
    );
    // An older (no id) conversation that goes on gets one id for all of it.
    final adopted = <String>[];
    final String conversation;
    if (fresh) {
      conversation = _newId(8);
    } else if (last!.conversation case final String c) {
      conversation = c;
    } else {
      conversation = _newId(8);
      final key = last.conversationKey;
      for (var i = 0; i < _rows.length; i++) {
        if (_rows[i].message.conversationKey == key) {
          adopted.add(_rows[i].id);
          _rows[i] = (
            id: _rows[i].id,
            message: _rows[i].message.inConversation(conversation),
          );
        }
      }
    }
    final row = (id: _newId(8), message: message.inConversation(conversation));
    _rows.add(row);
    _changes.add(messages);
    await _db.transaction(() async {
      if (adopted.isNotEmpty) {
        await (_db.update(_db.messages)..where((t) => t.id.isIn(adopted)))
            .write(MessagesCompanion(conversation: Value(conversation)));
      }
      await _db.into(_db.messages).insert(_row(row));
    });
    await _kv.remove(kNewNext);
  }

  @override
  Future<void> startNewConversation() => _kv.setBool(kNewNext, value: true);

  @override
  Future<List<TalkMessage>> deleteConversation(String key) async {
    final removed = [
      for (final r in _rows)
        if (r.message.conversationKey == key) r,
    ];
    if (removed.isEmpty) return const [];
    // The newest conversation gone: the next message never joins an older
    // one (it may have been cleared before, S9-4).
    final newest = identical(removed.last, _rows.last);
    _rows.removeWhere((r) => r.message.conversationKey == key);
    _changes.add(messages);
    final ids = [for (final r in removed) r.id];
    await (_db.delete(_db.messages)..where((t) => t.id.isIn(ids))).go();
    if (newest) await startNewConversation();
    return [for (final r in removed) r.message];
  }

  @override
  Future<void> restore(List<TalkMessage> messages) async {
    if (messages.isEmpty) return;
    final back = [for (final m in messages) (id: _newId(8), message: m)];
    _rows
      ..addAll(back)
      ..sort((a, b) => a.message.at.compareTo(b.message.at));
    _changes.add(this.messages);
    await _db.batch((b) => b.insertAll(_db.messages, back.map(_row)));
  }

  @override
  Future<void> deleteAll() async {
    _rows.clear();
    _changes.add(messages);
    await _db.delete(_db.messages).go();
  }

  /// The same shape as before step 10 (Privacy › Export keeps its format;
  /// nothing stored, nothing exported).
  @override
  Map<String, Object> export() => {
    if (_rows.isNotEmpty) ...{
      kVersion: schemaVersion,
      kMessages: jsonEncode([for (final r in _rows) r.message.toJson()]),
    },
    if (_kv.getBool(kNewNext) case final bool v) kNewNext: v,
  };

  Future<void> dispose() => _changes.close();
}
