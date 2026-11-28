// Release v1.0 (DECISIONS R1-4): a user without a glove gets in.
//   "I speak": Setup's Continue finishes onboarding and opens Talk.
//   "I sign": Pair has "Skip for now" in every state but connected; it
//   finishes onboarding and opens Talk, and nothing about the glove is saved.
//   Connected: Pair → Calibrate as before, calibration skip only with a
//   stored #CAL (Q-K6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/settings_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/pair/presentation/pair_screen.dart';

import '../support/fake_glove.dart';
import '../support/fake_talk.dart';

const _skip = ValueKey<String>('pair-skip');
const _hint = ValueKey<String>('pair-skip-hint');

/// The real app from [at] with the fakes; returns the store it saves to.
Future<MemoryKeyValueStore> _pumpApp(
  WidgetTester t, {
  required FakeGloveSource glove,
  FakeGlovePermissions? perms,
  String at = AppRoutes.setup,
  Map<String, Object>? saved,
}) async {
  final store = MemoryKeyValueStore(saved);
  final router = buildRouter(initialLocation: at);
  addTearDown(router.dispose);
  addTearDown(glove.dispose);
  t.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        gloveSourceProvider.overrideWithValue(glove),
        glovePermissionsProvider.overrideWithValue(
          perms ?? FakeGlovePermissions(),
        ),
        keyValueStoreProvider.overrideWithValue(store),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(delay: Duration.zero),
        ),
        ...TalkFakes().overrides,
      ],
      child: const IsharaApp(),
    ),
  );
  await _run(t);
  return store;
}

/// Frames plus a little real time (stream clean-up runs on the real loop).
Future<void> _run(WidgetTester t, {int n = 10}) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

Finder _screen(String key) => find.byKey(ValueKey('screen-$key'));

/// Onboarding done, and nothing about a glove on the phone.
void _expectDoneWithoutGlove(MemoryKeyValueStore store) {
  final saved = OnboardingStore(store);
  expect(saved.done, isTrue);
  expect(saved.glove, isNull);
  expect(store.read(OnboardingStore.kGloveId), isNull);
  expect(store.read(OnboardingStore.kGloveName), isNull);
}

