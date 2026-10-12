import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/ishara_tab_bar.dart';

import 'support/fake_glove.dart';
import 'support/fake_talk.dart';

/// A screen by key: the real onboarding screens (`screen-…`) or a skeleton
/// still waiting for its step (`skeleton-…`).
Finder _screen(String key) => find.byWidgetPredicate(
  (w) => w.key == ValueKey('skeleton-$key') || w.key == ValueKey('screen-$key'),
);

/// Pumps [n] frames [step] apart (screens with endless animations never
/// settle).
Future<void> _run(WidgetTester t, {int n = 10, int step = 100}) async {
  for (var i = 0; i < n; i++) {
    // a little real time too: some futures complete on the real event loop
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await t.pump(Duration(milliseconds: step));
  }
}

Future<GoRouter> _pumpApp(
  WidgetTester t, {
  String at = AppRoutes.splash,
  bool settle = true,
}) async {
  final router = buildRouter(initialLocation: at);
  addTearDown(router.dispose);
  final glove = FakeGloveSource();
  addTearDown(glove.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        gloveSourceProvider.overrideWithValue(glove),
        glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(delay: Duration.zero),
        ),
        // Talk's glove → text without the model isolate (its own tests run
        // the real pipeline)
        ...TalkFakes().overrides,
      ],
      child: const IsharaApp(),
    ),
  );
  if (settle) await t.pumpAndSettle();
  return router;
}

/// Scrolls the widget with [key] into view and taps it.
Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

