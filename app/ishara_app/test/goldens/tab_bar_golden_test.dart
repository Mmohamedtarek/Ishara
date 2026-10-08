import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_tab_bar.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

Widget _bar(Locale locale, Brightness b, int selected) => Localizations(
  locale: locale,
  delegates: AppLocalizations.localizationsDelegates,
  child: Builder(
    builder: (context) {
      final l = AppLocalizations.of(context);
      return Theme(
        data: IsharaTheme.build(
          brightness: b,
          isArabic: locale.languageCode == 'ar',
        ),
        child: Builder(
          builder: (context) => ColoredBox(
            color: context.colors.bg,
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: IsharaTabBar(
                selected: selected,
                onSelect: (_) {},
                items: [
                  IsharaTabItem(icon: 'chat', label: l.tabTalk),
                  IsharaTabItem(icon: 'book', label: l.tabLearn),
                  IsharaTabItem(icon: 'clock', label: l.tabHistory),
                  IsharaTabItem(icon: 'gear', label: l.tabSettings),
                ],
              ),
            ),
          ),
        ),
      );
    },
  ),
);

Future<void> main() async {
  await goldenTest(
    'tab bar: EN / AR x light / dark',
    fileName: 'tab_bar',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final locale in const [Locale('en'), Locale('ar')])
          for (final b in Brightness.values)
            GoldenTestScenario(
              name: '${locale.languageCode} ${b.name}',
              constraints: const BoxConstraints.tightFor(width: 390),
              child: Directionality(
                textDirection: locale.languageCode == 'ar'
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: _bar(locale, b, 1),
              ),
            ),
      ],
    ),
  );
}
