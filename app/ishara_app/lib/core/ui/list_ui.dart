import 'package:flutter/material.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';

// The prototype's list parts, shared by History, Settings and the Avatar
// studio: `.top .ttl`, `.sec`, `.row`, `.sw`, `.seg`, `.field .in`.

bool _dark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// `.top` with `.ttl` (17 px title, 11.5 px line under it) and [trailing].
class TitleBar extends StatelessWidget {
  const new({
    required this.title,
    this.lead,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final String? lead;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            if (leading case final w?) ...[w, const SizedBox(width: 10)],
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.topTitle.copyWith(color: c.ink),
                    ),
                    if (lead case final s?) ...[
                      const SizedBox(height: 1),
                      Text(s, style: t.topSubtitle),
                    ],
                  ],
                ),
              ),
            ),
            if (trailing case final w?) ...[const SizedBox(width: 10), w],
          ],
        ),
      ),
    );
  }
}

/// `.sec`: 11.5 px w800 muted, uppercase in English, margin 14 4 6.
class SectionLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(
          ar ? text : text.toUpperCase(),
          style: context.text.chip.copyWith(
            fontSize: ar ? 12.5 : 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: ar ? 0 : 11.5 * .04,
            color: context.colors.muted,
          ),
        ),
      ),
    );
  }
}

/// Icon tile tones (`.row .ic`, `.teal`, `.amber`, `.green`).
enum RowTone { violet, teal, amber, green }

/// `.row` (glass, radius 18, padding 12 14, gap 12): the icon tile, title
/// and subtitle, and [trailing] (a value, a chevron or a switch). Tappable
/// when [onTap] is set; with [toggled] it reads as a switch.
class ActionRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = RowTone.violet,
    this.value,
    this.chevron = false,
    this.toggled,
    this.trailing,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final RowTone tone;

  /// `.v`: a short value at the end.
  final String? value;

  /// `.chev`: opens another screen.
  final bool chevron;

  /// A switch (`.sw`) at the end; the whole row toggles it.
  final bool? toggled;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (bg, fg) = switch (tone) {
      RowTone.violet => (const Color(0x296F7CF0), c.violetSoft),
      RowTone.teal => (const Color(0x248E9CFF), c.tealSoft),
      RowTone.amber => (const Color(0x29F2A33A), c.amberSoft),
      RowTone.green => (const Color(0x294ABE84), c.okSoft),
    };
    final radius = BorderRadius.circular(IsharaRadii.row);
    final sw = toggled;
    return Semantics(
      container: true,
      button: onTap != null && sw == null,
      toggled: sw,
      label: semanticLabel ?? [title, ?subtitle, ?value].join('. '),
      // a trailing control (History's star) stays reachable on its own
      excludeSemantics: trailing == null,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: c.glass,
          borderRadius: radius,
          border: Border.all(color: c.line, width: c.borderWidth),
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
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: IsharaIcon(icon, size: 18, color: fg),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: t.rowTitle.copyWith(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                color: c.ink,
                              ),
                            ),
                            if (subtitle case final s?) ...[
                              const SizedBox(height: 1),
                              Text(
                                s,
                                style: t.rowSubtitle.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                  color: c.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (value case final v?) ...[
                      const SizedBox(width: 12),
                      Text(
                        v,
                        style: t.rowValue.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: c.sub,
                        ),
                      ),
                    ],
                    ?trailing == null ? null : const SizedBox(width: 12),
                    ?trailing,
                    if (sw != null) ...[
                      const SizedBox(width: 12),
                      IsharaSwitch(on: sw),
                    ],
                    if (chevron) ...[
                      const SizedBox(width: 12),
                      IsharaIcon('chev', size: 16, color: c.muted),
                    ],
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

/// `.sw`: 44 × 26, teal when on, a 20 px knob (the row handles the tap).
class IsharaSwitch extends StatelessWidget {
  const new({required this.on, super.key});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 26,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: on
            ? c.teal
            : (dark ? const Color(0x29FFFFFF) : const Color(0x3815171C)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: on
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? (dark ? c.knob : Colors.white) : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// `.seg`: two (or more) equal tabs in a glass track.
class SegTabs extends StatelessWidget {
  const new({
    required this.labels,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 6, 0, 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line, width: c.borderWidth),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: ValueKey('seg-$i'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelect(i),
                    child: Ink(
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: i == selected
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: dark
                                    ? const [
                                        Color(0x598E9CFF),
                                        Color(0x596F7CF0),
                                      ]
                                    : const [
                                        Color(0x2E3446C9),
                                        Color(0x2E24309A),
                                      ],
                              )
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: context.text.button.copyWith(
                            fontSize: 14,
                            color: i == selected ? c.ink : c.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.field .in`: 52 px, radius 16, the input colour, an icon and the text.
class SearchField extends StatelessWidget {
  const new({
    required this.controller,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 52,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.input,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line, width: c.borderWidth),
      ),
      child: Row(
        children: [
          IsharaIcon('search', size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const ValueKey('search-field'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: context.text.rowTitle.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: context.text.rowTitle.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet note for empty lists (glass card, centred text).
class EmptyNote extends StatelessWidget {
  const new(this.text, {this.icon = 'info', super.key});

  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: c.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line, width: c.borderWidth),
        ),
        child: Column(
          children: [
            IsharaIcon(icon, size: 22, color: c.muted),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: context.text.rowSubtitle.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.45,
                color: c.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
