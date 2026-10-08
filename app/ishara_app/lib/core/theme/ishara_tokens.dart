import 'package:flutter/material.dart';

/// Design tokens copied from the prototype CSS (`design/prototype.html`).
///
/// Dark values = `:root` (lines 11-21).
/// Light values = `.stage[data-theme=light]` (lines 22-32).
/// High contrast = `.stage.hc` (line 512): `--muted` becomes `--sub`,
/// `--line` becomes `--ring`, and card borders become 2 px.
@immutable
class IsharaColors extends ThemeExtension<IsharaColors> {
  const new({
    required this.bg,
    required this.bg2,
    required this.ink,
    required this.sub,
    required this.muted,
    required this.teal,
    required this.tealSoft,
    required this.violet,
    required this.violetSoft,
    required this.amber,
    required this.amberSoft,
    required this.danger,
    required this.ok,
    required this.okSoft,
    required this.glass,
    required this.glass2,
    required this.line,
    required this.stageA,
    required this.stageB,
    required this.stageC,
    required this.panel,
    required this.panelSoft,
    required this.bar,
    required this.bar2,
    required this.bar2s,
    required this.knob,
    required this.input,
    required this.hover,
    required this.shadow,
    required this.track,
    required this.ring,
    required this.primaryGradient,
    required this.onPrimary,
    required this.violetGradient,
    required this.borderWidth,
  });

  /// `:root` (dark).
  static const dark = IsharaColors(
    bg: Color(0xFF121318),
    bg2: Color(0xFF1B1D24),
    ink: Color(0xFFEDEEF2),
    sub: Color(0xFFC7CAD3),
    muted: Color(0xFFA3A8B4),
    teal: Color(0xFF8E9CFF),
    tealSoft: Color(0xFFB7C0FF),
    violet: Color(0xFF6F7CF0),
    violetSoft: Color(0xFFC9CFFF),
    amber: Color(0xFFF2A33A),
    amberSoft: Color(0xFFF7C987),
    danger: Color(0xFFF06E76),
    ok: Color(0xFF4ABE84),
    okSoft: Color(0xFF9FE0BD),
    glass: Color(0x0DFFFFFF), // rgba(255,255,255,.05)
    glass2: Color(0x14FFFFFF), // .08
    line: Color(0xFF2E323C),
    stageA: Color(0xFF4A4D57),
    stageB: Color(0xFF33363F),
    stageC: Color(0xFF24262D),
    panel: Color(0xF2121318), // rgba(18,19,24,.95)
    panelSoft: Color(0xDB1B1D24), // rgba(27,29,36,.86)
    bar: Color(0xF0121318), // rgba(18,19,24,.94)
    bar2: Color(0xFA1B1D24), // rgba(27,29,36,.98)
    bar2s: Color(0x991B1D24), // rgba(27,29,36,.6)
    knob: Color(0xFF0E1440),
    input: Color(0x0DFFFFFF), // .05
    hover: Color(0x1AFFFFFF), // .1
    shadow: Color(0x73000000), // rgba(0,0,0,.45)
    track: Color(0x1FFFFFFF), // .12
    ring: Color(0x52FFFFFF), // .32
    // .btn.primary: linear-gradient(135deg,#A9B3FF,#6F7CF0); color:#0E1440
    primaryGradient: [Color(0xFFA9B3FF), Color(0xFF6F7CF0)],
    onPrimary: Color(0xFF0E1440),
    // .btn.violet: linear-gradient(135deg,#C9CFFF,#6F7CF0)
    violetGradient: [Color(0xFFC9CFFF), Color(0xFF6F7CF0)],
    borderWidth: 1,
  );

  /// `.stage[data-theme=light]`.
  static const light = IsharaColors(
    bg: Color(0xFFF4F2EC),
    bg2: Color(0xFFFFFFFF),
    ink: Color(0xFF15171C),
    sub: Color(0xFF3B3F48),
    muted: Color(0xFF5B606B),
    teal: Color(0xFF3446C9),
    tealSoft: Color(0xFF24309A),
    violet: Color(0xFF24309A),
    violetSoft: Color(0xFF24309A),
    amber: Color(0xFFF2A33A),
    amberSoft: Color(0xFF8A4F00),
    danger: Color(0xFFC62B33),
    ok: Color(0xFF1F7A4D),
    okSoft: Color(0xFF1F7A4D),
    glass: Color(0xFFFFFFFF),
    glass2: Color(0xFFFBFAF7),
    line: Color(0xFFE3E0D8),
    stageA: Color(0xFFFBFAF7),
    stageB: Color(0xFFEFECE4),
    stageC: Color(0xFFDCD7CC),
    panel: Color(0xF7FFFFFF), // rgba(255,255,255,.97)
    panelSoft: Color(0xEBFFFFFF), // .92
    bar: Color(0xF5FFFFFF), // .96
    bar2: Color(0xFFFFFFFF),
    bar2s: Color(0xBFFFFFFF), // .75
    knob: Color(0xFFFFFFFF),
    input: Color(0xFFFFFFFF),
    hover: Color(0xFFEFECE4),
    shadow: Color(0x1415171C), // rgba(21,23,28,.08)
    track: Color(0x1A15171C), // .10
    ring: Color(0x4D15171C), // .30
    // light .btn.primary: linear-gradient(135deg,#4B5BD6,#3446C9); color:#fff
    primaryGradient: [Color(0xFF4B5BD6), Color(0xFF3446C9)],
    onPrimary: Color(0xFFFFFFFF),
    // light .btn.violet: linear-gradient(135deg,#3446C9,#24309A)
    violetGradient: [Color(0xFF3446C9), Color(0xFF24309A)],
    borderWidth: 1,
  );

