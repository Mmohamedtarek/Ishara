import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/backend/backend.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/core/sync/remote_store.dart';
import 'package:ishara_app/core/sync/sync_engine.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync_providers.g.dart';

/// Firestore behind [RemoteStore]; null in the fake backend (accounts live
/// in memory, nothing syncs) and when Firebase couldn't start (no accounts).
@Riverpod(keepAlive: true)
RemoteStore? remoteStore(Ref ref) => switch (ref.watch(backendProvider)) {
  Backend.fake || Backend.unavailable => null,
  Backend.firebase ||
  Backend.emulator => FirestoreRemoteStore(FirebaseFirestore.instance),
};

/// The sync (step 10b), started with the app; null without a remote.
@Riverpod(keepAlive: true)
SyncEngine? syncEngine(Ref ref) {
  final remote = ref.watch(remoteStoreProvider);
  if (remote == null) return null;
  final phrases = ref.watch(savedPhrasesRepositoryProvider);
  final activity = ref.watch(activityRepositoryProvider);
  final kv = ref.watch(keyValueStoreProvider);
  final engine = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    remote: remote,
    auth: ref.watch(authRepositoryProvider),
    phrases: phrases is LocalSavedPhrasesRepository ? phrases : null,
    activity: activity is LocalActivityRepository ? activity : null,
    prefs: kv is DriftKeyValueStore ? kv : null,
    // the account's settings are on the phone now: every screen reloads
    onSettingsApplied: () => ref
      ..invalidate(settingsStoreProvider)
      ..invalidate(onboardingStoreProvider),
  )..start();
  ref.onDispose(engine.dispose);
  return engine;
}

/// Sign-out's view of the sync (S10-6).
@Riverpod(keepAlive: true)
SyncControl? syncControl(Ref ref) => ref.watch(syncEngineProvider);

/// What Settings shows under the account (S10-8).
@Riverpod(keepAlive: true)
ValueListenable<SyncState> syncState(Ref ref) =>
    ref.watch(syncEngineProvider)?.state ?? ValueNotifier(SyncState.off);
