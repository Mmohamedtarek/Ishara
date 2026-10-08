import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';

void main() {
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
  runApp(const ProviderScope(child: IsharaApp()));
}
