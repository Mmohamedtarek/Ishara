import 'dart:async';

import 'package:clock/clock.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/core/storage/storage_providers.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/learn_progress.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'learn_providers.g.dart';

/// Learn's view of the active pack's catalogue (`signs.json`).
@Riverpod(keepAlive: true)
Future<LearnCatalog> learnCatalog(Ref ref) async =>
    learnCatalogFrom(await ref.watch(signCatalogueProvider.future));

LearnCatalog learnCatalogFrom(SignCatalogue c) => LearnCatalog(
  signs: [
    for (final s in c.signs)
      LearnSign(label: s.label, glove: s.glove, avatar: s.avatar),
  ],
  modules: [
    for (final m in c.modules)
      LearnModule(id: m.id, signs: m.signs, watchOnly: m.watchOnly),
  ],
);

/// The activity log, in the phone's database (it syncs in step 10b).
@Riverpod(keepAlive: true)
ActivityRepository activityRepository(Ref ref) {
  final local = ref.watch(localDataProvider);
  final repo = LocalActivityRepository(
    ref.watch(appDatabaseProvider),
    initial: local.activity,
    broken: [
      for (final k in local.kept)
        if (LegacyKeys.isActivityBroken(k.key)) k,
    ],
  );
  ref.onDispose(repo.dispose);
  return repo;
}

/// The log's events, live.
@Riverpod(keepAlive: true)
Stream<List<ActivityEvent>> activityEvents(Ref ref) async* {
  final repo = ref.watch(activityRepositoryProvider);
  yield repo.events;
  yield* repo.changes;
}

/// The phone's local day now. Refreshed at the next local midnight, and
/// when Learn is shown again or the app comes back (the screen invalidates
/// it), so a new day starts the streak and the daily challenge.
@riverpod
LocalDay learnToday(Ref ref) {
  final now = clock.now();
  final midnight = DateTime(now.year, now.month, now.day + 1);
  final timer = Timer(midnight.difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return LocalDay.of(now);
}

/// Everything the Learn screen shows, computed from the log.
@riverpod
Future<LearnProgress> learnProgress(Ref ref) async {
  final catalog = await ref.watch(learnCatalogProvider.future);
  final events = await ref.watch(activityEventsProvider.future);
  return LearnProgress.compute(catalog, events, ref.watch(learnTodayProvider));
}

/// The signed-in account, live (null = guest).
@riverpod
Stream<AuthUser?> authUser(Ref ref) async* {
  final auth = ref.watch(authRepositoryProvider);
  yield auth.currentUser;
  yield* auth.userChanges;
}

/// Guest mode: no account signed in (prototype `state.guest`).
@riverpod
bool learnGuest(Ref ref) =>
    (ref.watch(authUserProvider).value ??
        ref.watch(authRepositoryProvider).currentUser) ==
    null;
