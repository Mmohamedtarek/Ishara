import 'package:drift/drift.dart';

part 'app_database.g.dart';

// The phone's database (Phase 0: drift is the local source of truth). The
// screens read through the repositories, never these tables.
//
// Times: `…Us` columns are microseconds since the epoch, UTC. Message times
// stay in the text form the Talk feed always stored (local time).
//
// Sync fields (Phase 0 Firestore model) are here from version 1, so the
// sync (step 10b) needs no migration: stable ids, `updatedAtUs`, the
// phrases' `deleted` tombstones and the [Outbox].

/// Named values (S6-2 keys, unchanged): the onboarding answers, the
/// settings, and local flags. `value` is the JSON form of the stored value.
/// `updatedAtUs` is per value; the settings document's time for the sync is
/// the newest of its values.
@DataClassName('PrefRow')
class Prefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAtUs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The Talk feed (Q-B4: never synced). Lifts the old 500-message limit.
@TableIndex(name: 'messages_at', columns: {#atUs})
@DataClassName('MessageRow')
class Messages extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// Stable id of the message.
  TextColumn get id => text().unique()();

  /// The conversation id (S9-4); null for messages stored before step 9.
  TextColumn get conversation => text().nullable()();

  /// `me` or `them`.
  TextColumn get side => text()();
  TextColumn get content => text()();

  /// When it was said, exactly as the feed stored it (ISO 8601, local).
  TextColumn get at => text()();

  /// The same instant, for ordering.
  IntColumn get atUs => integer()();
}

/// Starred sentences (`users/{uid}/phrases/{phraseId}`): last writer wins
/// by `updatedAtUs` (id as tie-break); unstarring keeps a tombstone.
@DataClassName('PhraseRow')
class Phrases extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()();

  /// `en` or `ar`.
  TextColumn get lang => text()();
  IntColumn get createdAtUs => integer()();
  IntColumn get updatedAtUs => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Learn's append-only log (`users/{uid}/activity/{eventId}`). Each entry
/// is kept exactly as written (`json`), also when this version can't read
/// it (a newer app's event).
@DataClassName('ActivityEntryRow')
class ActivityEntries extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// The event id (`unread:…` for an entry with none).
  TextColumn get id => text().unique()();
  TextColumn get json => text()();
}

/// Emergency contacts (step 9): on this phone only, never synced.
@DataClassName('ContactRow')
class Contacts extends Table {
  IntColumn get position => integer()();
  TextColumn get name => text()();

  /// E.164.
  TextColumn get phone => text()();

  @override
  Set<Column<Object>> get primaryKey => {position};
}

/// Values the app couldn't use, kept aside instead of deleted (like
/// `learn.activity.broken` before): a damaged old value, an entry that
/// couldn't be read, an unknown old key.
@DataClassName('KeptRow')
class KeptValues extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Where it came from (the old key, `talk.messages[3]` for one entry).
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get reason => text()();
  IntColumn get keptAtUs => integer()();
}

/// The app's own state, not user data: migration markers, the sync's
/// cursors and flags (step 10b: the account deletion's "pending" flag).
@DataClassName('MetaRow')
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Documents to push (step 10b): one row per document, the newest local
/// state is read from its table when it is sent. Retried with backoff.
@TableIndex(name: 'outbox_next', columns: {#nextAttemptUs})
@DataClassName('OutboxRow')
class Outbox extends Table {
  /// `settings`, `phrases` or `activity`.
  TextColumn get collection => text()();
  TextColumn get docId => text()();
  IntColumn get queuedAtUs => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptUs => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {collection, docId};
}

@DriftDatabase(
  tables: [
    Prefs,
    Messages,
    Phrases,
    ActivityEntries,
    Contacts,
    KeptValues,
    Meta,
    Outbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  new(super.e);

  /// Every change to the tables raises this and adds a step to
  /// [migration] (tested from the schemas in `drift_schemas/`).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());
}
