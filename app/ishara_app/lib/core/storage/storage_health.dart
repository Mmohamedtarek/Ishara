import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/logging/log.dart';

/// Whether this session's changes are being stored (step 10a review). The
/// first write that fails (a full disk, mostly) raises [notSaving] once;
/// the app shows the "out of storage" notice then (`StorageNotice`).
class StorageHealth {
  new({this.degraded = false});

  /// Nothing can be stored this session (`openStorage`'s degraded mode):
  /// the first write raises [notSaving] even though it "works" in memory.
  final bool degraded;

  final ValueNotifier<bool> _notSaving = ValueNotifier(false);

  ValueListenable<bool> get notSaving => _notSaving;

  static final _log = Log('storage');

  /// A write failed (or, [degraded], was made at all).
  void writeFailed(Object? error) {
    if (_notSaving.value) return;
    _log.warn('write_failed', {
      'error': error?.runtimeType.toString() ?? 'degraded',
    });
    _notSaving.value = true;
  }

  void dispose() => _notSaving.dispose();
}

/// Runs a repository's database [write]. A failure was already reported by
/// [WriteWatch] (the notice); here it never reaches the caller: the change
/// stays in memory for the session, and nothing that depends on it (SOS
/// above all: speaking, the sheet, SMS, calls) stops.
Future<void> storeOrKeepGoing(Future<void> Function() write) async {
  try {
    await write();
  } on Object catch (e) {
    StorageHealth._log.warn('write_skipped', {
      'error': e.runtimeType.toString(),
    });
  }
}

/// Reports every database write that fails (the statement, or its
/// transaction's commit) to [health], then lets the error through.
class WriteWatch extends QueryInterceptor {
  new(this.health);

  final StorageHealth health;

  Future<T> _write<T>(Future<T> Function() run) async {
    try {
      final r = await run();
      if (health.degraded) health.writeFailed(null);
      return r;
    } on Object catch (e) {
      health.writeFailed(e);
      rethrow;
    }
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _write(() => executor.runInsert(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _write(() => executor.runUpdate(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _write(() => executor.runDelete(statement, args));

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _write(() => executor.runBatched(statements));

  @override
  Future<void> commitTransaction(TransactionExecutor inner) =>
      _write(inner.send);
}
