import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/message_bubble.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/history/application/history_providers.dart';
import 'package:ishara_app/features/history/presentation/history_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// History › one conversation (S9-5): every message as in the feed, a star
/// on each (a saved phrase, Q-B4), and Delete conversation (Undo).
class ConversationScreen extends ConsumerWidget {
  const new({required this.conversationKey, super.key});

  final String conversationKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final all = ref.watch(historyConversationsProvider);
    ref.watch(savedPhrasesProvider); // stars follow the phrases
    final conv = all.where((x) => x.key == conversationKey).firstOrNull;
    final actions = ref.read(historyActionsProvider);
    return Scaffold(
      key: const ValueKey('screen-conversation'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleBar(
              leading: IconCircleButton(
                key: const ValueKey('conversation-back'),
                icon: 'back',
                label: l.back,
                onPressed: () => context.pop(),
              ),
              title: conv == null
                  ? l.histTitle
                  : conversationTitle(context, conv.start, clock.now()),
              lead: conv == null ? null : l.messagesCount(conv.messages.length),
            ),
            Expanded(
              child: conv == null
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      key: const ValueKey('conversation-body'),
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                      itemCount: conv.messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = conv.messages[i];
                        final starred = actions.isStarred(m.text);
                        return MessageBubble(
                          m,
                          key: ValueKey('conversation-msg-$i'),
                          trailing: StarButton(
                            key: ValueKey('star-$i'),
                            starred: starred,
                            onTap: () async {
                              final now = await actions.toggleStar(m.text);
                              if (!context.mounted) return;
                              showToast(
                                context,
                                now ? l.toastStarred : l.toastUnstarred,
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
            if (conv != null)
              CtaBar(
                children: [
                  IsharaButton(
                    key: const ValueKey('conversation-delete'),
                    label: l.deleteConversation,
                    kind: IsharaButtonKind.ghost,
                    leading: IsharaIcon('trash', color: c.ink),
                    onPressed: () => unawaited(_delete(context, ref)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Deletes it and goes back to the list, which offers Undo. Starred
  /// phrases stay (they are their own records).
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final repo = ref.read(conversationRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final removed = await repo.deleteConversation(conversationKey);
    if (!context.mounted) return;
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('history-undo'),
          content: Text(l.toastConvDeleted),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: l.undo,
            onPressed: () => unawaited(repo.restore(removed)),
          ),
        ),
      );
  }
}
