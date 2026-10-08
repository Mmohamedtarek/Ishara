import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// The "Sign language" choice of Setup and Settings (prototype `.pills`,
/// `data-pick="sign"`), in the prototype's order: ArSL, ASL.
///
/// ASL is the default. ArSL carries a "Coming soon" badge; choosing it
/// shows [showArslComingSoon] and keeps ASL. Nothing is saved for ArSL.
class SignLanguagePicker extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignLanguagePicker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<SignLanguagePicker> {
  /// The dialog is open: a second tap must not stack another one.
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final active = ref.watch(activeSignLanguageProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final lang in const [SignLanguage.arsl, SignLanguage.asl])
          _Pill(
            key: ValueKey('sign-language-${lang.id}'),
            label: lang == SignLanguage.asl ? l.asl : l.arsl,
            selected: active == lang,
            comingSoon: !PackRegistry.isAvailable(lang),
            onTap: () async {
              final ok = ref
                  .read(activeSignLanguageProvider.notifier)
                  .select(lang);
              if (ok || _dialogOpen) return;
              _dialogOpen = true;
              try {
                await showArslComingSoon(context);
              } finally {
                if (mounted) _dialogOpen = false;
              }
            },
          ),
      ],
    );
  }
}

/// The dialog shown when ArSL is chosen (text and button from the prompt).
Future<void> showArslComingSoon(BuildContext context) {
  final l = AppLocalizations.of(context);
  final c = context.colors;
  final t = context.text;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      // Screen readers announce the dialog by name (iOS has no default).
      semanticLabel: l.comingSoon,
      backgroundColor: c.bg2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: c.line),
      ),
      content: Text(
        l.arslComingSoon,
        style: t.rowTitle.copyWith(fontWeight: FontWeight.w700, height: 1.45),
      ),
      actions: [
        TextButton(
          key: const ValueKey('arsl-coming-soon-ok'),
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 48),
            foregroundColor: Theme.of(context).brightness == Brightness.dark
                ? c.tealSoft
                : c.teal,
            textStyle: t.buttonSmall,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.ok),
        ),
      ],
    ),
  );
}

/// `.pill` (CSS l.273-276, light overrides l.64): glass background, 1.5 px
/// line border, check icon when on.
class _Pill extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.comingSoon,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool comingSoon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = selected;
    final fg = on ? c.tealSoft : c.sub;
    final bg = on
        ? (dark ? const Color(0x248E9CFF) : const Color(0x1A3446C9))
        : c.glass;
    final border = on
        ? (dark ? const Color(0xB3B7C0FF) : const Color(0x803446C9))
        : c.line;
    final l = AppLocalizations.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: on,
      button: true,
      label: comingSoon ? '$label, ${l.comingSoon}' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (on) ...[
                    IsharaIcon('check', size: 14, color: fg),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: t.chip.copyWith(fontSize: 13.5, color: fg),
                  ),
                  if (comingSoon) ...[
                    const SizedBox(width: 7),
                    _ComingSoonBadge(text: l.comingSoon),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small amber chip, styled like the prototype's `.mod .xp` (CSS l.436,
/// light l.53).
class _ComingSoonBadge extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0x24F2A33A) : const Color(0x1AF2A33A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark ? const Color(0x59FACD8C) : const Color(0x4DF2A33A),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          text,
          style: context.text.chip.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
            color: c.amberSoft,
          ),
        ),
      ),
    );
  }
}
