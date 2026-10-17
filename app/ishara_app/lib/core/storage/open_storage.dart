import 'dart:io';

import 'package:drift/native.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/kv_migration.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/core/storage/local_data.dart';
import 'package:path_provider/path_provider.dart';

/// The opened storage `main` hands to the providers.
typedef OpenedStorage = ({KeyValueStore kv, AppDatabase db, LocalData data});

/// The database file, in the app's private support folder.
const databaseFileName = 'ishara.sqlite';

/// Opens the database, migrates the old key-value store into it (once,
/// [KvMigration]) and reads everything the repositories hold.
///
/// If the database can't open, the app still runs: the lists come from the
/// old store, read only (nothing is removed from it), and named values keep
/// using it; the next start tries again.
Future<OpenedStorage> openStorage() async {
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
  try {
    final dir = await getApplicationSupportDirectory();
    db = AppDatabase(
      NativeDatabase.createInBackground(
        File('${dir.path}${Platform.pathSeparator}$databaseFileName'),
      ),
    );
    await db.customSelect('SELECT 1').get(); // opens it, creates the tables
    await KvMigration(old, db).run();
    return (
      kv: await DriftKeyValueStore.load(db),
      db: db,
      data: await LocalData.load(db),
    );
  } on Object catch (e, st) {
    log.failure(
      'database_open',
      UnexpectedFailure('database', cause: e, stackTrace: st),
    );
    await db?.close();
    return (
      kv: old,
      db: AppDatabase(NativeDatabase.memory()),
      data: LocalData.fromLegacy(LegacyData.read(old)),
    );
  }
}
