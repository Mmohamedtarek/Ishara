import 'package:drift/native.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/core/storage/local_data.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_providers.g.dart';

/// The phone's database. `main` overrides it with the opened file; tests
/// (and the fallback when the file can't open) use one in memory.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase(NativeDatabase.memory());
  ref.onDispose(db.close);
  return db;
}

/// The lists read at start. `main` overrides it with [LocalData.load];
/// without that (tests, the fallback) they come from the old key-value
/// store through the migration's own reader, and nothing is removed.
@Riverpod(keepAlive: true)
LocalData localData(Ref ref) =>
    LocalData.fromLegacy(LegacyData.read(ref.watch(keyValueStoreProvider)));
