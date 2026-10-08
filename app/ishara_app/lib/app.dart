import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Root widget: theme (light / dark / system), language and RTL, router.
class IsharaApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsControllerProvider);
    final router = ref.watch(appRouterProvider);
    final isArabic = settings.language == AppLanguage.ar;
    ThemeData theme(Brightness b) => IsharaTheme.build(
      brightness: b,
      isArabic: isArabic,
      highContrast: settings.highContrast,
      bigText: settings.bigText,
    );
    return MaterialApp.router(
      title: 'Ishara',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      themeMode: settings.themeMode,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      // The stage background (`.stage { background: var(--bg) }`) shows
      // behind a screen while it fades in.
      builder: (context, child) =>
          ColoredBox(color: context.colors.bg, child: child),
    );
  }
}
