import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/message_bubble.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';
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
          MessageBubble(
            m,
            key: ValueKey(i),
            segments: m.side == MessageSide.them
                ? ref.read(talkSpeechProvider.notifier).segmentsFor(m)
                : null,
          ),
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
