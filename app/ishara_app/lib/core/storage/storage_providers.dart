import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/core/storage/local_data.dart';
import 'package:ishara_app/core/storage/storage_health.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_providers.g.dart';

/// Whether changes are being stored this session (`main` overrides it with
/// the one `openStorage` watches the database with).
@Riverpod(keepAlive: true)
StorageHealth storageHealth(Ref ref) {
  final health = StorageHealth();
  ref.onDispose(health.dispose);
  return health;
}

/// The phone's database. `main` overrides it with the opened file; tests
/// (and the fallback when the file can't open) use one in memory.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(
    NativeDatabase.memory().interceptWith(
      WriteWatch(ref.watch(storageHealthProvider)),
    ),
  );
  ref.onDispose(db.close);
  return db;
}

/// The lists read at start. `main` overrides it with [LocalData.load];
/// without that (tests, the fallback) they come from the old key-value
/// store through the migration's own reader, and nothing is removed.
@Riverpod(keepAlive: true)
LocalData localData(Ref ref) =>
    LocalData.fromLegacy(LegacyData.read(ref.watch(keyValueStoreProvider)));
