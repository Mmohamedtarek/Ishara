import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/storage/open_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  new(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// The phone's old store as `shared_preferences` keeps it: every key with
/// the app's `ishara.` prefix.
Map<String, Object> _phone(String v) => {
  for (final MapEntry(:key, :value) in (jsonDecode(
    File('test/storage/legacy_snapshots/$v.json').readAsStringSync(),
  ) as Map<String, Object?>).entries)
    'ishara.$key': value!,
  // another app library's key is never touched
  'flutter.other': 'not ours',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late InMemorySharedPreferencesAsync prefs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ishara_open_');
    PathProviderPlatform.instance = _Paths(dir.path);
    prefs = InMemorySharedPreferencesAsync.withData(_phone('v9'));
    SharedPreferencesAsyncPlatform.instance = prefs;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('the first start after the update moves the step 9 store into the '
      'database file; the next start reads it back', () async {
    final first = await openStorage();
    expect(File('${dir.path}/$databaseFileName').existsSync(), isTrue);
    expect(first.kv.getString('settings.theme'), 'dark');
    expect(first.data.messages, hasLength(4));
    expect(first.data.phrases, hasLength(2));
    expect(first.data.activity, hasLength(2));
    expect(first.data.contacts, hasLength(2));
    // the old store keeps only what isn't ours
    final left = await prefs.getKeys(
      const GetPreferencesParameters(filter: PreferencesFilters()),
      const SharedPreferencesOptions(),
    );
    expect(left, {'flutter.other'});
    await first.db.close();

    final second = await openStorage();
    expect(second.kv.getString('settings.theme'), 'dark');
    expect(second.kv.getInt('settings.signSpeed'), 15);
    expect(
      [for (final m in second.data.messages) m.message],
      [for (final m in first.data.messages) m.message],
    );
    expect(
      [for (final m in second.data.messages) m.id],
      [for (final m in first.data.messages) m.id],
    );
    await second.db.close();
  });

  test("the database can't open: the app runs on the old store and "
      'removes nothing', () async {
    // a folder where the file should be: SQLite can't open it
    Directory('${dir.path}/$databaseFileName').createSync();
    final s = await openStorage();
    expect(s.kv.getString('settings.theme'), 'dark');
    expect(s.data.messages, hasLength(4));
    final left = await prefs.getKeys(
      const GetPreferencesParameters(filter: PreferencesFilters()),
      const SharedPreferencesOptions(),
    );
    expect(left, contains('ishara.talk.messages'));
    await s.db.close();
  });
}
