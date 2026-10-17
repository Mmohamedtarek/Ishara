import 'dart:async';
import 'dart:io';

import 'package:alchemist/alchemist.dart';
import 'package:drift/drift.dart';

/// Golden tests: "platform" goldens render real text with the bundled fonts
/// (readable, used for the screenshot review); "CI" goldens replace text with
/// blocks so they match on any OS. Platform goldens are local only: font
/// rasterising differs between machines, so CI (`CI=true`) checks CI goldens.
///
/// Every test app gets its own database in memory (`appDatabaseProvider`),
/// so drift's warning about several databases is expected.
Future<void> testExecutable(FutureOr<void> Function() testMain) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(enabled: !_ci),
    ),
    run: () async {
      await testMain();
    },
  );
}

final bool _ci = Platform.environment['CI'] == 'true';
