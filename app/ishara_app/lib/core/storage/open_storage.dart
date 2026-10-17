import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:drift/native.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/kv_migration.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/core/storage/local_data.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';

/// The opened storage `main` hands to the providers. `degraded`: nothing
/// is stored this session (see [openStorage]); `health` raises the "out of
/// storage" notice at the first write that fails.
typedef OpenedStorage = ({
  KeyValueStore kv,
  AppDatabase db,
  LocalData data,
  bool degraded,
  StorageHealth health,
});

/// The database file, in the app's private support folder.
const databaseFileName = 'ishara.sqlite';

/// Opens the database, migrates the old key-value store into it (once,
/// [KvMigration]) and reads everything the repositories hold.
///
/// - A database file that can't be opened or fails SQLite's check is moved
///   aside (`ishara.sqlite.damaged-<time>`, never deleted) and a new one is
///   made; the old store's values still there move into it.
/// - An old-store part that couldn't move this time is shown from the old
///   store this session ([LocalData.withLegacy]); the next start moves it.
/// - Only if no database can be written at all (a full disk, a folder that
///   can't be written) does the app run **degraded**: the data from the old
///   store, in memory, and nothing stored (not even into the old store,
///   whose values a later start would read as older than the database).
///
/// [onStep]: the migration's test hook.
Future<OpenedStorage> openStorage({
  @visibleForTesting Future<void> Function(String point)? onStep,
}) async {
  final log = Log('storage');
  KeyValueStore old;
  try {
    old = await SharedPrefsKeyValueStore.open();
  } on Object catch (e, st) {
    log.failure(
      'store_open',
      UnexpectedFailure('key-value store', cause: e, stackTrace: st),
    );
    old = MemoryKeyValueStore();
  }
  AppDatabase? db;
  final health = StorageHealth();
  try {
    final dir = (await getApplicationSupportDirectory()).path;
    final path = '$dir${Platform.pathSeparator}$databaseFileName';
    db = await _open(path, log, health);
    if (db == null && FileSystemEntity.typeSync(path) != .notFound) {
      _moveAside(path, log);
      db = await _open(path, log, health);
    }
    if (db == null) throw const FileSystemException('no database');
    final migration = KvMigration(old, db, onStep: onStep);
    await migration.run();
    final kv = await DriftKeyValueStore.load(db);
    var data = await LocalData.load(db);
    if (migration.failed.isNotEmpty) {
      final left = LegacyData.read(old);
      data = data.withLegacy(left, migration.failed);
      if (migration.failed.contains(LegacyPart.prefs)) {
        kv.showUnstored(left.prefs);
      }
    }
    return (kv: kv, db: db, data: data, degraded: false, health: health);
  } on Object catch (e, st) {
    log.failure(
      'storage_degraded',
      UnexpectedFailure('database', cause: e, stackTrace: st),
    );
    await db?.close();
    health.dispose();
    final left = LegacyData.read(old);
    final none = StorageHealth(degraded: true);
    return (
      kv: MemoryKeyValueStore({
        for (final k in old.keys)
          if (old.read(k) case final Object v) k: v,
      }),
      db: AppDatabase(NativeDatabase.memory().interceptWith(WriteWatch(none))),
      data: LocalData.fromLegacy(left),
      degraded: true,
      health: none,
    );
  }
}

/// The database at [path], opened and checked; null when it can't be used.
Future<AppDatabase?> _open(String path, Log log, StorageHealth health) async {
  final db = AppDatabase(
    NativeDatabase.createInBackground(File(path))
        .interceptWith(WriteWatch(health)),
  );
  try {
    final check = await db.customSelect('PRAGMA quick_check').get();
    if (check.length == 1 && check.single.data.values.single == 'ok') {
      return db;
    }
    log.warn('database_check_failed', {'rows': check.length});
  } on Object catch (e) {
    log.warn('database_open_failed', {'error': e.runtimeType.toString()});
  }
  await db.close();
  return null;
}

/// Keeps a damaged database (and its journal) under a new name.
void _moveAside(String path, Log log) {
  final t = clock.now().toUtc().toIso8601String().replaceAll(':', '-');
  for (final suffix in ['', '-journal', '-wal', '-shm']) {
    final from = '$path$suffix';
    final type = FileSystemEntity.typeSync(from);
    if (type == .notFound) continue;
    final to = '$path.damaged-$t$suffix';
    if (type == .directory) {
      Directory(from).renameSync(to);
    } else {
      File(from).renameSync(to);
    }
  }
  log.warn('database_moved_aside', {'at': t});
}
