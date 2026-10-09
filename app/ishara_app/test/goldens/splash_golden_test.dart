import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/settings/app_settings.dart';

/// Settings fixed for one scenario (language, theme).
class _Fixed extends AppSettingsController {
  new(this.settings);
  final AppSettings settings;
  @override
  AppSettings build() => settings;
}

/// The real app root and route (IsharaApp → router → splash), as on the
/// phone: anything the root fails to provide (Material, text styles)
/// shows up here.
Widget _app(AppLanguage language, ThemeMode mode) => ProviderScope(
  overrides: [
    appSettingsControllerProvider.overrideWith(
      () => _Fixed(AppSettings(language: language, themeMode: mode)),
    ),
    appRouterProvider.overrideWith((ref) => buildRouter()),
  ],
  child: const IsharaApp(),
);

Future<void> main() async {
  await goldenTest(
    'splash (real app root): EN / AR x light / dark',
    fileName: 'splash',
    // the entrance done (1.7 s), before it moves on to Welcome (2.1 s)
    pumpBeforeTest: (t) async {
      await t.pump(); // the splash's clock starts after its first frame
      await t.pump(const Duration(milliseconds: 1800));
    },
    builder: () => GoldenTestGroup(
      columns: 4,
      children: [
        for (final lang in AppLanguage.values)
          for (final mode in [ThemeMode.light, ThemeMode.dark])
            GoldenTestScenario(
              name: '${lang.name} ${mode.name}',
              constraints: const BoxConstraints.tightFor(
                width: 390,
                height: 844,
              ),
              child: _app(lang, mode),
            ),
      ],
    ),
  );
}
