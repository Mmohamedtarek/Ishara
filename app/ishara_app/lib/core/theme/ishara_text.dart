import 'package:flutter/material.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';

/// Font families bundled in `assets/fonts` (see `app/tools/make_fonts.sh`).
abstract final class IsharaFonts {
  static const ui = 'Figtree';
  static const arabic = 'Cairo';
  static const display = 'BricolageGrotesque';
}

/// Named text styles of the prototype CSS.
///
/// English: body text is Figtree (falls back to Cairo), titles are Bricolage
/// Grotesque (CSS line 515). Arabic (`.stage[lang=ar]`): everything is Cairo,
/// letter-spacing 0, and the small labels are 0.5-1 px bigger and not upper
/// case (lines 156-164, 516). Big text (Settings, line 511) enlarges only the
/// conversation text.
@immutable
class IsharaText extends ThemeExtension<IsharaText> {
  const new _({
    required this.isArabic,
    required this.h1,
    required this.lead,
    required this.eyebrow,
    required this.section,
    required this.question,
    required this.topTitle,
    required this.topSubtitle,
    required this.brand,
    required this.button,
    required this.buttonSmall,
    required this.link,
    required this.rowTitle,
    required this.rowSubtitle,
    required this.rowValue,
    required this.chip,
    required this.tab,
    required this.message,
    required this.liveBox,
    required this.caption,
    required this.micSigns,
    required this.stat,
    required this.statLabel,
    required this.score,
  });

  factory build(
    IsharaColors c, {
    required bool isArabic,
    bool bigText = false,
  }) {
    final body = isArabic ? IsharaFonts.arabic : IsharaFonts.ui;
    final display = isArabic ? IsharaFonts.arabic : IsharaFonts.display;
    const fallback = [IsharaFonts.arabic];
    TextStyle s(
      double size,
      FontWeight w, {
      Color? color,
      double? height,
      double spacingEm = 0,
      String? family,
    }) => TextStyle(
      fontFamily: family ?? body,
      fontFamilyFallback: fallback,
      fontSize: size,
      fontWeight: w,
      color: color ?? c.ink,
      height: height,
      letterSpacing: isArabic ? 0 : spacingEm * size,
    );
    // Small upper-case labels: Arabic is bigger, no tracking (lines 156-164).
    double label(double en, double ar) => isArabic ? ar : en;
    return IsharaText._(
      isArabic: isArabic,
      h1: s(
        26,
        FontWeight.w800,
        height: 1.15,
        spacingEm: -.01,
        family: display,
      ),
      lead: s(14, FontWeight.w600, color: c.muted, height: 1.5),
      eyebrow: s(
        label(11.5, 12.5),
        FontWeight.w800,
        color: c.tealSoft,
        spacingEm: .06,
      ),
      section: s(
        label(11.5, 12.5),
        FontWeight.w800,
        color: c.muted,
        spacingEm: .04,
      ),
      question: s(
        label(11.5, 12),
        FontWeight.w800,
        color: c.muted,
        spacingEm: .04,
      ),
      topTitle: s(17, FontWeight.w900, family: display),
      topSubtitle: s(11.5, FontWeight.w700, color: c.muted, height: 1.3),
      brand: s(19, FontWeight.w900, spacingEm: -.01, family: display),
      button: s(16, FontWeight.w900),
      buttonSmall: s(14.5, FontWeight.w900),
      link: s(
        13,
        FontWeight.w800,
        color: c.sub,
      ).copyWith(decoration: TextDecoration.underline, decorationColor: c.ring),
      rowTitle: s(14.5, FontWeight.w900),
      rowSubtitle: s(12, FontWeight.w700, color: c.muted, height: 1.35),
      rowValue: s(12.5, FontWeight.w800, color: c.sub),
      chip: s(12.5, FontWeight.w800),
      tab: s(11.5, FontWeight.w800, color: c.muted),
      message: s(bigText ? 18 : 14.5, FontWeight.w600, height: 1.45),
      liveBox: s(bigText ? 21 : 18, FontWeight.w800, height: 1.3),
      caption: s(
        bigText ? 18 : 15,
        FontWeight.w900,
        color: Colors.white,
        height: 1.35,
      ),
      micSigns: s(bigText ? 22 : 19, FontWeight.w900, height: 1.3),
      stat: s(20, FontWeight.w900, family: display),
      statLabel: s(
        label(11, 12),
        FontWeight.w800,
        color: c.muted,
        spacingEm: .03,
      ),
      score: s(
        42,
        FontWeight.w900,
        height: 1,
        spacingEm: -.02,
        family: display,
      ),
    );
  }

  final bool isArabic;
  final TextStyle h1;
  final TextStyle lead;
  final TextStyle eyebrow;
  final TextStyle section;
  final TextStyle question;
  final TextStyle topTitle;
  final TextStyle topSubtitle;
  final TextStyle brand;
  final TextStyle button;
  final TextStyle buttonSmall;
  final TextStyle link;
  final TextStyle rowTitle;
  final TextStyle rowSubtitle;
  final TextStyle rowValue;
  final TextStyle chip;
  final TextStyle tab;
  final TextStyle message;
  final TextStyle liveBox;
  final TextStyle caption;
  final TextStyle micSigns;
  final TextStyle stat;
  final TextStyle statLabel;
  final TextStyle score;

  /// The prototype upper-cases small labels in English only.
  String caps(String text) => isArabic ? text : text.toUpperCase();

  @override
  IsharaText copyWith() => this;

  @override
  IsharaText lerp(IsharaText? other, double t) =>
      other == null || t < .5 ? this : other;
}
