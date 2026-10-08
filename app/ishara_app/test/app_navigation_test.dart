import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/ishara_tab_bar.dart';

Finder _screen(String key) => find.byKey(ValueKey('skeleton-$key'));

Future<GoRouter> _pumpApp(
  WidgetTester t, {
  String at = AppRoutes.splash,
}) async {
  final router = buildRouter(initialLocation: at);
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [appRouterProvider.overrideWithValue(router)],
      child: const IsharaApp(),
    ),
  );
  await t.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('onboarding flow follows the prototype order', (t) async {
    await _pumpApp(t);
    expect(_screen('splash'), findsOneWidget);
    expect(find.byType(IsharaTabBar), findsNothing);
    await _tap(t, 'Get started');
    expect(_screen('welcome'), findsOneWidget);
    await _tap(t, 'Get started');
    expect(_screen('auth'), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    await _tap(t, 'Create account');
    expect(_screen('setup'), findsOneWidget);
    await _tap(t, 'Continue');
    expect(_screen('pair'), findsOneWidget);
    await _tap(t, 'Continue to calibration');
    expect(_screen('calibrate'), findsOneWidget);
    await _tap(t, 'Captured');
    expect(_screen('ready'), findsOneWidget);
    await _tap(t, 'Start talking');
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
    await _tap(t, 'Pair a new glove');
    expect(_screen('pair'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    await _tap(t, 'Calibrate');
    expect(_screen('calibrate'), findsOneWidget);
    router.go(AppRoutes.settings);
    await t.pumpAndSettle();
    await _tap(t, 'Sign out');
    expect(_screen('welcome'), findsOneWidget);
  });

  testWidgets('Arabic switches text and layout to RTL', (t) async {
    await _pumpApp(t, at: AppRoutes.welcome);
    expect(Directionality.of(t.element(_screen('welcome'))), TextDirection.ltr);
    await t.tap(find.byKey(const ValueKey('skeleton-lang')));
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

  testWidgets('screens slide in over 0.38 s', (t) async {
    await _pumpApp(t, at: AppRoutes.welcome);
    await t.tap(find.text('Get started'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final mid = t.widget<Opacity>(
      find.ancestor(of: _screen('auth'), matching: find.byType(Opacity)).first,
    );
    expect(mid.opacity, inExclusiveRange(0, 1));
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(_screen('auth'), findsOneWidget);
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
