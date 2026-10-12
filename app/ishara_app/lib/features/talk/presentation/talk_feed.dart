import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// `#feed`: "Today" (D1), then today's messages, newest at the bottom (it
/// scrolls there when one arrives). Older days stay in the conversation for
/// History (step 8).
class TalkFeed extends ConsumerStatefulWidget {
  const new({this.now = DateTime.now, super.key});

  /// Tests fix the clock.
  final DateTime Function() now;

  @override
  ConsumerState<TalkFeed> createState() => _TalkFeedState();
}

class _TalkFeedState extends ConsumerState<TalkFeed> {
  final _scroll = ScrollController();
  int _count = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    final all = ref.watch(conversationProvider).value ?? const [];
    final today = [
      for (final m in all)
        if (m.at.year == now.year &&
            m.at.month == now.month &&
            m.at.day == now.day)
          m,
    ];
    if (today.length != _count) {
      _count = today.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    return ListView(
      key: const ValueKey('talk-feed'),
      controller: _scroll,
      // .feed: padding 10 16 4, gap 8
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      children: [
        const Center(child: _Day()),
        for (final (i, m) in today.indexed) ...[
          const SizedBox(height: 8),
          // by position: two identical messages are still two widgets
          _Message(m, key: ValueKey(i)),
        ],
      ],
    );
  }
}

/// `.day`: 11 px w800 muted on glass, pill.
class _Day extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: context.colors.glass,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      AppLocalizations.of(context).talkToday,
      style: context.text.chip.copyWith(
        fontSize: 11,
        color: context.colors.muted,
      ),
    ),
  );
}

/// `.msg.them` / `.msg.me`: max 84 % wide, padding 9 13, radius 18 with the
/// corner on the speaker's side 6 (mirrored in RTL), the text and a status
/// line (hand + "Signed by Nour", or speaker + "Spoken"); pops in (0.3 s).
class _Message extends ConsumerStatefulWidget {
  const new(this.message, {super.key});

  final TalkMessage message;

  @override
  ConsumerState<_Message> createState() => _MessageState();
}

class _MessageState extends ConsumerState<_Message>
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
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: border),
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
