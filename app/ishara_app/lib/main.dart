import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

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
  // The saved onboarding answers (S6-2). If the phone store can't open, the
  // app still runs (in memory) and onboarding shows again.
  KeyValueStore store;
  try {
    store = await SharedPrefsKeyValueStore.open();
  } on Object catch (e, st) {
    log.failure(
      'store_open',
      UnexpectedFailure('key-value store', cause: e, stackTrace: st),
    );
    store = MemoryKeyValueStore();
  }
  final container = ProviderContainer(
    overrides: [keyValueStoreProvider.overrideWithValue(store)],
  );
  // The first screens name the avatar ("Hi, I'm Nour!"): load the (tiny)
  // cast before the first frame so no text shows without the name.
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
