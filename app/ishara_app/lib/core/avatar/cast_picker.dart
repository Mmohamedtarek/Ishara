import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// "Who signs for you" (prototype `castPicker`): one card per visible
/// character (`AvatarCast.characters`). Nothing at all unless the cast
/// offers a choice (`showPicker`, S5-13 / RB-1). The Avatar studio and
/// Setup use it (S6-9).
class CastPicker extends ConsumerWidget {
  const new({required this.selected, required this.onSelect, super.key});

  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(avatarCastProvider).value;
    if (cast == null || !cast.showPicker) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final current = cast.byId(selected).id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuestionLabel(l.avWho),
        SizedBox(
          height: 118,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final AvatarCharacter ch in cast.characters) ...[
                Semantics(
                  inMutuallyExclusiveGroup: true,
                  checked: ch.id == current,
                  button: true,
                  label: ch.name(arabic: ar),
                  excludeSemantics: true,
                  child: InkWell(
                    key: ValueKey('cast-${ch.id}'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelect(ch.id),
                    child: Container(
                      width: 86,
                      padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
                      decoration: BoxDecoration(
                        color: ch.id == current
                            ? const Color(0x1F8E9CFF)
                            : c.glass,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: ch.id == current
                              ? const Color(0xCCB7C0FF)
                              : c.line,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFE6E2D8),
                              border: ch.id == current
                                  ? Border.all(color: c.teal, width: 3)
                                  : null,
                            ),
                            child: Text(
                              ch.name(arabic: ar).characters.first,
                              style: context.text.topTitle.copyWith(
                                color: const Color(0xFF0B1026),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ch.name(arabic: ar),
                            style: context.text.rowTitle.copyWith(
                              fontSize: 13,
                              color: c.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
