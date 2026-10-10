import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/theme/ishara_text.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/ishara_mark.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

// Shared pieces of the onboarding screens (Welcome, Login, Setup, Pair,
// Calibrate, Ready), each from the prototype's CSS (the rule is named on the
// class).

bool _dark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// A screen of the onboarding flow: top bar, scrolling body (`.screen .body`
/// padding 4 18 14), CTA bar.
class OnboardingPage extends StatelessWidget {
  const new({
    required this.screenKey,
    required this.top,
    required this.body,
    this.cta,
    super.key,
  });

  /// `screen-<key>` for tests and screenshots.
  final String screenKey;
  final Widget top;
  final List<Widget> body;
  final Widget? cta;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey('screen-$screenKey'),
    backgroundColor: context.colors.bg,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          top,
          // Short pages: everything is built (screen readers can reach it).
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
          ?cta,
        ],
      ),
    ),
  );
}

/// `.top` (padding 12 16 8, min height 64, gap 10).
class OnboardingTopBar extends StatelessWidget {
  const new({
    this.back = false,
    this.brand = false,
    this.step,
    this.onBack,
    super.key,
  });

  /// Shows the back button (`data-back`).
  final bool back;

  /// Shows the brand (mark + "Ishara").
  final bool brand;

  /// The 3-step header (`.steps`): 0 Setup, 1 Glove, 2 Calibrate.
  final int? step;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            if (back) ...[
              IconCircleButton(
                key: const ValueKey('top-back'),
                icon: 'back',
                label: l.back,
                onPressed: onBack ?? () => context.pop(),
              ),
              const SizedBox(width: 10),
            ],
            if (brand) ...[const _Brand(), const SizedBox(width: 10)],
            if (step case final s?)
              Expanded(child: StepsHeader(current: s))
            else
              const Spacer(),
            const SizedBox(width: 10),
            const LangToggle(),
          ],
        ),
      ),
    );
  }
}

/// `.brand` (mark 32 px + "Ishara", 19 px w900).
class _Brand extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const IsharaMark.header(),
      const SizedBox(width: 9),
      Text('Ishara', style: context.text.brand.copyWith(fontSize: 19)),
    ],
  );
}

/// `.icon-btn` (44 px touch size, glass, line border).
class IconCircleButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: c.glass,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Center(child: IsharaIcon(icon, color: c.sub)),
          ),
        ),
      ),
    );
  }
}

