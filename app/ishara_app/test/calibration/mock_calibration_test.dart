import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/features/calibration/application/calibration_controller.dart';
import 'package:ishara_app/features/calibration/presentation/calibrate_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import '../support/kit.dart';

/// Kit v3.2.3: a full calibration on the real mock glove (its
/// `calibration/open|fist|turn.csv`), through the real glove client and the
/// real Calibrate screen. It must pass as on a real glove: "Hand still"
/// during OPEN and FIST, real finger bars, a real TURN rotation.
void main() {
  for (final person in MockPerson.values) {
    testWidgets('person ${person.dir}: mock calibration passes', (t) async {
      final recs = <String, Recording>{};
      await t.runAsync(() async {
        final lib = MockLibrary(readAsset);
        for (final f in MockLibrary.baseFiles(person)) {
          recs[f] = await lib.load(f);
        }
      });
      final lib = MockLibrary(readAsset);
      recs.forEach(lib.seed);
      final glove = MockGlove(MockFeed(lib, person: person));
      final client = GloveClient(glove);
      addTearDown(client.dispose);
      client.connect(glove.device).ignore();
      await t.pump(const Duration(seconds: 2));
      expect(client.status.isConnected, isTrue);

      t.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final router = GoRouter(
        initialLocation: AppRoutes.calibrate,
        routes: [
          GoRoute(
            path: AppRoutes.calibrate,
            builder: (_, _) => const CalibrateScreen(),
          ),
          GoRoute(
            path: AppRoutes.ready,
            builder: (_, s) => Text('route:${s.uri}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            gloveSourceProvider.overrideWithValue(client),
            keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
          ],
          child: MaterialApp.router(
            theme: IsharaTheme.build(
              brightness: Brightness.dark,
              isArabic: false,
            ),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      final container = ProviderScope.containerOf(
        t.element(find.byType(CalibrateScreen)),
      );
      CalibrationController ctl() =>
          container.read(calibrationControllerProvider.notifier);
      CalibrationState state() => container.read(calibrationControllerProvider);

      Future<void> tapCapture() async {
        final cta = find.byKey(const ValueKey('cal-cta'));
        await t.ensureVisible(cta);
        await t.tap(cta);
        await t.pump();
      }

      // OPEN and FIST: "Hand still" through the whole capture, never
      // "Hand moving".
      for (final title in ['Open your hand', 'Make a fist']) {
        expect(find.text(title), findsOneWidget);
        await tapCapture();
        for (var ms = 100; ms < 2000; ms += 100) {
          await t.pump(const Duration(milliseconds: 100));
          if (ms < 300) continue; // the first frames fill the window
          expect(find.text('Hand still'), findsOneWidget, reason: '$title $ms');
          expect(find.text('Hand moving'), findsNothing, reason: '$title $ms');
        }
        await t.pump(const Duration(milliseconds: 300));
        expect(state().phase, StepPhase.captured, reason: title);
        expect(find.text('Captured'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 800)); // the 0.75 s pause
      }

      // After OPEN and FIST: real bars for all five fingers (no "—").
      expect(find.text('Turn your wrist'), findsOneWidget);
      expect(state().weakFingers, isEmpty);
      expect(ctl().hand.weakFingers, isEmpty);
      expect(ctl().hand.fingers, everyElement(isNotNull));
      expect(find.text('—'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d+%$')), findsNWidgets(5));

      // TURN: the rotation shows turn.csv's real ±42° sweep (the glove
      // needs 30° of range), read on every batch of samples.
      await tapCapture();
      final rotations = <double>[];
      void read() => rotations.add(ctl().hand.rotation!);
      ctl().samplesSeen.addListener(read);
      for (var ms = 0; ms < 3000; ms += 100) {
        await t.pump(const Duration(milliseconds: 100));
      }
      ctl().samplesSeen.removeListener(read);
      final lo = rotations.reduce((a, b) => a < b ? a : b);
      final hi = rotations.reduce((a, b) => a > b ? a : b);
      expect(lo, closeTo(-42, 3));
      expect(hi, closeTo(42, 3));
      expect(hi - lo, greaterThanOrEqualTo(30));

      // CAL SAVE with the person's #CAL, then Ready.
      await t.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 20 && state().phase != StepPhase.saved; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(state().phase, StepPhase.saved);
      expect(state().failure, isNull);
      expect(state().reason, isNull);
      expect(client.status.storedCalibration, StoredCalibration.present);
      await t.pump(const Duration(seconds: 2));
      expect(find.textContaining('route:/ready'), findsOneWidget);

      await client.disconnect();
      await t.pump(const Duration(seconds: 1));
    });
  }
}
