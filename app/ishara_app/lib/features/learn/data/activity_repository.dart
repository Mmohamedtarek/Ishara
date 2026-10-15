import 'dart:async';
import 'dart:convert';

import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
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

  /// Every stored value by key (Privacy › Export, step 10).
  Map<String, Object> export();
}

/// The log in the phone's key-value store (S6-2 pattern): one versioned
/// JSON list.
///
/// Nothing is ever dropped: entries this version can't read (a newer app's
/// events) are kept as they are, and a value that isn't a JSON list is
/// moved to [kBroken] before a new list starts.
///
/// **Migration (step 10):** the database reads [export] and calls [clear],
/// like `OnboardingStore`; the database step adds the migration test.
/// **Size:** a mission adds about 10 events (≈ 2 KB), so a year of daily
/// use is a few MB, more than a key-value store is meant for: the step 10
/// database replaces it.
class LocalActivityRepository implements ActivityRepository {
  new(this._kv) {
    _load();
  }

  final KeyValueStore _kv;
  final _raw = <Object?>[];
  final _events = <ActivityEvent>[];
  final _changes = StreamController<List<ActivityEvent>>.broadcast();

  static const schemaVersion = 1;
  static const kVersion = 'learn.activity.version';
  static const kEvents = 'learn.activity';

  /// Where an unreadable value is kept (never deleted); a later one goes
  /// to `kBroken.2`, `.3`…
  static const kBroken = 'learn.activity.broken';
  static final _log = Log('learn');

  void _load() {
    final text = _kv.getString(kEvents);
    if (text == null) return;
    try {
      final list = jsonDecode(text);
      if (list is! List<Object?>) throw const FormatException('not a list');
      _raw.addAll(list);
    } on FormatException catch (e) {
      _log.warn('load_failed', {'error': e.message});
      var key = kBroken;
      for (var n = 2; _kv.getString(key) != null; n++) {
        key = '$kBroken.$n';
      }
      unawaited(_kv.setString(key, text));
      return;
    }
    var unread = 0;
    for (final j in _raw) {
      final e = ActivityEvent.tryParse(j);
      if (e == null) {
        unread++;
      } else {
        _events.add(e);
      }
    }
    if (unread > 0) _log.info('unread_events', {'count': unread});
  }

  @override
  List<ActivityEvent> get events => List.unmodifiable(_events);

  @override
  Stream<List<ActivityEvent>> get changes => _changes.stream;

  @override
  Future<void> append(ActivityEvent event) async {
    _raw.add(event.toJson());
    _events.add(event);
    _changes.add(events);
    await _kv.setInt(kVersion, schemaVersion);
    await _kv.setString(kEvents, jsonEncode(_raw));
  }

  @override
  Map<String, Object> export() => {
    if (_kv.getInt(kVersion) case final int v) kVersion: v,
    if (_kv.getString(kEvents) case final String v) kEvents: v,
    for (final k in _brokenKeys) k: _kv.getString(k)!,
  };

  Iterable<String> get _brokenKeys =>
      _kv.keys.where((k) => k == kBroken || k.startsWith('$kBroken.'));

  /// Removes every value (only after a successful migration).
  Future<void> clear() async {
    _raw.clear();
    _events.clear();
    _changes.add(events);
    await _kv.remove(kVersion);
    await _kv.remove(kEvents);
    for (final k in _brokenKeys.toList()) {
      await _kv.remove(k);
    }
  }

  Future<void> dispose() => _changes.close();
}
