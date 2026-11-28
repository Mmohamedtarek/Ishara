import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// `.msg.them` / `.msg.me`: max 84 % wide, padding 9 13, radius 18 with the
/// corner on the speaker's side 6 (mirrored in RTL), the text and a status
/// line (hand + "Signed by Nour", or speaker + "Spoken"); pops in (0.3 s).
class MessageBubble extends ConsumerStatefulWidget {
  const new(this.message, {this.trailing, this.segments, super.key});

  final TalkMessage message;

  /// How a heard sentence was signed (Talk, this session): the words with
  /// no sign are greyed, with NS2 under the text. Null: plain text.
  final List<SignSegment>? segments;

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
    final segments = widget.segments;
    final unsigned = segments == null ? 0 : SpeechToSign.noSignWords(segments);
    final plain = context.text.message.copyWith(color: c.ink);
    final grey = plain.copyWith(
      color: c.muted,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      decorationColor: c.muted,
    );
    // the screen reader hears "word, no sign yet" after each such word
    final spoken = segments == null || unsigned == 0
        ? widget.message.text
        : [
            for (final s in segments)
              if (SpeechToSign.noSign(s))
                '${s.text}, ${l.noSignYet},'
              else
                s.text,
          ].join(' ');
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
              label: unsigned == 0
                  ? '$spoken. $status'
                  : '$spoken. ${l.noSignCount(unsigned)}. $status',
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
                    if (segments == null || unsigned == 0)
                      Text(widget.message.text, style: plain)
                    else ...[
                      Text.rich(
                        key: const ValueKey('bubble-no-sign'),
                        TextSpan(
                          children: [
                            for (final (i, s) in segments.indexed) ...[
                              if (i > 0) const TextSpan(text: ' '),
                              TextSpan(
                                text: s.text,
                                style: SpeechToSign.noSign(s) ? grey : null,
                              ),
                            ],
                          ],
                        ),
                        style: plain,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l.noSignCount(unsigned),
                        style: context.text.chip.copyWith(
                          fontSize: 10.5,
                          color: c.muted,
                        ),
                      ),
                    ],
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