Future<void> _tap(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('onboarding flow follows the prototype order', (t) async {
    await _pumpApp(t);
    final splash = find.byKey(const ValueKey('screen-splash'));
    expect(splash, findsOneWidget);
    expect(find.byType(IsharaTabBar), findsNothing);
    await t.tap(splash); // prototype: a tap ends the splash
    await t.pumpAndSettle();
    expect(_screen('welcome'), findsOneWidget);
    await _tap(t, 'Get started');
    expect(_screen('auth'), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('auth-name')),
        matching: find.byType(TextField),
      ),
      'Mona',
    );
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('auth-email')),
        matching: find.byType(TextField),
      ),
      'mona@example.com',
    );
    await t.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('auth-password')),
        matching: find.byType(TextField),
      ),
      'secret123',
    );
    await _tapKey(t, 'auth-submit');
    await _run(t, n: 8);
    expect(_screen('setup'), findsOneWidget);
    await _tapKey(t, 'setup-continue');
    await _run(t, n: 8);
    expect(_screen('pair'), findsOneWidget);
    // the fake glove is found at once
    await _tapKey(t, 'pair-connect-g1');
    await _run(t, n: 8);
    expect(find.text('Connected'), findsOneWidget);
    await _tapKey(t, 'pair-cta');
    await _run(t, n: 8);
    expect(_screen('calibrate'), findsOneWidget);
    for (var step = 0; step < 3; step++) {
      await _tapKey(t, 'cal-cta');
      await _run(t, n: 12); // the step, then 0.75 s before the next
    }
    expect(_screen('ready'), findsOneWidget);
    expect(find.text("You're all set"), findsOneWidget);
    await _tapKey(t, 'ready-talk');
    await _run(t, n: 8);
    expect(_screen('talk'), findsOneWidget);
    expect(find.byType(IsharaTabBar), findsOneWidget);
  });

  testWidgets('sign-in mode and back navigation', (t) async {
    final router = await _pumpApp(t, at: AppRoutes.welcome);
    await _tap(t, 'I already have an account');
    expect(find.text('Welcome back'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    expect(_screen('welcome'), findsOneWidget);
    await _tap(t, 'Continue as guest');
    expect(_screen('setup'), findsOneWidget);
  });

  testWidgets('tabs switch screens and keep the tab bar', (t) async {
    await _pumpApp(t, at: AppRoutes.talk);
    for (final (label, key) in [
      ('Learn', 'learn'),
      ('History', 'history'),
      ('Settings', 'settings'),
      ('Talk', 'talk'),
    ]) {
      await t.tap(
        find.descendant(
          of: find.byType(IsharaTabBar),
          matching: find.text(label),
        ),
      );
      await t.pumpAndSettle();
      expect(_screen(key), findsOneWidget, reason: label);
    }
  });

  testWidgets('tabs work with TalkBack / VoiceOver (semantic tap)', (t) async {
    final handle = t.ensureSemantics();
    await _pumpApp(t, at: AppRoutes.talk);
    Finder historyTab() => find.descendant(
      of: find.byType(IsharaTabBar),
      matching: find.bySemanticsLabel('History'),
    );
    final node = t.getSemantics(historyTab());
    expect(node.flagsCollection.isButton, isTrue);
    t.semantics.tap(find.semantics.byLabel('History'));
    await t.pumpAndSettle();
    expect(_screen('history'), findsOneWidget);
    expect(
      t.getSemantics(historyTab()).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    handle.dispose();
  });

  testWidgets('Learn -> mission (no tab bar) -> back to Learn', (t) async {
    await _pumpApp(t, at: AppRoutes.learn);
    await _tap(t, 'Start here');
    expect(_screen('mission'), findsOneWidget);
    expect(find.byType(IsharaTabBar), findsNothing);
    await _tap(t, 'Back to Learn');
    expect(_screen('learn'), findsOneWidget);
  });

  testWidgets('Settings exits: calibrate, pair, avatar studio, sign out', (
    t,
  ) async {
    final router = await _pumpApp(t, at: AppRoutes.settings);
    await _tap(t, 'Your avatar');
    expect(_screen('avatar'), findsOneWidget);
    await _tap(t, 'Save avatar');
    expect(_screen('settings'), findsOneWidget);
    // Pair and Calibrate animate without end: timed frames, not settle
    await t.tap(find.text('Pair a new glove'));
    await _run(t);
    expect(_screen('pair'), findsOneWidget);
    router.pop();
    await _run(t);
    await t.tap(find.text('Calibrate'));
    await _run(t);
    expect(_screen('calibrate'), findsOneWidget);
    router.go(AppRoutes.settings);
    await _run(t);
    await _tap(t, 'Sign out');
    expect(_screen('welcome'), findsOneWidget);
  });

  testWidgets('Arabic switches text and layout to RTL', (t) async {
    await _pumpApp(t, at: AppRoutes.welcome);
    expect(Directionality.of(t.element(_screen('welcome'))), TextDirection.ltr);
    await t.tap(find.byKey(const ValueKey('lang-toggle')));
    await t.pumpAndSettle();
    expect(Directionality.of(t.element(_screen('welcome'))), TextDirection.rtl);
    expect(find.text('يلا نبدأ'), findsOneWidget);
  });

  testWidgets('theme follows the system (Q-D3)', (t) async {
    t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
    await _pumpApp(t, at: AppRoutes.welcome);
    final ctx = t.element(_screen('welcome'));
    expect(Theme.of(ctx).scaffoldBackgroundColor, IsharaColors.dark.bg);

    t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await t.pumpAndSettle();
    expect(
      Theme.of(t.element(_screen('welcome'))).scaffoldBackgroundColor,
      IsharaColors.light.bg,
    );
  });

  /// Product of every Opacity above the screen (1 = fully visible).
  double opacityOf(WidgetTester t, String key) => t
      .widgetList<Opacity>(
        find.ancestor(of: _screen(key), matching: find.byType(Opacity)),
      )
      .fold(1, (v, o) => v * o.opacity);

  testWidgets('push: covered screen hides at once, new one slides in', (
    t,
  ) async {
    await _pumpApp(t, at: AppRoutes.welcome);
    await t.tap(find.text('Get started'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(opacityOf(t, 'welcome'), 0);
    expect(opacityOf(t, 'auth'), inExclusiveRange(0, 1));
    await t.pumpAndSettle();
    expect(opacityOf(t, 'auth'), 1);
  });

  testWidgets('back: leaving screen hides at once, previous slides in again', (
    t,
  ) async {
    final router = await _pumpApp(t, at: AppRoutes.welcome);
    await _tap(t, 'Get started');
    router.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    expect(opacityOf(t, 'auth'), 0, reason: 'leaving screen');
    await t.pump(const Duration(milliseconds: 100));
    expect(opacityOf(t, 'welcome'), inExclusiveRange(0, 1));
    final slide = t
        .widgetList<Transform>(
          find.ancestor(
            of: _screen('welcome'),
            matching: find.byType(Transform),
          ),
        )
        .map((w) => w.transform.getTranslation().x)
        .firstWhere((x) => x != 0);
    expect(slide, inExclusiveRange(0, IsharaMotion.slideOffset));
    await t.pumpAndSettle();
    expect(_screen('auth'), findsNothing);
    expect(opacityOf(t, 'welcome'), 1);
  });

  testWidgets('system back button pops the same way', (t) async {
    await _pumpApp(t, at: AppRoutes.welcome);
    await _tap(t, 'Get started');
    final handled = await t.binding.handlePopRoute();
    expect(handled, isTrue);
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    expect(opacityOf(t, 'auth'), 0);
    await t.pumpAndSettle();
    expect(_screen('welcome'), findsOneWidget);
  });

  testWidgets('hidden screens are out of the accessibility tree', (t) async {
    final handle = t.ensureSemantics();
    await _pumpApp(t, at: AppRoutes.welcome);
    await t.tap(find.text('Get started'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.semantics.byLabel('I already have an account'), findsNothing);
    await t.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('reduced motion: no entrance animation', (t) async {
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ScreenEntranceTransition(
            animation: const AlwaysStoppedAnimation(0),
            child: Container(key: const ValueKey('c')),
          ),
        ),
      ),
    );
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('entrance math: slide mirrors in RTL, pop rises and grows', (
    t,
  ) async {
    Future<Matrix4> transformAt(ScreenEntrance e, TextDirection dir) async {
      await t.pumpWidget(
        Directionality(
          textDirection: dir,
          child: ScreenEntranceTransition(
            animation: const AlwaysStoppedAnimation(0),
            entrance: e,
            child: const SizedBox(),
          ),
        ),
      );
      return t.widget<Transform>(find.byType(Transform)).transform;
    }

    final ltr = await transformAt(ScreenEntrance.slide, TextDirection.ltr);
    final rtl = await transformAt(ScreenEntrance.slide, TextDirection.rtl);
    expect(ltr.getTranslation().x, IsharaMotion.slideOffset);
    expect(rtl.getTranslation().x, -IsharaMotion.slideOffset);
    final pop = await transformAt(ScreenEntrance.pop, TextDirection.ltr);
    expect(pop.getTranslation().y, IsharaMotion.popOffset);
    expect(pop.entry(0, 0), closeTo(IsharaMotion.popScale, 1e-9));
    expect(pop.entry(1, 1), closeTo(IsharaMotion.popScale, 1e-9));
  });

  test('route helpers', () {
    expect(AppRoutes.auth(signUp: true), '/auth?mode=signup');
    expect(AppRoutes.auth(signUp: false), '/auth?mode=signin');
    expect(AppRoutes.mission('a b'), '/mission/a%20b');
    expect(AppRoutes.tabs, hasLength(4));
  });
}
