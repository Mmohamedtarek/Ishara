import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/theme/ishara_text.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';

void main() {
  ThemeData build({
    Brightness b = Brightness.light,
    bool ar = false,
    bool hc = false,
    bool big = false,
  }) => IsharaTheme.build(
    brightness: b,
    isArabic: ar,
    highContrast: hc,
    bigText: big,
  );

  test('light and dark use their prototype tokens', () {
    final l = build();
    final d = build(b: Brightness.dark);
    expect(l.extension<IsharaColors>()!.bg, IsharaColors.light.bg);
    expect(d.extension<IsharaColors>()!.bg, IsharaColors.dark.bg);
    expect(l.scaffoldBackgroundColor, IsharaColors.light.bg);
    expect(d.colorScheme.primary, IsharaColors.dark.teal);
    expect(d.colorScheme.brightness, Brightness.dark);
    expect(l.useMaterial3, isTrue);
  });

  test('English: Figtree body, Bricolage titles, tracked caps labels', () {
    final t = build().extension<IsharaText>()!;
    expect(t.lead.fontFamily, IsharaFonts.ui);
    expect(t.h1.fontFamily, IsharaFonts.display);
    expect(t.h1.fontSize, 26);
    expect(t.h1.fontWeight, FontWeight.w800);
    expect(t.h1.letterSpacing, closeTo(-.26, 1e-9));
    expect(t.eyebrow.fontSize, 11.5);
    expect(t.eyebrow.letterSpacing, closeTo(.69, 1e-9));
    expect(t.caps('Step 1'), 'STEP 1');
    expect(t.lead.fontFamilyFallback, [IsharaFonts.arabic]);
  });

  test('Arabic: Cairo everywhere, no tracking, bigger labels, no caps', () {
    final t = build(ar: true).extension<IsharaText>()!;
    for (final s in [t.h1, t.lead, t.topTitle, t.stat, t.score, t.brand]) {
      expect(s.fontFamily, IsharaFonts.arabic);
      expect(s.letterSpacing, 0);
    }
    expect(t.eyebrow.fontSize, 12.5);
    expect(t.section.fontSize, 12.5);
    expect(t.question.fontSize, 12);
    expect(t.statLabel.fontSize, 12);
    expect(t.caps('خطوة'), 'خطوة');
    expect(build(ar: true).textTheme.headlineMedium!.fontFamily, 'Cairo');
  });

  test('big text enlarges only the conversation text (CSS line 511)', () {
    final n = build().extension<IsharaText>()!;
    final b = build(big: true).extension<IsharaText>()!;
    expect([n.message.fontSize, b.message.fontSize], [14.5, 18]);
    expect([n.liveBox.fontSize, b.liveBox.fontSize], [18, 21]);
    expect([n.caption.fontSize, b.caption.fontSize], [15, 18]);
    expect([n.micSigns.fontSize, b.micSigns.fontSize], [19, 22]);
    expect(b.h1.fontSize, n.h1.fontSize);
    expect(b.lead.fontSize, n.lead.fontSize);
  });

  test('high contrast swaps muted and line', () {
    final c = build(b: Brightness.dark, hc: true).extension<IsharaColors>()!;
    expect(c.muted, IsharaColors.dark.sub);
    expect(c.line, IsharaColors.dark.ring);
    expect(c.borderWidth, 2);
  });

  test('text extension lerp snaps and copyWith keeps the styles', () {
    final a = build().extension<IsharaText>()!;
    final b = build(ar: true).extension<IsharaText>()!;
    expect(a.lerp(b, .2), same(a));
    expect(a.lerp(b, .8), same(b));
    expect(a.lerp(null, .8), same(a));
    expect(a.copyWith(), same(a));
  });

  testWidgets('context.colors / context.text read the extensions', (t) async {
    late IsharaColors colors;
    late IsharaText text;
    await t.pumpWidget(
      MaterialApp(
        theme: build(b: Brightness.dark),
        home: Builder(
          builder: (context) {
            colors = context.colors;
            text = context.text;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(colors.bg, IsharaColors.dark.bg);
    expect(text.h1.color, IsharaColors.dark.ink);
  });
}
