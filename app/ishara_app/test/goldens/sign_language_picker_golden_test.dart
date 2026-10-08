import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/sign_language_picker.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

Widget _themed(Locale locale, Brightness b, Widget child) => ProviderScope(
  child: Localizations(
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
        child: Builder(
          builder: (context) => ColoredBox(
            color: context.colors.bg,
            child: Padding(padding: const EdgeInsets.all(18), child: child),
          ),
        ),
      ),
    ),
  ),
);

/// The dialog's content, laid out as it appears (AlertDialog needs a route).
class _DialogPreview extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Builder(
      builder: (context) {
        final c = context.colors;
        return Material(
          type: MaterialType.transparency,
          child: AlertDialog(
            backgroundColor: c.bg2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(color: c.line),
            ),
            content: Text(
              l.arslComingSoon,
              style: context.text.rowTitle.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            actions: [TextButton(onPressed: () {}, child: Text(l.ok))],
          ),
        );
      },
    );
  }
}

Future<void> main() async {
  await goldenTest(
    'sign language picker and ArSL dialog: EN / AR x light / dark',
    fileName: 'sign_language_picker',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        for (final locale in const [Locale('en'), Locale('ar')])
          for (final b in [Brightness.light, Brightness.dark])
            GoldenTestScenario(
              name: '${locale.languageCode} ${b.name}',
              constraints: const BoxConstraints.tightFor(width: 390),
              child: _themed(
                locale,
                b,
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SignLanguagePicker(),
                    SizedBox(height: 16),
                    _DialogPreview(),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}