/// `.lang`: the EN / ع toggle (76 × 40 touch size, sliding knob).
class LangToggle extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dark = _dark(context);
    final arabic =
        ref.watch(appSettingsControllerProvider).language == AppLanguage.ar;
    final knob = dark
        ? const LinearGradient(colors: [Color(0xFFA9B3FF), Color(0xFF6F7CF0)])
        : const LinearGradient(colors: [Color(0xFF4B5BD6), Color(0xFF3446C9)]);
    final glow = dark ? const Color(0x998E9CFF) : const Color(0x663446C9);
    final onKnob = dark ? const Color(0xFF0E1440) : Colors.white;
    Widget opt(String text, {required bool on, required bool cairo}) =>
        Expanded(
          child: Center(
            child: Text(
              text,
              style: context.text.chip.copyWith(
                fontSize: cairo ? 14 : 12,
                fontWeight: FontWeight.w900,
                height: 1,
                fontFamily: cairo ? IsharaFonts.arabic : null,
                color: on ? onKnob : c.muted,
              ),
            ),
          ),
        );
    return Semantics(
      key: const ValueKey('lang-toggle'),
      button: true,
      label: 'Switch language / تغيير اللغة',
      excludeSemantics: true,
      onTap: () =>
          ref.read(appSettingsControllerProvider.notifier).toggleLanguage(),
      child: GestureDetector(
        onTap: () =>
            ref.read(appSettingsControllerProvider.notifier).toggleLanguage(),
        child: Container(
          width: 76,
          height: 40,
          decoration: ShapeDecoration(
            color: dark ? c.glass : const Color(0x0F15171C),
            shape: StadiumBorder(
              side: BorderSide(color: dark ? c.line : const Color(0x2415171C)),
            ),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 450),
                curve: IsharaMotion.ease,
                alignment: arabic
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Container(
                  width: 76 / 2 - 3,
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    gradient: knob,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: glow, blurRadius: 16)],
                  ),
                ),
              ),
              Row(
                children: [
                  opt('EN', on: !arabic, cairo: false),
                  opt('ع', on: arabic, cairo: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.steps`: Setup, Glove, Calibrate. Done steps show a check, the current
/// one glows.
class StepsHeader extends StatelessWidget {
  const new({required this.current, super.key});

  final int current;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = _dark(context);
    final labels = [l.stSetup, l.stPair, l.stCal];
    return Semantics(
      label: l.stepOfLabel(current + 1, labels[current]),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      // either the track or the fill, never both
                      color: i <= current
                          ? null
                          : dark
                          ? c.track
                          : const Color(0x1F15171C),
                      borderRadius: BorderRadius.circular(2),
                      gradient: i <= current
                          ? LinearGradient(colors: [c.teal, c.tealSoft])
                          : null,
                      boxShadow: i == current
                          ? const [
                              BoxShadow(
                                color: Color(0xCC8E9CFF),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (i < current) ...[
                        IsharaIcon('check', size: 11, color: c.sub),
                        const SizedBox(width: 3),
                      ],
                      Flexible(
                        child: Text(
                          labels[i].toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: context.text.eyebrow.copyWith(
                            fontSize: 10.5,
                            letterSpacing: .02 * 10.5,
                            color: i == current
                                ? c.tealSoft
                                : i < current
                                ? c.sub
                                : c.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Button kinds (`.btn.primary`, `.violet`, `.ghost`, `.ok`, `.counting`).
enum IsharaButtonKind { primary, violet, ghost, ok, counting }

/// `.btn` (54 px, radius 18, 16 px w900; `.sm` 46 px, radius 14, 14.5 px).
class IsharaButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.kind = IsharaButtonKind.primary,
    this.small = false,
    this.arrow = false,
    this.trailingIcon,
    this.leading,
    this.progress,
    this.busy = false,
    super.key,
  });

  final String label;

  /// Null = disabled (opacity .45, no shadow).
  final VoidCallback? onPressed;
  final IsharaButtonKind kind;
  final bool small;

  /// The trailing arrow icon (mirrored in RTL).
  final bool arrow;

  /// Another trailing prototype icon (e.g. `check` for "Captured ✓": the
  /// bundled fonts have no ✓ glyph).
  final String? trailingIcon;
  final Widget? leading;

  /// `.counting .ring`: fill from the start, 0…1.
  final double? progress;

  /// Shows a spinner instead of the arrow (a call is running).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final dark = _dark(context);
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(small ? 14 : 18);
    Gradient? gradient;
    Color? bg;
    Color fg;
    BoxBorder? border;
    List<BoxShadow>? shadow;
    switch (kind) {
      case IsharaButtonKind.primary:
        gradient = dark
            ? const LinearGradient(
                colors: [Color(0xFFA9B3FF), Color(0xFF6F7CF0)],
              )
            : const LinearGradient(
                colors: [Color(0xFF4B5BD6), Color(0xFF3446C9)],
              );
        fg = dark ? const Color(0xFF0E1440) : Colors.white;
        shadow = [
          if (dark)
            const BoxShadow(
              color: Color(0x598E9CFF),
              blurRadius: 30,
              offset: Offset(0, 12),
            )
          else
            const BoxShadow(
              color: Color(0x473446C9),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
        ];
      case IsharaButtonKind.violet:
        gradient = dark
            ? const LinearGradient(
                colors: [Color(0xFFC9CFFF), Color(0xFF6F7CF0)],
              )
            : const LinearGradient(
                colors: [Color(0xFF3446C9), Color(0xFF24309A)],
              );
        fg = dark ? const Color(0xFF0E1440) : Colors.white;
        shadow = const [
          BoxShadow(
            color: Color(0x666F7CF0),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ];
      case IsharaButtonKind.ghost:
        bg = c.glass;
        fg = c.ink;
        border = Border.all(color: c.line);
      case IsharaButtonKind.ok:
        bg = dark ? const Color(0x2E4ABE84) : const Color(0x1F1F7A4D);
        fg = c.okSoft;
        border = Border.all(
          color: dark ? const Color(0x994ABE84) : const Color(0x801F7A4D),
          width: 1.5,
        );
      case IsharaButtonKind.counting:
        bg = dark ? const Color(0x248E9CFF) : const Color(0x1A3446C9);
        fg = c.tealSoft;
        border = Border.all(
          color: dark ? const Color(0x80B7C0FF) : const Color(0x733446C9),
          width: 1.5,
        );
    }
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading case final w?) ...[w, const SizedBox(width: 9)],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: (small ? t.buttonSmall : t.button).copyWith(color: fg),
          ),
        ),
        if (busy) ...[
          const SizedBox(width: 9),
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          ),
        ] else if (arrow || trailingIcon != null) ...[
          const SizedBox(width: 9),
          IsharaIcon(trailingIcon ?? 'arrow', color: fg),
        ],
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            color: bg,
            borderRadius: radius,
            border: border,
            boxShadow: enabled ? shadow : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: onPressed,
              child: SizedBox(
                height: small ? 46 : 54,
                width: double.infinity,
                child: Stack(
                  alignment: AlignmentDirectional.center,
                  children: [
                    if (progress case final p?)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: p.clamp(0.0, 1.0),
                          child: ClipRRect(
                            borderRadius: radius,
                            child: const ColoredBox(color: Color(0x478E9CFF)),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: content,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.link` (13 px w800, underlined, padding 6 10; 48 px touch height).
class IsharaLink extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        foregroundColor: c.sub,
        overlayColor: c.hover,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: context.text.link.copyWith(
          color: c.sub,
          decoration: TextDecoration.underline,
          decorationColor: c.ring,
        ),
      ),
    );
  }
}

