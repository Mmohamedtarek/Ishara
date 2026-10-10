import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_mark.dart';
import 'package:ishara_app/features/onboarding/presentation/splash_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import '../support/fake_glove.dart';

Widget _app({
  bool reduceMotion = false,
  KeyValueStore? store,
  FakeGloveSource? glove,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const Scaffold(body: Text('WELCOME')),
      ),
      GoRoute(
        path: '/talk',
        builder: (_, _) => const Scaffold(body: Text('TALK')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(store ?? MemoryKeyValueStore()),
      gloveSourceProvider.overrideWithValue(glove ?? FakeGloveSource()),
      glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
    ],
    child: _themed(reduceMotion, router),
  );
}

Widget _themed(bool reduceMotion, GoRouter router) {
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
  textStyleChecks();
  lateSizeCheck();
  testWidgets('mark, name (Latin), tagline and bar; Welcome after 2.1 s', (
    t,
  ) async {
    await t.pumpWidget(_app());
    expect(find.byType(IsharaMark), findsOneWidget);
    expect(find.text('Ishara'), findsOneWidget);
    expect(find.text('Your hands speak.'), findsOneWidget);
    // the mark is on screen from the first frame, at the screen centre
    // (where the native launch screen shows it); the name pops in later
    final screen = t.getCenter(find.byKey(const ValueKey('screen-splash')));
    expect(t.getCenter(find.byType(IsharaMark)), screen);
    await t.pump(); // the clock starts after the first frame
    await t.pump(const Duration(milliseconds: 150));
    expect(_opacityOf(t, find.text('Ishara')), 0);
    final halfway = t.getCenter(find.byType(IsharaMark));
    expect(halfway.dy, lessThan(screen.dy), reason: 'moving up');
    // after 300 ms it sits in its place in the centred group (prototype)
    await t.pump(const Duration(milliseconds: 200));
    final placed = t.getCenter(find.byType(IsharaMark));
    expect(placed.dy, lessThan(halfway.dy));
    expect(placed.dx, screen.dx);
    final groupTop = placed.dy - 44;
    final groupBottom = t.getBottomLeft(find.byType(ClipRRect).last).dy;
    expect(
      (groupTop + groupBottom) / 2,
      closeTo(screen.dy, 1),
      reason: 'the whole group is centred, as the prototype',
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(t.getCenter(find.byType(IsharaMark)), placed, reason: 'no drift');
    await t.pump(const Duration(milliseconds: 1600));
    expect(_opacityOf(t, find.text('Your hands speak.')), 1);
    expect(find.text('WELCOME'), findsNothing);
    await t.pump(const Duration(milliseconds: 400)); // 2.15 s
    await t.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
  });

  testWidgets('S6-2: after onboarding it goes to Talk and reconnects the '
      'paired glove', (t) async {
    final kv = MemoryKeyValueStore();
    final store = OnboardingStore(kv);
    await store.saveDone(done: true);
    await store.saveGlove(const PairedGlove(id: 'g1', name: 'Ishara-3FA2'));
    final glove = FakeGloveSource();
    await t.pumpWidget(_app(store: kv, glove: glove));
    await t.tap(find.byKey(const ValueKey('screen-splash')));
    for (var i = 0; i < 5; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('TALK'), findsOneWidget);
    expect(glove.commands, ['scan', 'connect g1']);
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
    final placed = t.getCenter(find.byType(IsharaMark));
    expect(
      placed.dy,
      lessThan(t.getCenter(find.byKey(const ValueKey('screen-splash'))).dy),
      reason: 'already in its place: no movement',
    );
    await t.pump();
    expect(t.getCenter(find.byType(IsharaMark)), placed);
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

/// WidgetsApp's error text style: what a Text shows (yellow double
/// underline) when no Material / DefaultTextStyle sits above it.
bool _isDebugFallback(TextStyle? s) =>
    s != null &&
    s.decoration == TextDecoration.underline &&
    s.decorationStyle == TextDecorationStyle.double;

void textStyleChecks() {
  testWidgets('no Text on the splash falls back to the debug style', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWith((ref) => buildRouter())],
        child: const IsharaApp(),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 1800));
    final splash = find.byKey(const ValueKey('screen-splash'));
    final texts = find.descendant(of: splash, matching: find.byType(RichText));
    expect(texts, findsAtLeastNWidgets(2));
    for (final e in texts.evaluate()) {
      final rich = e.widget as RichText;
      expect(
        _isDebugFallback(rich.text.style) ||
            _isDebugFallback(DefaultTextStyle.of(e).style),
        isFalse,
        reason: '"${rich.text.toPlainText()}" uses the debug text style',
      );
    }
    // the check works: a Text with no Material above it has that style
    await t.pumpWidget(const MaterialApp(home: Text('x')));
    expect(
      _isDebugFallback(DefaultTextStyle.of(t.element(find.text('x'))).style),
      isTrue,
    );
  });
}

void lateSizeCheck() {
  testWidgets('a window that gets its size late: the mark still ends in '
      'its place (not in a corner)', (t) async {
    final size = ValueNotifier(Size.zero);
    addTearDown(size.dispose);
    await t.pumpWidget(
      MaterialApp(
        theme: IsharaTheme.build(brightness: Brightness.dark, isArabic: false),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ValueListenableBuilder(
          valueListenable: size,
          builder: (_, s, _) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: s,
              child: const SplashScreen(hold: Duration(days: 1)),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 50));
    size.value = const Size(390, 844); // the real size arrives
    await t.pump(const Duration(milliseconds: 600));
    final mark = t.getCenter(find.byType(IsharaMark));
    expect(mark.dx, closeTo(195, .5));
    expect(mark.dy, greaterThan(200), reason: 'in the group, not at the top');
    expect(mark.dy, lessThan(422), reason: 'above the screen centre');
    await t.pumpWidget(const SizedBox());
  });
}
