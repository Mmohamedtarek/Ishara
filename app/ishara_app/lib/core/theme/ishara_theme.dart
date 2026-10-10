import 'package:flutter/material.dart';
import 'package:ishara_app/core/theme/ishara_text.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';

/// The one place the app's theme is built (Material 3 + prototype tokens).
abstract final class IsharaTheme {
  static ThemeData build({
    required Brightness brightness,
    required bool isArabic,
    bool highContrast = false,
    bool bigText = false,
  }) {
    var c = brightness == Brightness.dark
        ? IsharaColors.dark
        : IsharaColors.light;
    if (highContrast) c = c.highContrast();
    final text = IsharaText.build(c, isArabic: isArabic, bigText: bigText);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.teal,
      onPrimary: c.onPrimary,
      secondary: c.violet,
      onSecondary: c.onPrimary,
      tertiary: c.amber,
      onTertiary: const Color(0xFF3B2A00),
      error: c.danger,
      onError: Colors.white,
      surface: c.bg,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.bg2,
      surfaceContainer: c.bg2,
      surfaceContainerHigh: c.bg2,
      surfaceContainerHighest: c.bg2,
      outline: c.line,
      outlineVariant: c.line,
      shadow: c.shadow,
      inverseSurface: c.ink,
      onInverseSurface: c.bg,
    );
    final family = isArabic ? IsharaFonts.arabic : IsharaFonts.ui;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      fontFamily: family,
      fontFamilyFallback: const [IsharaFonts.arabic, IsharaFonts.ui],
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: _textTheme(text),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      extensions: [c, text],
    );
  }

  static TextTheme _textTheme(IsharaText t) => TextTheme(
    headlineMedium: t.h1,
    titleLarge: t.topTitle,
    titleMedium: t.rowTitle,
    bodyLarge: t.message,
    bodyMedium: t.lead.copyWith(color: t.rowTitle.color),
    bodySmall: t.rowSubtitle,
    labelLarge: t.button,
    labelMedium: t.chip,
    labelSmall: t.tab,
  );
}

/// Short access to the prototype tokens:
/// `context.colors.teal`, `context.text.h1`.
extension IsharaThemeContext on BuildContext {
  IsharaColors get colors => Theme.of(this).extension<IsharaColors>()!;
  IsharaText get text => Theme.of(this).extension<IsharaText>()!;
}
