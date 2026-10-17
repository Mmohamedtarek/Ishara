import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/storage_health.dart';

/// Every write fails as on a full disk (SQLite's SQLITE_FULL), reads work.
class FullDisk extends QueryInterceptor {
  static Never _full() => throw const FileSystemFullError();

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _full();

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _full();

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async => _full();

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) async => _full();
}

class FileSystemFullError implements Exception {
  const new();

  @override
  String toString() => 'database or disk is full';
}

/// A database in memory whose writes all fail, watched by [health].
AppDatabase fullDiskDb(StorageHealth health) => AppDatabase(
  NativeDatabase.memory()
      .interceptWith(FullDisk())
      .interceptWith(WriteWatch(health)),
);
