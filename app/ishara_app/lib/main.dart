import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/config/app_rules.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/open_storage.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setUpLogging();
  final log = Log('app');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.failure(
      'flutter_error',
      UnexpectedFailure(
        details.exceptionAsString(),
        cause: details.exception,
        stackTrace: details.stack,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log.failure(
      'uncaught_error',
      UnexpectedFailure(error.toString(), cause: error, stackTrace: stack),
    );
    return true;
  };
  // The phone's database, with the old key-value store migrated into it
  // (step 10a). If it can't open, the app still runs on the old store.
  final storage = await openStorage();
  final container = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(storage.kv),
      appDatabaseProvider.overrideWithValue(storage.db),
      localDataProvider.overrideWithValue(storage.data),
      storageHealthProvider.overrideWithValue(storage.health),
    ],
  );
  // The first screens name the avatar ("Hi, I'm Nour!"): load the (tiny)
  // cast before the first frame so no text shows without the name.
  try {
    // app_rules.json: data the feed and SOS need from the first message
    await container.read(appRulesProvider.future);
  } on Object catch (e, st) {
    log.failure(
      'rules_load',
      UnexpectedFailure('app_rules.json', cause: e, stackTrace: st),
    );
  }
  try {
    await container.read(avatarCastProvider.future);
  } on Object catch (e, st) {
    log.failure(
      'cast_load',
      UnexpectedFailure('cast.json', cause: e, stackTrace: st),
    );
  }
  runApp(
    UncontrolledProviderScope(container: container, child: const IsharaApp()),
  );
}
