import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/sync/outbox.dart';
import 'package:ishara_app/core/sync/remote_store.dart';
import 'package:ishara_app/core/sync/settings_doc.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';

/// What Settings shows under the account (S10-8).
enum SyncState {
  /// Guest, signed out, or the email isn't verified yet (Q-B3).
  off,

  /// Changes are waiting for the connection (or the first download).
  pending,

  /// Everything is up.
  synced,

  /// The account refused some changes three times (they stay on the phone,
  /// logged: usually a rules bug); tried again at the next start.
  parked,
}

/// What sign-out needs from the sync (S10-6); [SyncEngine] does it.
abstract interface class SyncControl {
  /// Pushes what is waiting; true when nothing is left unsent.
  Future<bool> flush({Duration limit});

  /// The account's synced data leaves the phone.
  Future<void> clearSyncedData();
}

/// Moves the phone's settings, Learn log and starred phrases to and from
/// the account (Phase 0; Q-B3, Q-B4). Only while signed in with a verified
/// email. Never conversations, emergency contacts, the paired glove or
/// anything from SOS.
///
/// - Every local change is in the outbox (`enqueue`, in the change's own
///   transaction); it is pushed when online, retried with backoff.
/// - On sign-in (and at start) it pulls everything, then listens while the
///   app runs.
/// - Conflicts: settings and phrases, last writer wins per document by
///   `updatedAt`; phrases keep tombstones; activity is append-only, so two
///   offline phones merge with no loss.
/// - The first sign-in on this phone queues the phone's (guest) data once;
///   the account's settings win if the account has any (S10-5).
class SyncEngine implements SyncControl {
  new({
    required this.db,
    required this.remote,
    required this.auth,
    required this.phrases,
    required this.activity,
    required this.prefs,
    required this.onSettingsApplied,
    this.debounce = const Duration(milliseconds: 800),
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final RemoteStore remote;
  final AuthRepository auth;
  final LocalSavedPhrasesRepository? phrases;
  final LocalActivityRepository? activity;
  final DriftKeyValueStore? prefs;

  /// The account's settings were stored on the phone: the screens reload
  /// them.
  final VoidCallback onSettingsApplied;
  final Duration debounce;
  final Random _random;

  static final _log = Log('sync');

  /// Meta keys: whose data the synced tables hold (null = guest), and the
  /// account whose first download is still to come.
  static const kOwner = 'sync.owner';
  static const kFirstPull = 'sync.firstPull';

  /// `AccountDeletion.kPending`: while a deletion is pending nothing syncs
  /// (a push could bring deleted documents back).
  static const kDeletionPending = 'account.deletion';

  /// A write refused this many times is parked.
  static const parkAfter = 3;

  /// `nextAttemptUs` of a parked row (never due until the next start).
  static const int parkedUs = 1 << 62;

  final ValueNotifier<SyncState> _state = ValueNotifier(SyncState.off);
  ValueListenable<SyncState> get state => _state;

  StreamSubscription<AuthUser?>? _authSub;
  StreamSubscription<List<OutboxRow>>? _outboxSub;
  final _live = <StreamSubscription<Object?>>[];

  /// The next push (retry time); [_pullTimer] is the next pull after a
  /// failure. Two timers: a push ending must never cancel a pull retry.
  Timer? _timer;
  Timer? _pullTimer;
  Timer? _debounceTimer;
  String? _active;
  AuthUser? _user;
  bool _pulled = false;
  int _pullTries = 0;
  int _waiting = 0;
  int _parked = 0;
  bool _pushing = false;
  bool _pushAgain = false;
  late Completer<void> _pushRun;
  bool _suspended = false;

  /// Pushes in a row that ended in an error other than the server's answer
  /// (a database error, say): they back off like network failures.
  int _pushErrors = 0;

  /// After a network failure nothing is pushed before this time.
  int _holdUntilUs = 0;
  Future<void> _chain = Future.value();
  bool _disposed = false;

  String _base(String uid) => 'users/$uid';

  /// [path] for the log: the account id masked (logcat keeps release
  /// builds' structured fields; nothing needs to know whose it was).
  static String logPath(String path) =>
      path.replaceFirst(RegExp('^users/[^/]+'), 'users/{uid}');

  /// Starts following the signed-in user and the outbox. Writes parked by
  /// an earlier run are tried again once (an update may have fixed them).
  void start() {
    _authSub = auth.userChanges.listen((u) => _serial(() => _follow(u)));
    unawaited(
      _serial(() async {
        await (db.update(db.outbox)
              ..where((t) => t.nextAttemptUs.equals(parkedUs)))
            .write(const OutboxCompanion(nextAttemptUs: Value(0)));
        await _follow(auth.currentUser);
      }),
    );
    _outboxSub = db.select(db.outbox).watch().listen((rows) {
      _waiting = rows.length;
      _parked = rows.where((r) => r.nextAttemptUs == parkedUs).length;
      _refreshState();
      if (_waiting > _parked) _soon();
    });
  }

  /// Account deletion (Q-B1): nothing syncs until [resume]. A push already
  /// under way is waited for, so no write lands after the deletion's.
  Future<void> suspend() async {
    _suspended = true;
    await _serial(_stop);
    if (_pushing) await _pushRun.future;
  }

  /// The deletion ended (done, failed, or nothing to do): the sync follows
  /// the signed-in user again. A deletion still pending keeps it off
  /// ([_follow] checks the flag).
  Future<void> resume() => _serial(() async {
    _suspended = false;
    await _follow(auth.currentUser);
  });

  /// Queues [job] behind the engine's own jobs (tests hold the queue).
  @visibleForTesting
  Future<void> runSerial(Future<void> Function() job) => _serial(job);

  Future<void> _serial(Future<void> Function() job) => _chain = _chain
      .then((_) => _disposed ? null : job())
      .catchError(
        (Object e) => _log.warn('job_failed', {'error': '${e.runtimeType}'}),
      );

  void _refreshState() {
    if (_disposed) return;
    _state.value = _active == null
        ? SyncState.off
        : _parked > 0
        ? SyncState.parked
        : (!_pulled || _waiting > 0 ? SyncState.pending : SyncState.synced);
  }

  Future<void> _follow(AuthUser? u) async {
    final uid = u != null && u.emailVerified && !_suspended ? u.id : null;
    _user = u;
    if (uid == _active) return;
    await _stop();
    if (uid != null && await _meta(kDeletionPending) == null) {
      await _begin(u!);
    }
  }

  Future<String?> _meta(String key) async => (await (db.select(
    db.meta,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> _setMeta(String key, String value) => db
      .into(db.meta)
      .insertOnConflictUpdate(MetaCompanion.insert(key: key, value: value));

  Future<void> _dropMeta(String key) =>
      (db.delete(db.meta)..where((t) => t.key.equals(key))).go();

  Future<void> _begin(AuthUser user) async {
    final owner = await _meta(kOwner);
    if (owner != user.id) {
      // another account's data must never go up into this one
      if (owner != null) await _clearSynced();
      // the phone's data joins the account, once, through the outbox
      await db.transaction(() async {
        for (final p in phrases?.all ?? const <SavedPhrase>[]) {
          // too long for the account: stays on this phone
          if (Synced.phraseFits(p.text)) {
            await enqueue(db, Synced.phrases, p.id);
          }
        }
        for (final e in activity?.events ?? const <ActivityEvent>[]) {
          await enqueue(db, Synced.activity, e.id);
        }
        if (prefs?.settingsUpdatedAt != null) {
          await enqueue(db, Synced.settings, Synced.settingsDoc);
        }
        await _setMeta(kOwner, user.id);
        await _setMeta(kFirstPull, user.id);
      });
      _log.info('joined', {
        'phrases': phrases?.all.length ?? 0,
        'events': activity?.events.length ?? 0,
      });
    }
    _active = user.id;
    _pulled = false;
    _pullTries = 0;
    _refreshState();
    await _pullAndListen();
  }

  Future<void> _stop() async {
    _active = null;
    _pulled = false;
    _timer?.cancel();
    _pullTimer?.cancel();
    _debounceTimer?.cancel();
    await _stopListening();
    _refreshState();
  }

  Future<void> _stopListening() async {
    final live = [..._live];
    _live.clear();
    for (final s in live) {
      await s.cancel();
    }
  }

  /// The first download, then the live listeners and the push. Offline it
  /// tries again with backoff.
  Future<void> _pullAndListen() async {
    final uid = _active;
    if (uid == null) return;
    try {
      await _pull(uid);
    } on RemoteFailure catch (e) {
      _pullTries++;
      _log.info('pull_failed', {'problem': e.problem.name});
      _pullTimer?.cancel();
      _pullTimer = Timer(
        _backoff(_pullTries),
        () => unawaited(_serial(_pullAndListen)),
      );
      return;
    }
    if (_active != uid) return;
    _pulled = true;
    _pullTries = 0;
    _refreshState();
    _listen(uid);
    _soon();
  }

  Future<void> _pull(String uid) async {
    final base = _base(uid);
    // the profile (users/{uid}), once
    if (await remote.get(base) == null) {
      final now = clock.now().toUtc();
      final name = _user?.name ?? '';
      try {
        await remote.set(base, {
          // the sign-up field allows 100; this is the last guard (rules)
          'displayName': name.length > 100 ? name.substring(0, 100) : name,
          'createdAt': now,
          'updatedAt': now,
          'schemaVersion': 1,
        });
      } on RemoteFailure catch (e) {
        // a refused profile never stops the sync (it is only the name)
        if (e.problem == RemoteProblem.network) rethrow;
        _log.warn('profile_refused', {
          'path': logPath(base),
          'code': '${e.cause ?? e.problem.name}',
        });
      }
    }
    final first = await _meta(kFirstPull) == uid;
    final doc = await remote.get('$base/settings/${Synced.settingsDoc}');
    if (doc != null) await _applySettings(doc, accountWins: first);
    await phrases?.applyRemote([
      for (final d in await remote.list('$base/phrases')) ?_phrase(d),
    ]);
    await activity?.applyRemote([
      for (final d in await remote.list('$base/activity')) ?_event(d),
    ]);
    if (first) await _dropMeta(kFirstPull);
  }

  void _listen(String uid) {
    final base = _base(uid);
    // a listener that fails ends: all of them start again after a pause,
    // with a fresh download (nothing missed meanwhile)
    void onError(Object e) {
      _log.info('listen_error', {'error': '${e.runtimeType}'});
      unawaited(
        _serial(() async {
          if (_active != uid || !_pulled) return;
          await _stopListening();
          _pulled = false;
          _pullTries++;
          _refreshState();
          _pullTimer?.cancel();
          _pullTimer = Timer(
            _backoff(_pullTries),
            () => unawaited(_serial(_pullAndListen)),
          );
        }),
      );
    }

    _live
      ..add(
        remote
            .watch('$base/phrases')
            .listen(
              (docs) => unawaited(
                _serial(() async {
                  // signed out (or another account) meanwhile: not ours
                  if (_active != uid) return;
                  await phrases?.applyRemote([
                    for (final d in docs) ?_phrase(d),
                  ]);
                }),
              ),
              onError: onError,
            ),
      )
      ..add(
        remote
            .watch('$base/activity')
            .listen(
              (docs) => unawaited(
                _serial(() async {
                  if (_active != uid) return;
                  await activity?.applyRemote([
                    for (final d in docs) ?_event(d),
                  ]);
                }),
              ),
              onError: onError,
            ),
      )
      ..add(
        remote
            .watchDoc('$base/settings/${Synced.settingsDoc}')
            .listen(
              (doc) => unawaited(
                _serial(() async {
                  if (doc != null && _active == uid) {
                    await _applySettings(doc, accountWins: false);
                  }
                }),
              ),
              onError: onError,
            ),
      );
  }

  /// The account's settings document: stored when newer than the phone's
  /// (or always, on the first sign-in: S10-5); the phone's queued settings
  /// are then dropped.
  Future<void> _applySettings(
    Map<String, Object?> doc, {
    required bool accountWins,
  }) async {
    final p = prefs;
    final at = doc['updatedAt'];
    if (p == null || at is! DateTime) return;
    final local = p.settingsUpdatedAt;
    if (!accountWins && local != null && !at.isAfter(local)) return;
    // the phone's queued settings are replaced, unless changed again while
    // the account's are stored (then they go up after all)
    final queued =
        await (db.select(db.outbox)..where(
              (t) =>
                  t.collection.equals(Synced.settings) &
                  t.docId.equals(Synced.settingsDoc),
            ))
            .getSingleOrNull();
    await p.applyRemote(SettingsDoc.fromRemote(doc), at);
    if (queued != null) {
      await (db.delete(db.outbox)..where(
            (t) =>
                t.collection.equals(Synced.settings) &
                t.docId.equals(Synced.settingsDoc) &
                t.queuedAtUs.equals(queued.queuedAtUs),
          ))
          .go();
    }
    onSettingsApplied();
  }

  static SavedPhrase? _phrase(RemoteDoc d) {
    final created = d.data['createdAt'];
    final updated = d.data['updatedAt'];
    return SavedPhrase.fromJson({
      ...d.data,
      'id': d.id,
      if (created is DateTime) 'createdAt': created.toIso8601String(),
      if (updated is DateTime) 'updatedAt': updated.toIso8601String(),
    });
  }

  static ActivityEvent? _event(RemoteDoc d) {
    final at = d.data['at'];
    return ActivityEvent.tryParse(<String, Object?>{
      ...d.data,
      'id': d.id,
      if (at is DateTime) 'at': at.toIso8601String(),
    });
  }

  /// The document to send for an outbox row; null = nothing to send (gone,
  /// or never synced, like a Learn entry this version can't read).
  Map<String, Object?>? _docFor(String collection, String id) {
    switch (collection) {
      case Synced.phrases:
        final p = phrases?.byId(id);
        // gone, or too long for the account (a row queued before this
        // check): nothing to send, the row goes
        if (p == null || !Synced.phraseFits(p.text)) return null;
        return {
          'text': p.text,
          'lang': p.lang,
          'createdAt': p.createdAt.toUtc(),
          // a clock set back must not make it look changed before created
          'updatedAt':
              (p.updatedAt.isBefore(p.createdAt) ? p.createdAt : p.updatedAt)
                  .toUtc(),
          'deleted': p.deleted,
        };
      case Synced.activity:
        final raw = activity?.rawById[id];
        final e = ActivityEvent.tryParse(raw);
        if (e == null) return null;
        return {...e.toJson(), 'at': e.at.toUtc()}..remove('id');
      case Synced.settings:
        final p = prefs;
        final at = p?.settingsUpdatedAt;
        if (p == null || at == null) return null;
        return SettingsDoc.toRemote(p.read, at);
    }
    return null;
  }

  static Duration _backoffBase(int attempt) =>
      Duration(seconds: min(600, 2 << min(attempt - 1, 9)));

  Duration _backoff(int attempt) {
    final base = _backoffBase(attempt);
    // up to a fifth more, so phones don't retry in step
    return base +
        Duration(milliseconds: _random.nextInt(base.inMilliseconds ~/ 5 + 1));
  }

  void _soon() {
    if (_active == null || !_pulled) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(push()));
  }

  /// Sends what is due in the outbox. Stops at the first network failure
  /// (the rest would fail too) and comes back at the next retry time.
  Future<void> push() async {
    final uid = _active;
    if (uid == null || !_pulled || _disposed) return;
    if (_pushing) {
      // the running push goes round again; wait for it (flush counts on it)
      _pushAgain = true;
      return await _pushRun.future;
    }
    _pushing = true;
    final run = _pushRun = Completer<void>();
    try {
      do {
        _pushAgain = false;
        await _pushDue(uid);
      } while (_pushAgain && _active == uid);
      _pushErrors = 0;
    } on Object catch (e) {
      // not the server's answer (those are handled per row): back off and
      // try again later, never an unhandled error from a timer
      _pushErrors++;
      _holdUntilUs = clock
          .now()
          .add(_backoff(_pushErrors))
          .microsecondsSinceEpoch;
      _log.warn('push_failed', {
        'error': '${e.runtimeType}',
        'attempts': _pushErrors,
      });
    } finally {
      _pushing = false;
      run.complete();
    }
    await _scheduleNext();
  }

  Future<void> _pushDue(String uid) async {
    final now = clock.now().microsecondsSinceEpoch;
    if (now < _holdUntilUs) return; // offline: wait for the retry time
    final rows =
        await (db.select(db.outbox)
              ..where((t) => t.nextAttemptUs.isSmallerOrEqualValue(now))
              ..orderBy([(t) => OrderingTerm(expression: t.queuedAtUs)]))
            .get();
    for (final row in rows) {
      if (_active != uid) return;
      final doc = _docFor(row.collection, row.docId);
      final path = row.collection == Synced.settings
          ? '${_base(uid)}/settings/${Synced.settingsDoc}'
          : '${_base(uid)}/${row.collection}/${row.docId}';
      try {
        if (doc != null) await remote.set(path, doc);
      } on RemoteFailure catch (e) {
        // an event already up (its first answer was lost) can't be written
        // again: append-only
        final already =
            row.collection == Synced.activity &&
            e.problem == RemoteProblem.denied &&
            await _exists(path);
        if (!already) {
          final next = await _retryLater(row, e, path);
          if (e.problem == RemoteProblem.network) {
            _holdUntilUs = next;
            return;
          }
          continue;
        }
      }
      // done, unless it changed again meanwhile (then it goes once more)
      await (db.delete(db.outbox)..where(
            (t) =>
                t.collection.equals(row.collection) &
                t.docId.equals(row.docId) &
                t.queuedAtUs.equals(row.queuedAtUs),
          ))
          .go();
    }
  }

  Future<bool> _exists(String path) async {
    try {
      return await remote.get(path) != null;
    } on RemoteFailure {
      return false;
    }
  }

  /// Backs the row off (or parks it after [parkAfter] refusals); returns
  /// its next try time.
  Future<int> _retryLater(OutboxRow row, RemoteFailure e, String path) async {
    final problem = e.problem;
    final attempts = row.attempts + 1;
    final park = problem == RemoteProblem.denied && attempts >= parkAfter;
    final next = park
        ? parkedUs
        : clock.now().add(_backoff(attempts)).microsecondsSinceEpoch;
    await (db.update(db.outbox)..where(
          (t) =>
              t.collection.equals(row.collection) &
              t.docId.equals(row.docId) &
              t.queuedAtUs.equals(row.queuedAtUs),
        ))
        .write(
          OutboxCompanion(
            attempts: Value(attempts),
            nextAttemptUs: Value(next),
            lastError: Value('${e.cause ?? problem.name}'),
          ),
        );
    if (park) {
      // kept on the phone, shown in Settings; a refusal is usually a bug in
      // the rules or in what the app sends (ids and codes, never content)
      _log.warn('write_parked', {
        'path': logPath(path),
        'code': '${e.cause ?? problem.name}',
        'attempts': attempts,
      });
    } else {
      _log.info('push_retry', {
        'collection': row.collection,
        'attempts': attempts,
        'problem': problem.name,
      });
    }
    return next;
  }

  Future<void> _scheduleNext() async {
    if (_active == null || _disposed) return;
    final next =
        await (db.select(db.outbox)
              ..where((t) => t.nextAttemptUs.isSmallerThanValue(parkedUs))
              ..orderBy([(t) => OrderingTerm(expression: t.nextAttemptUs)])
              ..limit(1))
            .getSingleOrNull();
    if (next == null) return;
    final wait = Duration(
      microseconds: max(
        0,
        max(next.nextAttemptUs, _holdUntilUs) -
            clock.now().microsecondsSinceEpoch,
      ),
    );
    _timer?.cancel();
    _timer = Timer(wait, () => unawaited(push()));
  }

  /// Sign-out: pushes what it can within [limit]; true when nothing is
  /// left unsent (S10-6).
  @override
  Future<bool> flush({Duration limit = const Duration(seconds: 8)}) async {
    if (_active == null) return await _left() == 0;
    // due now, whatever the backoff said (parked writes stay parked: they
    // count as not sent)
    _holdUntilUs = 0;
    await (db.update(db.outbox)
          ..where((t) => t.nextAttemptUs.isSmallerThanValue(parkedUs)))
        .write(const OutboxCompanion(nextAttemptUs: Value(0)));
    try {
      await push().timeout(limit);
    } on TimeoutException {
      // reported by what's left
    }
    return await _left() == 0;
  }

  Future<int> _left() {
    final count = db.outbox.collection.count();
    return (db.selectOnly(
      db.outbox,
    )..addColumns([count])).map((r) => r.read(count) ?? 0).getSingle();
  }

  /// Signed out (S10-6) or another account's data found: the synced data
  /// leaves the phone (phrases, Learn log, the outbox); settings, Talk,
  /// emergency contacts and the glove stay.
  @override
  Future<void> clearSyncedData() => _serial(() async {
    // stopped first: no listener job queued after this one applies the
    // account's data again
    await _stop();
    await _clearSynced();
  });

  Future<void> _clearSynced() async {
    await phrases?.clearAll();
    await activity?.clearAll();
    await db.delete(db.outbox).go();
    await _dropMeta(kOwner);
    await _dropMeta(kFirstPull);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _authSub?.cancel();
    await _outboxSub?.cancel();
    await _stop();
    _state.dispose();
  }
}
