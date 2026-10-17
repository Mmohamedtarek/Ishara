import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Step 10a review: conversations and emergency contacts never leave the
/// phone, so no backup or device transfer may carry the app's data.
void main() {
  const domains = [
    'root',
    'file',
    'database',
    'sharedpref',
    'external',
    'device_root',
    'device_file',
    'device_database',
    'device_sharedpref',
  ];
  const res = 'android/app/src/main/res/xml';

  Set<String> excluded(String xml) => {
    for (final m in RegExp(
      r'<exclude domain="(\w+)" path="\." />',
    ).allMatches(xml))
      m.group(1)!,
  };

  test('Android: backup off, and the rules point at files that exclude '
      'everything', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final full = File('$res/backup_rules.xml').readAsStringSync();
    expect(full, isNot(contains('<include')));
    expect(excluded(full), domains.toSet());
  });

  test('Android 12+: nothing to the cloud backup, nothing in a device '
      'transfer', () {
    final rules = File('$res/data_extraction_rules.xml').readAsStringSync();
    expect(rules, isNot(contains('<include')));
    String section(String name) => RegExp(
      '<$name>(.*?)</$name>',
      dotAll: true,
    ).firstMatch(rules)!.group(1)!;
    expect(excluded(section('cloud-backup')), domains.toSet());
    expect(excluded(section('device-transfer')), domains.toSet());
  });

  test('iOS: the database folder is excluded from backups at launch', () {
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(delegate, contains('.applicationSupportDirectory'));
    expect(delegate, contains('isExcludedFromBackup = true'));
    final launch = RegExp(
      r'didFinishLaunchingWithOptions launchOptions.*?\{(.*?)return super',
      dotAll: true,
    ).firstMatch(delegate)!.group(1)!;
    expect(launch, contains('excludeDataFromBackup()'));
  });
}
