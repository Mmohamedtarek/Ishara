import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// `.msg.them` / `.msg.me`: max 84 % wide, padding 9 13, radius 18 with the
/// corner on the speaker's side 6 (mirrored in RTL), the text and a status
/// line (hand + "Signed by Nour", or speaker + "Spoken"); pops in (0.3 s).
class MessageBubble extends ConsumerStatefulWidget {
  const new(this.message, {this.trailing, super.key});

  final TalkMessage message;

  /// At the end of the status line (History: the star).
  final Widget? trailing;

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _a.value = 1;
    } else if (!_a.isAnimating && _a.value == 0) {
      _a.forward();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final them = widget.message.side == MessageSide.them;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final character = ref.watch(currentCharacterProvider);
    final status = them
        ? l.signed(
            character?.name(arabic: ar) ?? '',
            character?.icuGender ?? '',
          )
        : l.spoken;
    // dark / light: .msg.them, .msg.me
    final (bg, border) = switch ((them, light)) {
      (true, false) => (const Color(0x218E9CFF), const Color(0x598E9CFF)),
      (true, true) => (const Color(0x1A3446C9), const Color(0x4D3446C9)),
      (false, false) => (const Color(0x296F7CF0), const Color(0x666F7CF0)),
      (false, true) => (const Color(0x1424309A), const Color(0x4D24309A)),
    };
    const big = Radius.circular(18);
    const small = Radius.circular(6);
    return LayoutBuilder(
      builder: (context, box) => Align(
        alignment: them
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * .84),
          child: PopIn(
            animation: CurvedAnimation(parent: _a, curve: Curves.ease),
            child: Semantics(
              container: true,
              label: '${widget.message.text}. $status',
              // the trailing control (History's star) keeps its own label
              excludeSemantics: widget.trailing == null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: border, width: c.borderWidth),
                  borderRadius: BorderRadiusDirectional.only(
                    topStart: big,
                    topEnd: big,
                    bottomStart: them ? small : big,
                    bottomEnd: them ? big : small,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.message.text,
                      style: context.text.message.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 4),
                    Opacity(
                      opacity: .85,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IsharaIcon(
                            them ? 'hand' : 'speaker',
                            size: 12,
                            color: them ? c.tealSoft : c.violetSoft,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              status,
                              style: context.text.chip.copyWith(
                                fontSize: 10.5,
                                color: them ? c.tealSoft : c.violetSoft,
                              ),
                            ),
                          ),
                          if (widget.trailing case final w?) ...[
                            const SizedBox(width: 8),
                            w,
                          ],
                        ],
                      ),
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
