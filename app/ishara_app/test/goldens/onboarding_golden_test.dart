import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

import '../support/fake_glove.dart';

/// Settings fixed for one scenario (language, theme).
class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// One onboarding screen through the real app root and router, with the
/// fakes (glove, permissions, accounts, store).
Widget _app(
  String route,
  AppLanguage language,
  ThemeMode mode, {
  FakeGloveSource Function()? glove,
  FakeGlovePermissions Function()? perms,
}) {
  final g = (glove ?? FakeGloveSource.new)();
  return ProviderScope(
    overrides: [
      appSettingsControllerProvider.overrideWith(
        () => _Fixed(AppSettings(language: language, themeMode: mode)),
      ),
      appRouterProvider.overrideWith(
        (ref) => buildRouter(initialLocation: route),
      ),
      gloveSourceProvider.overrideWithValue(g),
      glovePermissionsProvider.overrideWithValue(
        (perms ?? FakeGlovePermissions.new)(),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(delay: Duration.zero),
      ),
      keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
    ],
    child: const IsharaApp(),
  );
}

/// A connected glove (Pair "connected", Calibrate, Ready).
FakeGloveSource _connected() {
  final g = FakeGloveSource();
  g.connect(g.found.single).ignore();
  return g;
}

Future<void> _screen(
  String name,
  String route, {
  FakeGloveSource Function()? glove,
  FakeGlovePermissions Function()? perms,
}) => goldenTest(
  '$name: EN / AR x light / dark',
  fileName: 'onboarding_$name',
  // entrances done; endless animations (radar, live badge) caught mid-way
  pumpBeforeTest: (t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await t.pump(const Duration(milliseconds: 200));
    }
  },
  builder: () => GoldenTestGroup(
    columns: 4,
    children: [
      for (final lang in AppLanguage.values)
        for (final mode in [ThemeMode.light, ThemeMode.dark])
          GoldenTestScenario(
            name: '${lang.name} ${mode.name}',
            constraints: const BoxConstraints.tightFor(width: 390, height: 844),
            child: _app(route, lang, mode, glove: glove, perms: perms),
          ),
    ],
  ),
);

Future<void> main() async {
  await _screen('welcome', AppRoutes.welcome);
  await _screen('create_account', AppRoutes.auth(signUp: true));
  await _screen('sign_in', AppRoutes.auth(signUp: false));
  await _screen('setup', AppRoutes.setup);
  await _screen('pair_found', AppRoutes.pair);
  await _screen('pair_connected', AppRoutes.pair, glove: _connected);
  await _screen(
    'pair_permission',
    AppRoutes.pair,
    perms: () => FakeGlovePermissions(answer: GlovePermission.denied),
  );
  await _screen(
    'pair_not_found',
    AppRoutes.pair,
    glove: () => FakeGloveSource(found: const []),
  );
  await _screen('calibrate', AppRoutes.calibrate, glove: _connected);
  await _screen('ready', AppRoutes.ready, glove: _connected);
  await _screen(
    'ready_skipped',
    AppRoutes.readyAfter(skipped: true),
    glove: _connected,
  );
}