/// `.cta-bar`: padding 10 18 14 (+ safe area), the page background fading
/// in from the bottom, gap 8.
class CtaBar extends StatelessWidget {
  const new({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bg = context.colors.bg;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [bg, bg, bg.withValues(alpha: 0)],
          stops: const [0, .6, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, w) in children.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                w,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `h1` + `p.lead`.
class PageTitle extends StatelessWidget {
  const new(this.title, {this.lead, this.eyebrow, super.key});

  final String title;
  final String? lead;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow case final e?)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(e.toUpperCase(), style: t.eyebrow),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Semantics(header: true, child: Text(title, style: t.h1)),
        ),
        if (lead case final l?)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ConstrainedBox(
              // max-width: 36ch at 14 px
              constraints: const BoxConstraints(maxWidth: 36 * 8.2),
              child: Text(l, style: t.lead),
            ),
          ),
      ],
    );
  }
}

/// `.q`: a question label (11.5 px w800, uppercase, margin 6 0 8). Its top
/// margin collapses into the block above (14-16 px), as in CSS.
class QuestionLabel extends StatelessWidget {
  const new(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: context.text.question),
    ),
  );
}

/// `.opt-card` (radio card: icon tile, title + text, round check).
class OptCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.teal = false,
    super.key,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  /// `.ic.teal` instead of violet.
  final bool teal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final dark = _dark(context);
    final border = selected
        ? (dark ? const Color(0xB3B7C0FF) : const Color(0x803446C9))
        : c.line;
    final bg = selected
        ? (dark ? const Color(0x1A8E9CFF) : const Color(0x143446C9))
        : c.glass;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IsharaRadii.card),
          side: BorderSide(color: border, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(IsharaRadii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                IconTile(icon: icon, teal: teal, size: 44, radius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.rowTitle.copyWith(
                          fontSize: 15.5,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: t.rowSubtitle.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Radio(on: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.opt-card .rad` (24 px, 2 px ring; on: teal with a check).
class _Radio extends StatelessWidget {
  const new({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? c.teal : null,
        border: Border.all(color: on ? c.teal : c.ring, width: 2),
        boxShadow: on && dark
            ? const [BoxShadow(color: Color(0x998E9CFF), blurRadius: 14)]
            : null,
      ),
      child: on
          ? Center(
              child: IsharaIcon(
                'check',
                size: 14,
                color: dark ? const Color(0xFF0E1440) : Colors.white,
              ),
            )
          : null,
    );
  }
}

/// An icon on a tinted tile (`.row .ic`, `.opt-card .ic`, `.dev .ic`).
class IconTile extends StatelessWidget {
  const new({
    required this.icon,
    this.teal = false,
    this.tone,
    this.size = 38,
    this.radius = IsharaRadii.iconTile,
    this.iconSize,
    super.key,
  });

  final String icon;
  final bool teal;

  /// Overrides the tile colour: `amber` or `green`.
  final String? tone;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      'amber' => (const Color(0x29F2A33A), c.amberSoft),
      'green' => (const Color(0x294ABE84), c.okSoft),
      _ =>
        teal
            ? (const Color(0x248E9CFF), c.tealSoft)
            : (const Color(0x296F7CF0), c.violetSoft),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: IsharaIcon(icon, size: iconSize ?? size * .48, color: fg),
      ),
    );
  }
}

/// `.row` (glass, radius 18, padding 12 14): icon, title + subtitle, value.
class InfoRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.valueColor,
    this.teal = false,
    super.key,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final bool teal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(IsharaRadii.row),
        border: Border.all(color: c.line),
        boxShadow: _dark(context)
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0D15171C),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          IconTile(icon: icon, teal: teal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.rowTitle.copyWith(color: c.ink)),
                if (subtitle case final s?) ...[
                  const SizedBox(height: 1),
                  Text(s, style: t.rowSubtitle.copyWith(color: c.muted)),
                ],
              ],
            ),
          ),
          if (value case final v?) ...[
            const SizedBox(width: 12),
            Text(v, style: t.rowValue.copyWith(color: valueColor ?? c.sub)),
          ],
        ],
      ),
    );
  }
}

/// A problem card in the prototype's `.tips` style (glass, radius 20): a
/// title, an explanation and an optional action. Used for the states the
/// prototype lacks (Bluetooth off, permission refused, sensor problem…).
class NoticeCard extends StatelessWidget {
  const new({
    required this.title,
    required this.body,
    this.icon = 'info',
    this.tone,
    this.action,
    super.key,
  });

  final String title;
  final String body;
  final String icon;

  /// `amber` for problems the user must fix.
  final String? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.glass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: icon, tone: tone ?? 'amber', size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.rowTitle.copyWith(fontSize: 14, color: c.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: t.rowSubtitle.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: c.sub,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (action case final a?) ...[const SizedBox(height: 10), a],
          ],
        ),
      ),
    );
  }
}
