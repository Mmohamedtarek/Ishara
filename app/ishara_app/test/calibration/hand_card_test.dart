import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/features/calibration/presentation/calibrate_widgets.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// TURN: the drawing turns at most ±33° (the prototype's maximum); the
/// number keeps showing the real angle.
void main() {
  Future<void> pump(WidgetTester t, double rotation) => t.pumpWidget(
    MaterialApp(
      theme: IsharaTheme.build(brightness: Brightness.light, isArabic: false),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: HandCard(
          bend: const [0, 0, 0, 0, 0],
          bars: null,
          still: null,
          rotation: rotation,
          turning: true,
          live: false,
        ),
      ),
    ),
  );

  double drawnDeg(WidgetTester t) {
    final rotate = t.widget<Transform>(
      find
          .descendant(
            of: find.byType(HandCard),
            matching: find.byType(Transform),
          )
          .first,
    );
    // rotation about z: m[0] = cos, m[1] = sin
    final m = rotate.transform.storage;
    return math.atan2(m[1], m[0]) * 180 / math.pi;
  }

  for (final (real, drawn, shown) in [
    (20.0, 20.0, '+20°'),
    (42.0, 33.0, '+42°'),
    (-42.0, -33.0, '-42°'),
  ]) {
    testWidgets('$real° drawn as $drawn°, shown as $shown', (t) async {
      await pump(t, real);
      expect(drawnDeg(t), closeTo(drawn, 1e-6));
      expect(find.text(shown), findsOneWidget);
    });
  }
}
