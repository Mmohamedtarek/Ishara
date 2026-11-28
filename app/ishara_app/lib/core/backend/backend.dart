import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ishara_app/core/backend/firebase_project.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';

/// Where accounts and the sync go (`--dart-define=BACKEND=…`, step 10b).
enum Backend {
  /// On the phone only: the local fakes (no network).
  fake,

  /// The Firebase Emulator Suite on the laptop (demo project).
  emulator,

  /// The real Firebase project.
  firebase,

  /// Firebase (or the emulators) was asked for but couldn't start: no
  /// accounts and no sync this run, the app works as a guest (user
  /// 2026-11-27: never in-memory accounts that vanish at restart).
  unavailable,
}

/// What `--dart-define=BACKEND` asks for that this build can't do. The
/// Android build already refuses these (`android/app/build.gradle.kts`);
/// this catches any other way in.
class BackendConfigError extends StateError {
  new(super.message);
}

/// The backend for this build: fake unless `--dart-define=BACKEND=…` says
/// otherwise, in every build mode (the repo is public and holds no project
/// config, so CI and the tests always run on the fakes). An unknown value,
/// or firebase without the project's options ([hasOptions]), throws
/// [BackendConfigError]: a build meant for real accounts must never run on
/// the fakes by mistake.
Backend resolveBackend({
  required bool hasOptions,
  String define = const String.fromEnvironment('BACKEND'),
}) {
  if (define.isEmpty) return Backend.fake;
  final wanted = Backend.values.asNameMap()[define];
  if (wanted == null) {
    throw BackendConfigError(
      'BACKEND=$define: use fake, emulator or firebase.',
    );
  }
  if (wanted == Backend.firebase && !hasOptions) {
    throw BackendConfigError(
      "BACKEND=firebase needs the Firebase project's values: run "
      'python3 app/tools/firebase_defines.py, then build with '
      '--dart-define-from-file=firebase.defines.json.',
    );
  }
  return wanted;
}

/// Starts Firebase for [backend] before the first frame. Firestore keeps no
/// cache of its own: the phone's database is the source of truth and the
/// sync's outbox does the retrying (Phase 0). If Firebase can't start, the
/// app runs on the fakes (logged).
Future<Backend> startBackend(Backend backend) async {
  if (backend == Backend.fake || backend == Backend.unavailable) {
    return backend;
  }
  final log = Log('backend');
  try {
    if (backend == Backend.emulator) {
      await Firebase.initializeApp(options: emulatorOptions);
      // the host as given: 127.0.0.1 is the phone itself (adb reverse);
      // the plugins would turn it into the Android emulator's 10.0.2.2
      await FirebaseAuth.instance.useAuthEmulator(
        emulatorHost,
        emulatorAuthPort,
        automaticHostMapping: false,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(
        emulatorHost,
        emulatorFirestorePort,
        automaticHostMapping: false,
      );
    } else {
      await Firebase.initializeApp(options: firebaseProjectOptions());
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    log.info('started', {'backend': backend.name});
    return backend;
  } on Object catch (e, st) {
    log.failure(
      'start_failed',
      UnexpectedFailure('firebase', cause: e, stackTrace: st),
    );
    return Backend.unavailable;
  }
}
