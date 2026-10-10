// On the emulator, with the mock glove (debug build default):
//   flutter test integration_test/onboarding_test.dart -d emulator-5554
// For the review video, paced (pause on each screen, in ms):
//   flutter test integration_test/onboarding_test.dart -d emulator-5554 \
//     --plain-name guest --dart-define=PACE_MS=1500
// The whole onboarding on the real app and the real mock glove (its scan,
// the three pairing checks, CAL OPEN / FIST / TURN / SAVE at their real
// lengths), with the phone's own key-value store. Prints ONBOARDING lines
// for the step record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

/// Pause on each screen (0 in normal runs).
final _pace = Duration(
  milliseconds: int.parse(
    const String.fromEnvironment('PACE_MS', defaultValue: '0'),
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Keeps frames coming for [d] (the screen stays live on video).
  Future<void> linger(WidgetTester t, [Duration? d]) async {
    final end = DateTime.now().add(d ?? _pace);
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> waitFor(
    WidgetTester t,
    Finder f, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final end = DateTime.now().add(timeout);
    while (f.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw TimeoutException('not found: $f');
      }
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(ValueKey(key));
    await waitFor(t, f);
    await t.ensureVisible(f);
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(f);
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('onboarding: account, setup, pair, calibrate, ready, talk', (
    t,
  ) async {
    final store = await SharedPrefsKeyValueStore.open();
    await OnboardingStore(store).clear();
    await OnboardingStore(store).forgetGlove();
    final sw = Stopwatch()..start();
    void mark(String what) =>
        debugPrint('ONBOARDING ${sw.elapsedMilliseconds} ms $what');

    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.welcome),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    await tapKey(t, 'welcome-get-started');
    mark('auth');
    for (final (key, text) in [
      ('auth-name', 'Mona'),
      ('auth-email', 'mona@example.com'),
      ('auth-password', 'secret123'),
    ]) {
      await t.enterText(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextField),
        ),
        text,
      );
    }
    await tapKey(t, 'auth-submit');
    await waitFor(t, find.byKey(const ValueKey('screen-setup')));
    mark('setup');
    await tapKey(t, 'setup-who-speak');
    await tapKey(t, 'setup-voice-en');
    await tapKey(t, 'setup-continue');
    await waitFor(t, find.byKey(const ValueKey('screen-pair')));
    mark('pair: scanning');
    final connect = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('pair-connect-'),
    );
    await waitFor(t, connect);
    mark('pair: found');
    await t.ensureVisible(connect);
    await t.tap(connect);
    await waitFor(t, find.text('Continue to calibration'));
    mark('pair: connected (3 checks)');
    await tapKey(t, 'pair-cta');
    await waitFor(t, find.byKey(const ValueKey('screen-calibrate')));
    mark('calibrate');
    for (final step in ['Make a fist', 'Turn your wrist']) {
      await tapKey(t, 'cal-cta');
      await waitFor(t, find.text(step));
      mark('calibrate: next $step');
    }
    await tapKey(t, 'cal-cta');
    await waitFor(t, find.byKey(const ValueKey('screen-ready')));
    mark('ready');
    expect(find.text("You're all set"), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await tapKey(t, 'ready-talk');
    await waitFor(t, find.byKey(const ValueKey('skeleton-talk')));
    mark('talk');

    final saved = OnboardingStore(store);
    expect(saved.done, isTrue);
    expect(saved.role, UserRole.speak);
    expect(saved.glove?.name, startsWith('Ishara-'));
    mark('saved: ${saved.export()}');
  });

  testWidgets('guest: splash, welcome, login, setup, pair, calibrate, '
      'ready, talk', (t) async {
    final store = await SharedPrefsKeyValueStore.open();
    await OnboardingStore(store).clear();
    await OnboardingStore(store).forgetGlove();
    // the real start: splash, then Welcome (onboarding not done)
    await t.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const IsharaApp(),
      ),
    );
    await waitFor(t, find.byKey(const ValueKey('welcome-sign-in')));
    await linger(t, _pace * 2); // the greeting plays
    await tapKey(t, 'welcome-sign-in');
    await waitFor(t, find.byKey(const ValueKey('auth-submit')));
    await linger(t);
    await tapKey(t, 'auth-guest');
    await waitFor(t, find.byKey(const ValueKey('screen-setup')));
    await linger(t);
    await tapKey(t, 'setup-who-speak');
    await linger(t, _pace ~/ 2);
    await tapKey(t, 'setup-voice-en');
    await linger(t, _pace ~/ 2);
    await tapKey(t, 'setup-continue');
    await waitFor(t, find.byKey(const ValueKey('screen-pair')));
    final connect = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('pair-connect-'),
    );
    await waitFor(t, connect);
    await linger(t);
    await t.ensureVisible(connect);
    await t.tap(connect);
    await waitFor(t, find.text('Continue to calibration'));
    await linger(t);
    await tapKey(t, 'pair-cta');
    await waitFor(t, find.byKey(const ValueKey('screen-calibrate')));
    await linger(t);
    for (final step in ['Make a fist', 'Turn your wrist']) {
      await tapKey(t, 'cal-cta');
      await waitFor(t, find.text(step));
      await linger(t);
    }
    await tapKey(t, 'cal-cta');
    await waitFor(t, find.byKey(const ValueKey('screen-ready')));
    await linger(t, _pace * 2);
    await tapKey(t, 'ready-talk');
    await waitFor(t, find.byKey(const ValueKey('skeleton-talk')));
    await linger(t);

    final saved = OnboardingStore(store);
    expect(saved.done, isTrue);
    expect(saved.role, UserRole.speak);
    expect(saved.glove?.name, startsWith('Ishara-'));
    debugPrint('ONBOARDING guest saved: ${saved.export()}');
  });
}
