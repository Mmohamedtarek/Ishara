// drift's migration tests (step 10a): the schemas of every released
// version are dumped in drift_schemas/ (`dart run drift_dev
// make-migrations` after each change; it also writes the generated/ files
// and a test per new version). Version 1 is the first.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema version is dumped', () async {
    final db = AppDatabase((await verifier.schemaAt(1)).newConnection());
    expect(GeneratedHelper.versions.last, db.schemaVersion);
    await db.close();
  });

  test('a new database matches the dumped schema of its version', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });

  test('every step from each released version to the current one', () async {
    for (final from in GeneratedHelper.versions) {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
      await db.close();
    }
  });
}
