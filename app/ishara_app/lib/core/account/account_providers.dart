import 'dart:async';

import 'package:ishara_app/core/account/account_deletion.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/phrases/saved_phrases_repository.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/drift_key_value_store.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/core/sync/sync_providers.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/sos/application/sos_controller.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_providers.g.dart';

@Riverpod(keepAlive: true)
AccountDeletion accountDeletion(Ref ref) => AccountDeletion(
  db: ref.watch(appDatabaseProvider),
  remote: ref.watch(remoteStoreProvider),
  auth: ref.watch(authRepositoryProvider),
  wipeLocal: () => wipeLocalData(ref),
  pauseSync: () async => await ref.read(syncEngineProvider)?.suspend(),
  resumeSync: () async => await ref.read(syncEngineProvider)?.resume(),
);

/// Account deletion (Q-B1): every table but the pending flag, and what the
/// running app holds; onboarding starts again (Welcome).
Future<void> wipeLocalData(Ref ref) async {
  final db = ref.read(appDatabaseProvider);
  await db.transaction(() async {
    for (final t in db.allTables) {
      if (t == db.meta) continue;
      await db.delete(t).go();
    }
    await (db.delete(
      db.meta,
    )..where((t) => t.key.isNotValue(AccountDeletion.kPending))).go();
  });
  await ref.read(conversationRepositoryProvider).deleteAll();
  final phrases = ref.read(savedPhrasesRepositoryProvider);
  if (phrases is LocalSavedPhrasesRepository) await phrases.clearAll();
  final activity = ref.read(activityRepositoryProvider);
  if (activity is LocalActivityRepository) await activity.clearAll();
  final contacts = ref.read(emergencyContactsRepositoryProvider);
  if (contacts is LocalEmergencyContactsRepository) await contacts.clearAll();
  final kv = ref.read(keyValueStoreProvider);
  if (kv is DriftKeyValueStore) {
    await kv.clearAll();
  } else {
    for (final k in kv.keys.toList()) {
      await kv.remove(k);
    }
  }
  // (a removed synced value may have queued the settings again)
  await db.delete(db.outbox).go();
  ref
    ..invalidate(settingsStoreProvider)
    ..invalidate(onboardingStoreProvider);
}

/// Where a deletion stands, for Settings and the app root.
enum DeletionState { idle, deleting, needsPassword, failed, done }

@Riverpod(keepAlive: true)
class AccountDeletionController extends _$AccountDeletionController {
  @override
  DeletionState build() => DeletionState.idle;

  AccountDeletion get _deletion => ref.read(accountDeletionProvider);

  Future<DeletionState> _go(Future<DeletionResult> Function() run) async {
    state = DeletionState.deleting;
    DeletionResult r;
    try {
      r = await run();
    } on AuthFailure {
      // the password was refused before anything was deleted
      state = DeletionState.idle;
      rethrow;
    } on Object {
      r = DeletionResult.failed;
    }
    return state = switch (r) {
      DeletionResult.done => DeletionState.done,
      DeletionResult.needsPassword => DeletionState.needsPassword,
      DeletionResult.failed => DeletionState.failed,
      DeletionResult.nothing => DeletionState.idle,
    };
  }

  /// Settings › Delete account, after the email and the password. Throws
  /// `AuthFailure` (wrong password, offline): nothing was deleted.
  Future<DeletionState> start(String password) =>
      _go(() => _deletion.start(password: password));

  /// At start: a deletion an earlier run left pending.
  Future<DeletionState> resume() => _go(_deletion.resume);

  /// The password, when the server asked for it. Throws `AuthFailure`
  /// (wrong password) and stays [DeletionState.needsPassword].
  Future<DeletionState> withPassword(String password) async {
    await ref.read(authRepositoryProvider).reauthenticate(password);
    return await _go(_deletion.resume);
  }

  /// The user saw the end state.
  void acknowledge() => state = DeletionState.idle;
}
