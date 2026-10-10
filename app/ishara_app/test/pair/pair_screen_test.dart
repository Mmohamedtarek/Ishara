import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/features/pair/presentation/pair_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import '../support/fake_glove.dart';

Future<FakeGloveSource> pumpPair(
  WidgetTester t, {
  FakeGloveSource? glove,
  FakeGlovePermissions? perms,
}) async {
  final g = glove ?? FakeGloveSource();
  addTearDown(g.dispose);
  // a phone screen (390 × 844 dp)
  t.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        gloveSourceProvider.overrideWithValue(g),
        glovePermissionsProvider.overrideWithValue(
          perms ?? FakeGlovePermissions(),
        ),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
      child: MaterialApp(
        theme: IsharaTheme.build(brightness: Brightness.dark, isArabic: false),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const PairScreen(),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return g;
}

/// Lets the screen's async work finish: frames, plus a little real time
/// (some futures, e.g. from stream cancellation, complete on the real event
/// loop, not on the test's fake clock).
Future<void> run(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('found → connect → connected, real name, signal, battery, '
      'firmware', (t) async {
    final g = await pumpPair(t);
    expect(find.text('Found your glove'), findsOneWidget);
    expect(find.text('Ishara-3FA2'), findsOneWidget);
    expect(find.text('Strong signal · -55 dBm'), findsOneWidget);
    final cta = find.byKey(const ValueKey('pair-cta'));
    expect(
      find.descendant(of: cta, matching: find.text('Tap Connect above')),
      findsOneWidget,
    );
    await t.ensureVisible(find.byKey(const ValueKey('pair-connect-g1')));
    await t.tap(find.byKey(const ValueKey('pair-connect-g1')));
    await run(t);
    expect(g.commands, ['scan', 'connect g1']);
    expect(find.byKey(const ValueKey('pair-status')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('pair-status'))).data,
      'Connected',
    );
    expect(find.text('Battery 78% · Firmware 0.3.0'), findsOneWidget);
    expect(find.text('Checking the sensors'), findsOneWidget);
    expect(
      find.descendant(of: cta, matching: find.text('Continue to calibration')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pair-scan-again')), findsOneWidget);
  });

  testWidgets('not found shows the tips (S6-3 drafts)', (t) async {
    await pumpPair(t, glove: FakeGloveSource(found: const []));
    expect(find.text('No glove found'), findsOneWidget);
    expect(find.byKey(const ValueKey('pair-tips')), findsOneWidget);
    expect(find.textContaining('another phone'), findsOneWidget);
  });

  testWidgets('permission refused for good → Open settings', (t) async {
    final perms = FakeGlovePermissions(
      answer: GlovePermission.permanentlyDenied,
    );
    await pumpPair(t, perms: perms);
    expect(find.text('Bluetooth permission needed'), findsOneWidget);
    await t.ensureVisible(find.text('Open settings'));
    await t.tap(find.text('Open settings'));
    await run(t);
    expect(perms.settingsOpened, 1);
  });

  testWidgets('Bluetooth off', (t) async {
    final g = FakeGloveSource()
      ..scanError = const BluetoothUnavailableFailure(BluetoothProblem.off);
    await pumpPair(t, glove: g);
    expect(find.text('Bluetooth is off'), findsOneWidget);
  });

  testWidgets('motion sensor problem fails check 2 with Try again', (t) async {
    final g = FakeGloveSource()..mpuFail = true;
    await pumpPair(t, glove: g);
    await t.ensureVisible(find.byKey(const ValueKey('pair-connect-g1')));
    await t.tap(find.byKey(const ValueKey('pair-connect-g1')));
    await run(t);
    expect(
      find.text("The glove's motion sensor isn't responding"),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pair-try-again')), findsOneWidget);
  });

  testWidgets('back from settings with the permission granted: scans', (
    t,
  ) async {
    final perms = FakeGlovePermissions(
      answer: GlovePermission.permanentlyDenied,
    );
    final g = await pumpPair(t, perms: perms);
    expect(find.text('Bluetooth permission needed'), findsOneWidget);
    perms.answer = GlovePermission.granted;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await run(t);
    expect(find.text('Found your glove'), findsOneWidget);
    expect(g.commands, ['scan']);
  });
}
