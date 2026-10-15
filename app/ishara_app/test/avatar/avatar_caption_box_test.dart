import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_card_parts.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

/// One avatar for every screen: when a screen with a caption is shown again,
/// it tells the avatar its caption height again (another screen's caption
/// may have reframed it meanwhile; review step 8).
void main() {
  testWidgets('reports its height again when its screen is shown again', (
    t,
  ) async {
    final heights = <double>[];
    Widget app({required bool shown}) => MaterialApp(
      theme: IsharaTheme.build(brightness: Brightness.dark, isArabic: false),
      home: TickerMode(
        enabled: shown,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AvatarCaptionBox(
            label: 'Watch Nour',
            onHeight: heights.add,
            child: const Text('Hello'),
          ),
        ),
      ),
    );
    await t.pumpWidget(app(shown: true));
    await t.pump();
    expect(heights, hasLength(1));
    await t.pumpWidget(app(shown: false));
    await t.pump();
    expect(heights, hasLength(1));
    await t.pumpWidget(app(shown: true));
    await t.pump();
    expect(heights, [heights.first, heights.first]);
  });
}
