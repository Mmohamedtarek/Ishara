import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/device/app_info.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_mark.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/settings/domain/tap_counter.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Settings › About: the version (7 taps: developer mode, S9-3), the
/// avatar credits (RB-1 wording) and the open-source licences.
class AboutScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  final _taps = TapCounter();

  void _tapVersion() {
    if (!_taps.tap()) return;
    final l = AppLocalizations.of(context);
    final dev = ref.read(developerModeProvider.notifier);
    final on = !ref.read(developerModeProvider);
    dev.set(on: on);
    showToast(context, on ? l.devModeOn : l.devModeOff);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final version = ref.watch(appVersionProvider).value ?? '';
    return Scaffold(
      key: const ValueKey('screen-about'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleBar(
              leading: IconCircleButton(
                key: const ValueKey('about-back'),
                icon: 'back',
                label: l.back,
                onPressed: () => context.pop(),
              ),
              title: l.sAbout,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                children: [
                  const Center(child: IsharaMark.header()),
                  const SizedBox(height: 16),
                  ActionRow(
                    key: const ValueKey('about-version'),
                    icon: 'info',
                    title: 'Ishara',
                    subtitle: l.aboutVersion(version),
                    onTap: _tapVersion,
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('about-licences'),
                    icon: 'text',
                    tone: RowTone.teal,
                    title: l.licences,
                    chevron: true,
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Ishara',
                      applicationVersion: version,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.avCredit,
                    key: const ValueKey('about-credits'),
                    style: context.text.rowSubtitle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