  final Color bg;
  final Color bg2;
  final Color ink;
  final Color sub;
  final Color muted;
  final Color teal;
  final Color tealSoft;
  final Color violet;
  final Color violetSoft;
  final Color amber;
  final Color amberSoft;
  final Color danger;
  final Color ok;
  final Color okSoft;
  final Color glass;
  final Color glass2;
  final Color line;
  final Color stageA;
  final Color stageB;
  final Color stageC;
  final Color panel;
  final Color panelSoft;
  final Color bar;
  final Color bar2;
  final Color bar2s;
  final Color knob;
  final Color input;
  final Color hover;
  final Color shadow;
  final Color track;
  final Color ring;
  final List<Color> primaryGradient;
  final Color onPrimary;
  final List<Color> violetGradient;

  /// Border width of cards, rows, option cards, modules, tiles and messages.
  final double borderWidth;

  /// `.stage.hc`: muted text takes the `sub` colour, lines take the `ring`
  /// colour, and borders are 2 px.
  IsharaColors highContrast() =>
      copyWith(muted: sub, line: ring, borderWidth: 2);

  /// Brand mark: linear-gradient(135deg,#4B5BD6,#3446C9 55%,#24309A).
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4B5BD6), Color(0xFF3446C9), Color(0xFF24309A)],
    stops: [0, .55, 1],
  );

  LinearGradient get primary => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: primaryGradient,
  );

  LinearGradient get violetButton => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: violetGradient,
  );

  @override
  IsharaColors copyWith({
    Color? bg,
    Color? bg2,
    Color? ink,
    Color? sub,
    Color? muted,
    Color? teal,
    Color? tealSoft,
    Color? violet,
    Color? violetSoft,
    Color? amber,
    Color? amberSoft,
    Color? danger,
    Color? ok,
    Color? okSoft,
    Color? glass,
    Color? glass2,
    Color? line,
    Color? stageA,
    Color? stageB,
    Color? stageC,
    Color? panel,
    Color? panelSoft,
    Color? bar,
    Color? bar2,
    Color? bar2s,
    Color? knob,
    Color? input,
    Color? hover,
    Color? shadow,
    Color? track,
    Color? ring,
    List<Color>? primaryGradient,
    Color? onPrimary,
    List<Color>? violetGradient,
    double? borderWidth,
  }) => IsharaColors(
    bg: bg ?? this.bg,
    bg2: bg2 ?? this.bg2,
    ink: ink ?? this.ink,
    sub: sub ?? this.sub,
    muted: muted ?? this.muted,
    teal: teal ?? this.teal,
    tealSoft: tealSoft ?? this.tealSoft,
    violet: violet ?? this.violet,
    violetSoft: violetSoft ?? this.violetSoft,
    amber: amber ?? this.amber,
    amberSoft: amberSoft ?? this.amberSoft,
    danger: danger ?? this.danger,
    ok: ok ?? this.ok,
    okSoft: okSoft ?? this.okSoft,
    glass: glass ?? this.glass,
    glass2: glass2 ?? this.glass2,
    line: line ?? this.line,
    stageA: stageA ?? this.stageA,
    stageB: stageB ?? this.stageB,
    stageC: stageC ?? this.stageC,
    panel: panel ?? this.panel,
    panelSoft: panelSoft ?? this.panelSoft,
    bar: bar ?? this.bar,
    bar2: bar2 ?? this.bar2,
    bar2s: bar2s ?? this.bar2s,
    knob: knob ?? this.knob,
    input: input ?? this.input,
    hover: hover ?? this.hover,
    shadow: shadow ?? this.shadow,
    track: track ?? this.track,
    ring: ring ?? this.ring,
    primaryGradient: primaryGradient ?? this.primaryGradient,
    onPrimary: onPrimary ?? this.onPrimary,
    violetGradient: violetGradient ?? this.violetGradient,
    borderWidth: borderWidth ?? this.borderWidth,
  );

  /// Theme changes are instant in the prototype (no colour transition), so
  /// interpolation snaps at the midpoint.
  @override
  IsharaColors lerp(IsharaColors? other, double t) =>
      other == null || t < .5 ? this : other;
}

/// Corner radii used by the prototype components.
abstract final class IsharaRadii {
  static const double button = 18; // .btn
  static const double buttonSmall = 14; // .btn.sm
  static const double card = 20; // .card, .opt-card, .tile
  static const double row = 18; // .row, .guest, .live-box, .msg
  static const double field = 16; // .field .in, .seg
  static const double segButton = 12; // .seg button
  static const double module = 22; // .mod, .dev, .mic-card
  static const double avatar = 24; // #avatar, .handcard
  static const double iconTile = 12; // .row .ic
  static const double pill = 999;
}

/// Motion from the prototype CSS.
abstract final class IsharaMotion {
  /// `.screen { animation: slidein .38s cubic-bezier(.2,.8,.2,1) }`.
  static const Duration screen = Duration(milliseconds: 380);

  /// cubic-bezier(.2,.8,.2,1), used by every entrance animation.
  static const Curve ease = Cubic(.2, .8, .2, 1);

  /// `@keyframes slidein { from { translateX(22px) } }` (mirrored in RTL).
  static const double slideOffset = 22;

  /// `@keyframes popin { from { translateY(14px) scale(.98) } }`.
  static const double popOffset = 14;
  static const double popScale = .98;
}
