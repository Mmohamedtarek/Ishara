import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import 'fake_glove.dart';

/// The fakes a screen test can inspect.
class Harness {
  new({
    FakeGloveSource? glove,
    FakeGlovePermissions? perms,
    FakeAuthRepository? auth,
    KeyValueStore? store,
  }) : glove = glove ?? FakeGloveSource(),
       perms = perms ?? FakeGlovePermissions(),
       auth = auth ?? FakeAuthRepository(delay: Duration.zero),
       store = store ?? MemoryKeyValueStore();

  final FakeGloveSource glove;
  final FakeGlovePermissions perms;
  final FakeAuthRepository auth;
  final KeyValueStore store;
  late final GoRouter router;

  /// Where the screen led (stub routes show their path).
  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

/// Pumps [screen] on a phone (390 × 844) with every fake, and stub routes
/// for the other screens.
Future<Harness> pumpScreen(
  WidgetTester t,
  Widget screen, {
  Harness? harness,
  bool dark = true,
  AppLanguage language = AppLanguage.en,
  List<Override> overrides = const [],
}) async {
  final h = harness ?? Harness();
  addTearDown(h.glove.dispose);
  addTearDown(h.auth.dispose);
  t.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(t.view.reset);
  Widget stub(String path) => Scaffold(body: Text('route:$path'));
  h.router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, _) => screen),
      for (final p in [
        AppRoutes.welcome,
        AppRoutes.setup,
        AppRoutes.pair,
        AppRoutes.calibrate,
        AppRoutes.ready,
        AppRoutes.talk,
      ])
        GoRoute(path: p, builder: (_, s) => stub(s.uri.toString())),
    ],
  );
  addTearDown(h.router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        gloveSourceProvider.overrideWithValue(h.glove),
        glovePermissionsProvider.overrideWithValue(h.perms),
        authRepositoryProvider.overrideWithValue(h.auth),
        keyValueStoreProvider.overrideWithValue(h.store),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: h.router,
        locale: language.locale,
        theme: IsharaTheme.build(
          brightness: dark ? Brightness.dark : Brightness.light,
          isArabic: language == AppLanguage.ar,
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
      ),
    ),
  );
  await settle(t);
  return h;
}

/// Frames plus a little real time (some futures complete on the real
/// event loop, not on the test's fake clock).
Future<void> settle(WidgetTester t, {int n = 5}) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Scrolls [f] into view and taps it.
Future<void> tapIt(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settle(t);
}

/// The text field inside the widget with [key].
Finder field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);
