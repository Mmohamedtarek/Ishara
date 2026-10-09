import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_mark.dart';
import 'package:ishara_app/features/onboarding/presentation/splash_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

Widget _app({bool reduceMotion = false}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const Scaffold(body: Text('WELCOME')),
      ),
    ],
  );
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: MaterialApp.router(
      routerConfig: router,
      theme: IsharaTheme.build(brightness: Brightness.light, isArabic: false),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    ),
  );
}

double _opacityOf(WidgetTester t, Finder f) => t
    .widget<Opacity>(find.ancestor(of: f, matching: find.byType(Opacity)).first)
    .opacity;

void main() {
  testWidgets('mark, name (Latin), tagline and bar; Welcome after 2.1 s', (
    t,
  ) async {
    await t.pumpWidget(_app());
    expect(find.byType(IsharaMark), findsOneWidget);
    expect(find.text('Ishara'), findsOneWidget);
    expect(find.text('Your hands speak.'), findsOneWidget);
    // pop-ins: the mark first, the name .15 s later, the tagline .3 s later
    await t.pump(const Duration(milliseconds: 150));
    expect(_opacityOf(t, find.byType(IsharaMark)), greaterThan(0));
    expect(_opacityOf(t, find.text('Ishara')), 0);
    await t.pump(const Duration(milliseconds: 1600));
    expect(_opacityOf(t, find.text('Your hands speak.')), 1);
    expect(find.text('WELCOME'), findsNothing);
    await t.pump(const Duration(milliseconds: 400)); // 2.15 s
    await t.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
  });

  testWidgets('a tap ends it at once (prototype), with a semantic action', (
    t,
  ) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_app());
    expect(find.bySemanticsLabel('Ishara. Your hands speak.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('screen-splash')));
    await t.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
    h.dispose();
  });

  testWidgets('reduce motion: everything shown at once', (t) async {
    await t.pumpWidget(_app(reduceMotion: true));
    await t.pump();
    expect(_opacityOf(t, find.text('Your hands speak.')), 1);
    final bar = t.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(bar.widthFactor, 1);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
  });

  testWidgets('Arabic: the name stays "Ishara" in Latin letters', (t) async {
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: IsharaTheme.build(brightness: Brightness.dark, isArabic: true),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const SplashScreen(hold: Duration(days: 1)),
      ),
    );
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Ishara'), findsOneWidget);
    expect(find.text('إيديك بتتكلم.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
