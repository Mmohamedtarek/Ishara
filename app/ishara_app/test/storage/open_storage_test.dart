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

  test('a damaged database file is moved aside (kept) and a new one is '
      'made from the old store', () async {
    final file = File('${dir.path}/$databaseFileName')
      ..writeAsStringSync('this is not a database');
    final s = await openStorage();
    expect(s.degraded, isFalse);
    expect(s.kv.getString('settings.theme'), 'dark');
    expect(s.data.messages, hasLength(4));
    final aside = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('$databaseFileName.damaged-'))
        .single;
    expect(aside.readAsStringSync(), 'this is not a database');
    expect(file.existsSync(), isTrue);
    await s.db.close();
  });

  test('a part that fails is shown from the old store this session, then '
      'moves at the next start', () async {
    final s = await openStorage(
      onStep: (p) async {
        if (p == 'copying:sos' || p == 'copying:prefs') {
          throw StateError('disk full');
        }
      },
    );
    expect(s.degraded, isFalse);
    expect(s.data.contacts.map((c) => c.phone), [
      '+201012345678',
      '+201123456789',
    ]);
    expect(s.kv.getString('settings.theme'), 'dark');
    expect(s.data.messages, hasLength(4)); // talk moved
    // a value set this session is stored and wins over the old one
    await s.kv.setString('settings.theme', 'light');
    await s.db.close();
    final next = await openStorage();
    expect(next.kv.getString('settings.theme'), 'light');
    expect(next.kv.getString('setup.spoken'), 'ar');
    expect(next.data.contacts, hasLength(2));
    expect(await _left(prefs), {'flutter.other'});
    await next.db.close();
  });

  test('no database can be written: degraded, the old store is shown and '
      'never written to', () async {
    // a folder where the file goes, inside a folder that can't be written
    Directory('${dir.path}/$databaseFileName').createSync();
    Process.runSync('chmod', ['a-w', dir.path]);
    addTearDown(() => Process.runSync('chmod', ['u+w', dir.path]));
    final s = await openStorage();
    expect(s.degraded, isTrue);
    expect(s.kv.getString('settings.theme'), 'dark');
    expect(s.data.messages, hasLength(4));
    await s.kv.setString('settings.theme', 'light');
    expect(await _left(prefs), contains('ishara.talk.messages'));
    final theme = await prefs.getString(
      'ishara.settings.theme',
      const SharedPreferencesOptions(),
    );
    expect(theme, 'dark');
    await s.db.close();
  });
}

Future<Set<String>> _left(InMemorySharedPreferencesAsync prefs) =>
    prefs.getKeys(
      const GetPreferencesParameters(filter: PreferencesFilters()),
      const SharedPreferencesOptions(),
    );
