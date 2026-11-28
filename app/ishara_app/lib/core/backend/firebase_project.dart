import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// The real Firebase project's values (Spark plan, Q-B1), given at build
/// time. They are never committed (the repo is public):
/// `python3 app/tools/firebase_defines.py` writes them from the git-ignored
/// `android/app/google-services.json` into the git-ignored
/// `firebase.defines.json`, and a build reads them with
/// `--dart-define=BACKEND=firebase`
/// `--dart-define-from-file=firebase.defines.json`.
/// The Android build refuses `BACKEND=firebase` without them
/// (`android/app/build.gradle.kts`). They identify the project and are not
/// secrets; the security rules protect the data.
abstract final class FirebaseDefines {
  static const apiKey = 'FIREBASE_API_KEY';
  static const appId = 'FIREBASE_APP_ID';
  static const senderId = 'FIREBASE_SENDER_ID';
  static const projectId = 'FIREBASE_PROJECT_ID';
  static const storageBucket = 'FIREBASE_STORAGE_BUCKET';
}

const _defines = <String, String>{
  FirebaseDefines.apiKey: String.fromEnvironment(FirebaseDefines.apiKey),
  FirebaseDefines.appId: String.fromEnvironment(FirebaseDefines.appId),
  FirebaseDefines.senderId: String.fromEnvironment(FirebaseDefines.senderId),
  FirebaseDefines.projectId: String.fromEnvironment(FirebaseDefines.projectId),
  FirebaseDefines.storageBucket: String.fromEnvironment(
    FirebaseDefines.storageBucket,
  ),
};

/// The project's options for this platform from [defines] (the build's
/// dart-defines by default), or null when a required value is missing or
/// the platform has none (only Android is registered; iOS isn't built).
FirebaseOptions? firebaseProjectOptions({
  Map<String, String> defines = _defines,
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return null;
  }
  String? value(String key) =>
      (defines[key] ?? '').isEmpty ? null : defines[key];
  final apiKey = value(FirebaseDefines.apiKey);
  final appId = value(FirebaseDefines.appId);
  final senderId = value(FirebaseDefines.senderId);
  final projectId = value(FirebaseDefines.projectId);
  if (apiKey == null || appId == null || senderId == null) return null;
  if (projectId == null) return null;
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    storageBucket: value(FirebaseDefines.storageBucket),
  );
}

/// The Firebase Emulator Suite on the laptop (`firebase/`): a `demo-`
/// project, which the emulators treat as emulator-only, so nothing can
/// reach a real Firebase project.
const emulatorProjectId = 'demo-ishara';

const emulatorOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:android:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: emulatorProjectId,
);

/// Where the emulators listen, as the device sees it. On the phone over
/// USB (the default): `adb reverse tcp:9099 tcp:9099` and
/// `adb reverse tcp:8080 tcp:8080`. On an Android emulator:
/// `--dart-define=EMULATOR_HOST=10.0.2.2`.
const emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);
const emulatorAuthPort = 9099;
const emulatorFirestorePort = 8080;
