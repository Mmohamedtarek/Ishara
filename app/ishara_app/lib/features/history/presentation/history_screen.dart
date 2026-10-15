import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/history/application/history_providers.dart';
import 'package:ishara_app/features/history/domain/history.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// A conversation's title (Q-B4): its day ("Today", "Yesterday" or the
/// date) and the time of its first message, in the app language.
String conversationTitle(BuildContext context, DateTime start, DateTime now) {
  final l = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  final day = switch (History.marker(start, now)) {
    DayMarker.today => l.talkToday,
    DayMarker.yesterday => l.histYesterday,
    DayMarker.date =>
      start.year == now.year
          ? (DateFormat('d MMM', locale)..useNativeDigits = false).format(start)
          : (DateFormat(
              'd MMM y',
              locale,
            )..useNativeDigits = false).format(start),
  };
  // Western digits, as everywhere else in the app
  final time = (DateFormat.Hm(locale)..useNativeDigits = false).format(start);
  return l.histTitleAt(day, time);
}

/// Prototype screen `#s-history` (`renderHist`): search, All / Starred.
/// Real data only: the feed's conversations and the starred phrases.
class HistoryScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _search = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return Scaffold(
      key: const ValueKey('screen-history'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleBar(title: l.histTitle, lead: l.histLeadPhone),
            Expanded(
              child: ListView(
                key: const ValueKey('history-body'),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                children: [
                  SearchField(
                    controller: _search,
                    hint: l.searchWordPh,
                    onChanged: (_) => setState(() {}),
                  ),
                  SegTabs(
                    labels: [l.allConv, l.starred],
                    selected: _tab,
                    onSelect: (i) => setState(() => _tab = i),
                  ),
                  if (_tab == 0)
                    _Conversations(query: _search.text)
                  else
                    _Starred(query: _search.text),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conversations extends ConsumerWidget {
  const new({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final all = ref.watch(historyConversationsProvider);
    if (all.isEmpty) {
      return EmptyNote(l.histEmpty, icon: 'clock');
    }
    final found = History.search(all, query);
    if (found.isEmpty) return EmptyNote(l.searchEmpty(query), icon: 'search');
    final now = clock.now();
    return Column(
      children: [
        for (final (conv, match) in found) ...[
          ActionRow(
            key: ValueKey('history-row-${conv.key}'),
            icon: 'chat',
            tone: RowTone.teal,
            title: conversationTitle(context, conv.start, now),
            subtitle:
                '${l.messagesCount(conv.messages.length)} · ${match.text}',
            chevron: true,
            onTap: () =>
                unawaited(context.push(AppRoutes.conversation(conv.key))),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Starred extends ConsumerWidget {
  const new({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final phrases = ref.watch(savedPhrasesProvider).value ?? const [];
    final guest = ref.watch(learnGuestProvider);
    final q = History.fold(query);
    final shown = [
      for (final p in phrases)
        if (q.isEmpty || History.fold(p.text).contains(q)) p,
    ];
    final actions = ref.read(historyActionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (guest) ...[
          Text(
            l.guestStarredNote,
            key: const ValueKey('history-guest'),
            style: context.text.rowSubtitle.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.amberSoft,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (phrases.isEmpty)
          EmptyNote(l.starredEmpty, icon: 'star')
        else if (shown.isEmpty)
          EmptyNote(l.searchEmpty(query), icon: 'search')
        else
          for (final p in shown) ...[
            ActionRow(
              key: ValueKey('starred-${p.id}'),
              icon: 'star',
              tone: RowTone.amber,
              title: p.text,
              semanticLabel: l.speakPhraseLabel(p.text),
              trailing: StarButton(
                starred: true,
                onTap: () async {
                  await actions.toggleStar(p.text);
                  if (context.mounted) showToast(context, l.toastUnstarred);
                },
              ),
              onTap: () => unawaited(actions.speak(p.text)),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// The star on a sentence (the prototype's `star` icon): amber when
/// starred, muted when not; a 44 px target.
class StarButton extends StatelessWidget {
  const new({required this.starred, required this.onTap, super.key});

  final bool starred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return Semantics(
      container: true,
      button: true,
      toggled: starred,
      label: starred ? l.unstarLabel : l.starLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: IsharaIcon('star', color: starred ? c.amber : c.muted),
          ),
        ),
      ),
    );
  }
}
