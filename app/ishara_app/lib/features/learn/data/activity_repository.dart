import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';

/// Learn's append-only activity log (Phase 0 model
/// `users/{uid}/activity/{eventId}`). Events are never changed or removed;
/// XP, medals, the streak, signs learned and unlocks are computed from them.
abstract interface class ActivityRepository {
  /// Every readable event, oldest first.
  List<ActivityEvent> get events;

  /// [events] after each change.
  Stream<List<ActivityEvent>> get changes;

  Future<void> append(ActivityEvent event);

  /// Every stored value by key (Privacy › Export).
  Map<String, Object> export();
}

/// The log in the phone's database (`activity_entries`, step 10a), read at
/// start.
///
/// Nothing is ever dropped: entries this version can't read (a newer app's
/// events) stay stored as they are and in the export, and damaged values
/// from before step 10 stay kept aside (`learn.activity.broken…`).
class LocalActivityRepository implements ActivityRepository {
  /// `initial`: every stored entry, oldest first; `broken`: the damaged
  /// values kept aside (`LocalData`).
  new(
    this._db, {
    List<ActivityRow> initial = const [],
    this._broken = const [],
  }) {
    var unread = 0;
    for (final r in initial) {
      final raw = _decode(r.json);
      _raw.add(raw);
      final e = ActivityEvent.tryParse(raw);
      if (e == null) {
        unread++;
      } else {
        _events.add(e);
      }
    }
    if (unread > 0) _log.info('unread_events', {'count': unread});
  }

  final AppDatabase _db;
  final List<KeptValue> _broken;
  final _raw = <Object?>[];
  final _events = <ActivityEvent>[];
  final _changes = StreamController<List<ActivityEvent>>.broadcast();

  /// The export's names, unchanged since step 8.
  static const schemaVersion = 1;
  static const kVersion = 'learn.activity.version';
  static const kEvents = 'learn.activity';
  static const String kBroken = LegacyKeys.activityBroken;
  static final Log _log = Log('learn');

  static Object? _decode(String json) {
    try {
      return jsonDecode(json);
    } on FormatException {
      return json;
    }
  }

  @override
  List<ActivityEvent> get events => List.unmodifiable(_events);

  @override
  Stream<List<ActivityEvent>> get changes => _changes.stream;

  @override
  Future<void> append(ActivityEvent event) async {
    final json = event.toJson();
    _raw.add(json);
    _events.add(event);
    _changes.add(events);
    // an id already stored is the same immutable event: kept once
    await _db
        .into(_db.activityEntries)
        .insert(
          ActivityEntriesCompanion.insert(id: event.id, json: jsonEncode(json)),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// The same shape as before step 10 (Privacy › Export keeps its format;
  /// nothing stored, nothing exported).
  @override
  Map<String, Object> export() => {
    if (_raw.isNotEmpty) ...{
      kVersion: schemaVersion,
      kEvents: jsonEncode(_raw),
    },
    for (final k in _broken) k.key: k.value,
  };

  Future<void> dispose() => _changes.close();
}
