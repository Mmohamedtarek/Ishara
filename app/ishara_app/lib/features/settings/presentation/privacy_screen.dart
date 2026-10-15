import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/settings/application/data_export.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Settings › Privacy: what stays where (the S7-8 speech line included),
/// Export my data and Clear history.
class PrivacyScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    Widget line(String icon, String text, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: IsharaIcon(icon, size: 18, color: c.okSoft),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.text.rowSubtitle.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: c.sub,
              ),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      key: const ValueKey('screen-privacy'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleBar(
              leading: IconCircleButton(
                key: const ValueKey('privacy-back'),
                icon: 'back',
                label: l.back,
                onPressed: () => context.pop(),
              ),
              title: l.sPrivacy,
              lead: l.privacyIntro,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                children: [
                  line('hand', l.privacyGlove),
                  line('clock', l.privacyStored),
                  line('star', l.privacyPhrases),
                  line(
                    'mic',
                    l.privacySpeech,
                    key: const ValueKey('privacy-speech'),
                  ),
                  line(
                    'sos',
                    l.privacyLocation,
                    key: const ValueKey('privacy-location'),
                  ),
                  line('user', l.privacyContacts),
                  const SizedBox(height: 6),
                  ActionRow(
                    key: const ValueKey('privacy-export'),
                    icon: 'shield',
                    tone: RowTone.teal,
                    title: l.exportData,
                    subtitle: l.exportDataS,
                    chevron: true,
                    onTap: () => unawaited(ref.read(exportMyDataProvider)()),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('privacy-clear'),
                    icon: 'trash',
                    tone: RowTone.amber,
                    title: l.clearHistory,
                    subtitle: l.clearHistoryS,
                    onTap: () => unawaited(_clear(context, ref)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.clearHistoryTitle),
        content: Text(l.clearHistoryS),
        actions: [
          TextButton(
            key: const ValueKey('clear-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancelAction),
          ),
          TextButton(
            key: const ValueKey('clear-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.clearAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(conversationRepositoryProvider).deleteAll();
    if (context.mounted) showToast(context, l.toastHistoryCleared);
  }
}
