import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/ishara_icon_data.dart';

Widget _host(Widget child, {TextDirection dir = TextDirection.ltr}) =>
    MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Center(child: child),
      ),
    );

void main() {
  test('all 53 prototype icons were ported, as valid SVG', () async {
    expect(isharaIconSvg, hasLength(53));
    for (final e in isharaIconSvg.entries) {
      expect(e.value, startsWith('<svg'), reason: e.key);
      expect(e.value, contains('currentColor'), reason: e.key);
    }
    expect(isharaIconSvg['arrow'], contains('stroke-width="2.6"'));
    expect(isharaIconSvg['gear'], contains('stroke-width="2"'));
    expect(isharaIconSvg['book'], contains('stroke-width="2.2"'));
  });

  testWidgets('every icon parses and renders', (t) async {
    for (final name in isharaIconSvg.keys) {
      await t.pumpWidget(_host(IsharaIcon(name)));
      await t.pump();
      expect(t.takeException(), isNull, reason: name);
    }
    final loader = SvgStringLoader(isharaIconSvg['logo']!);
    expect(await loader.loadBytes(null), isNotNull);
  });

  testWidgets('directional icons flip in RTL only', (t) async {
    for (final dir in TextDirection.values) {
      for (final name in ['arrow', 'back', 'chev', 'mic']) {
        await t.pumpWidget(_host(IsharaIcon(name), dir: dir));
        final flipped = find.descendant(
          of: find.byType(IsharaIcon),
          matching: find.byType(Transform),
        );
        final shouldFlip =
            dir == TextDirection.rtl && IsharaIcon.directional.contains(name);
        expect(
          flipped,
          shouldFlip ? findsOneWidget : findsNothing,
          reason: '$name $dir',
        );
      }
    }
  });

  testWidgets('semantics: decorative unless labelled', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_host(const IsharaIcon('mic', semanticLabel: 'Speak')));
    expect(find.bySemanticsLabel('Speak'), findsOneWidget);
    await t.pumpWidget(_host(const IsharaIcon('mic')));
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    h.dispose();
  });
}