void main() {
  testWidgets('I speak: Continue opens Talk, no Pair, no Calibrate', (t) async {
    final glove = FakeGloveSource();
    final store = await _pumpApp(t, glove: glove);
    expect(_screen('setup'), findsOneWidget);
    await _tapKey(t, 'setup-who-speak');
    await _run(t, n: 2);
    await _tapKey(t, 'setup-continue');
    await _run(t);
    expect(_screen('talk'), findsOneWidget);
    expect(_screen('pair'), findsNothing);
    expect(_screen('calibrate'), findsNothing);
    expect(OnboardingStore(store).role, UserRole.speak);
    _expectDoneWithoutGlove(store);
    // the glove was never searched for
    expect(glove.commands, isEmpty);
    // Talk is the app's start from now on, not onboarding: no way back
    final router = GoRouter.of(t.element(_screen('talk')));
    expect(router.canPop(), isFalse);
  });

  testWidgets('I sign: Pair, Skip for now, Talk; nothing about the glove '
      'saved', (t) async {
    final glove = FakeGloveSource();
    final store = await _pumpApp(t, glove: glove);
    await _tapKey(t, 'setup-who-sign');
    await _run(t, n: 2);
    await _tapKey(t, 'setup-continue');
    await _run(t);
    expect(_screen('pair'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
    expect(
      find.text('You can pair your glove later in Settings.'),
      findsOneWidget,
    );
    await _tapKey(t, 'pair-skip');
    await _run(t);
    expect(_screen('talk'), findsOneWidget);
    expect(OnboardingStore(store).role, UserRole.sign);
    _expectDoneWithoutGlove(store);
    expect(glove.commands, ['scan']);
    // Talk offers pairing later ("Glove not connected" → Connect → Pair)
    expect(find.byKey(const ValueKey('talk-live-action')), findsOneWidget);
    await _tapKey(t, 'talk-live-action');
    await _run(t);
    expect(_screen('pair'), findsOneWidget);
    // after onboarding Pair has no skip
    expect(find.byKey(_skip), findsNothing);
  });

  testWidgets('I sign: connect, then Calibrate as before (no skip once '
      'connected; calibration skip with a stored #CAL, Q-K6)', (t) async {
    final glove = FakeGloveSource();
    final store = await _pumpApp(t, glove: glove);
    await _tapKey(t, 'setup-continue'); // the default role: I sign
    await _run(t);
    expect(_screen('pair'), findsOneWidget);
    await _tapKey(t, 'pair-connect-g1');
    await _run(t);
    expect(find.text('Continue to calibration'), findsOneWidget);
    expect(find.byKey(_skip), findsNothing);
    expect(find.byKey(_hint), findsNothing);
    await _tapKey(t, 'pair-cta');
    await _run(t);
    expect(_screen('calibrate'), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-skip')), findsOneWidget);
    expect(OnboardingStore(store).done, isFalse);
    expect(OnboardingStore(store).glove?.id, 'g1');
  });

  testWidgets('connected without a stored #CAL: calibration has no skip '
      '(Q-K6 unchanged)', (t) async {
    final glove = FakeGloveSource(stored: false);
    await _pumpApp(t, glove: glove, at: AppRoutes.pair);
    await _tapKey(t, 'pair-connect-g1');
    await _run(t);
    expect(find.byKey(_skip), findsNothing);
    await _tapKey(t, 'pair-cta');
    await _run(t);
    expect(_screen('calibrate'), findsOneWidget);
    expect(find.byKey(const ValueKey('cal-skip')), findsNothing);
    expect(find.byKey(const ValueKey('cal-skip-hidden')), findsOneWidget);
  });

  group('Skip for now in every state but connected', () {
    Future<void> expectSkip(
      WidgetTester t,
      FakeGloveSource glove, {
      required String state,
      FakeGlovePermissions? perms,
    }) async {
      final store = await _pumpApp(
        t,
        glove: glove,
        perms: perms,
        at: AppRoutes.pair,
      );
      expect(find.byKey(ValueKey(state)), findsOneWidget, reason: state);
      expect(find.byKey(_skip), findsOneWidget, reason: state);
      expect(find.byKey(_hint), findsOneWidget, reason: state);
      await _tapKey(t, 'pair-skip');
      await _run(t);
      expect(_screen('talk'), findsOneWidget, reason: state);
      _expectDoneWithoutGlove(store);
    }

    testWidgets('permission denied', (t) async {
      await expectSkip(
        t,
        FakeGloveSource(),
        perms: FakeGlovePermissions(answer: GlovePermission.denied),
        state: 'pair-permission',
      );
    });

    testWidgets('permission denied for good', (t) async {
      await expectSkip(
        t,
        FakeGloveSource(),
        perms: FakeGlovePermissions(answer: GlovePermission.permanentlyDenied),
        state: 'pair-permission',
      );
    });

    testWidgets('Bluetooth off', (t) async {
      await expectSkip(
        t,
        FakeGloveSource()
          ..scanError = const BluetoothUnavailableFailure(BluetoothProblem.off),
        state: 'pair-bluetooth',
      );
    });

    testWidgets('location off', (t) async {
      await expectSkip(
        t,
        FakeGloveSource()
          ..scanError = const BluetoothUnavailableFailure(
            BluetoothProblem.locationOff,
          ),
        state: 'pair-bluetooth',
      );
    });

    testWidgets('no glove found', (t) async {
      await expectSkip(t, FakeGloveSource(found: const []), state: 'pair-tips');
    });

    testWidgets('found', (t) async {
      await expectSkip(t, FakeGloveSource(), state: 'pair-connect-g1');
    });

    testWidgets('the checks failed', (t) async {
      final glove = FakeGloveSource()..mpuFail = true;
      final store = await _pumpApp(t, glove: glove, at: AppRoutes.pair);
      await _tapKey(t, 'pair-connect-g1');
      await _run(t);
      expect(find.byKey(const ValueKey('pair-failed')), findsOneWidget);
      expect(find.byKey(_skip), findsOneWidget);
      await _tapKey(t, 'pair-skip');
      await _run(t);
      expect(_screen('talk'), findsOneWidget);
      _expectDoneWithoutGlove(store);
    });

    testWidgets('while connecting: the connect is stopped and the glove is '
        'not saved, even when the connect still finishes', (t) async {
      // this fake ignores the disconnect and still reaches "ready"
      final glove = FakeGloveSource()
        ..connectTime = const Duration(milliseconds: 300);
      final store = await _pumpApp(t, glove: glove, at: AppRoutes.pair);
      await _tapKey(t, 'pair-connect-g1');
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(_skip), findsOneWidget);
      await _tapKey(t, 'pair-skip');
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1200)),
      );
      await _run(t, n: 12);
      expect(_screen('talk'), findsOneWidget);
      expect(glove.commands, containsAllInOrder(['connect g1', 'disconnect']));
      _expectDoneWithoutGlove(store);
    });
  });

  group('no skip outside onboarding', () {
    testWidgets('onboarding done (Pair from Settings or Talk)', (t) async {
      await _pumpApp(
        t,
        glove: FakeGloveSource(found: const []),
        at: AppRoutes.pair,
        saved: {OnboardingStore.kDone: true},
      );
      expect(find.byType(PairScreen), findsOneWidget);
      expect(find.byKey(_skip), findsNothing);
      expect(find.byKey(_hint), findsNothing);
    });

    testWidgets('from a practice step (back)', (t) async {
      await _pumpApp(
        t,
        glove: FakeGloveSource(found: const []),
        at: AppRoutes.pairBack(1),
      );
      expect(find.byType(PairScreen), findsOneWidget);
      expect(find.byKey(_skip), findsNothing);
    });
  });

  testWidgets('Arabic texts', (t) async {
    await _pumpApp(
      t,
      glove: FakeGloveSource(found: const []),
      at: AppRoutes.pair,
      saved: {SettingsStore.kLanguage: 'ar'},
    );
    expect(find.text('تخطّى دلوقتي'), findsOneWidget);
    expect(
      find.text('تقدر توصّل الجوانتي بعدين من الإعدادات.'),
      findsOneWidget,
    );
  });
}
