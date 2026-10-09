import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/features/onboarding/presentation/splash_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

Widget _themed(Locale locale, Brightness b) => Localizations(
  locale: locale,
  delegates: AppLocalizations.localizationsDelegates,
  child: Directionality(
    textDirection: locale.languageCode == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr,
    child: Theme(
      data: IsharaTheme.build(
        brightness: b,
        isArabic: locale.languageCode == 'ar',
      ),
      child: const MediaQuery(
        // the final frame of the entrance (pop-ins and the bar done)
        data: MediaQueryData(disableAnimations: true),
        child: SplashScreen(hold: Duration(days: 1)),
      ),
    ),
  ),
);

Future<void> main() async {
  await goldenTest(
    'splash: EN / AR x light / dark',
    fileName: 'splash',
    builder: () => GoldenTestGroup(
      columns: 4,
      children: [
        for (final locale in const [Locale('en'), Locale('ar')])
          for (final b in [Brightness.light, Brightness.dark])
            GoldenTestScenario(
              name: '${locale.languageCode} ${b.name}',
              constraints: const BoxConstraints.tightFor(
                width: 390,
                height: 844,
              ),
              child: _themed(locale, b),
            ),
      ],
    ),
  );
}
