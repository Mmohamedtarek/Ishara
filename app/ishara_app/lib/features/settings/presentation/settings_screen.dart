import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/glove/dev_glove_switch.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/sign_language_picker.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/sos/application/sos_controller.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

String speedLabel(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// Prototype screen `#s-settings` (`renderSettings`) with the step 9
/// changes: real profile and glove, the sign-language pills (Q-B5), avatar
/// and subtitles (S9-2), accessibility (S9-1), appearance (Q-D3), language,
/// emergency contacts, privacy, about, sign out. No "coming soon" rows.
class SettingsScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final settings = ref.watch(appSettingsControllerProvider);
    final ctl = ref.read(appSettingsControllerProvider.notifier);
    final ar = settings.language == AppLanguage.ar;
    final character = ref.watch(currentCharacterProvider);
    final speed = ref.watch(signSpeedProvider);
    final contacts = ref.watch(emergencyContactsProvider).value ?? const [];
    final dev = ref.watch(developerModeProvider) && DevGloveSwitch.available;
    return Scaffold(
      key: const ValueKey('screen-settings'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleBar(
              title: l.setTitle,
              lead: l.setLead,
              trailing: const LangToggle(),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('settings-body'),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
                children: [
                  const _Profile(),
                  SectionLabel(l.secGlove),
                  const _Glove(),
                  SectionLabel(l.qSignLang),
                  const SignLanguagePicker(),
                  SectionLabel(l.secAvatarOnly),
                  ActionRow(
                    key: const ValueKey('settings-avatar'),
                    icon: 'user',
                    tone: RowTone.teal,
                    title: l.sAvatar(character?.name(arabic: ar) ?? ''),
                    subtitle: l.avatarSpeedS(speedLabel(speed)),
                    chevron: true,
                    onTap: () =>
                        unawaited(context.push(AppRoutes.avatarStudio)),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-subtitles'),
                    icon: 'text',
                    title: l.sSubs,
                    subtitle: l.sSubsS,
                    toggled: settings.subtitles,
                    onTap: () => ctl.setSubtitles(on: !settings.subtitles),
                  ),
                  SectionLabel(l.secAccess),
                  ActionRow(
                    key: const ValueKey('settings-vibrate'),
                    icon: 'vibrate',
                    tone: RowTone.green,
                    title: l.vibrateTitle,
                    subtitle: l.vibrateS,
                    toggled: settings.vibrate,
                    onTap: () => ctl.setVibrate(on: !settings.vibrate),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-big-text'),
                    icon: 'text',
                    title: l.sText,
                    subtitle: l.sTextS,
                    toggled: settings.bigText,
                    onTap: () => ctl.setBigText(on: !settings.bigText),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-contrast'),
                    icon: 'eye',
                    title: l.sContrast,
                    subtitle: l.sContrastS,
                    toggled: settings.highContrast,
                    onTap: () =>
                        ctl.setHighContrast(on: !settings.highContrast),
                  ),
                  SectionLabel(l.secApp),
                  ActionRow(
                    icon: 'eye',
                    tone: RowTone.teal,
                    title: l.appearance,
                    semanticLabel: l.appearance,
                  ),
                  SegTabs(
                    key: const ValueKey('settings-theme'),
                    labels: [l.themeSystem, l.themeLight, l.themeDark],
                    selected: switch (settings.themeMode) {
                      ThemeMode.system => 0,
                      ThemeMode.light => 1,
                      ThemeMode.dark => 2,
                    },
                    onSelect: (i) => ctl.setThemeMode(
                      [ThemeMode.system, ThemeMode.light, ThemeMode.dark][i],
                    ),
                  ),
                  ActionRow(
                    key: const ValueKey('settings-language'),
                    icon: 'globe',
                    tone: RowTone.teal,
                    title: l.sLang,
                    subtitle: l.sLangS,
                    value: ar ? 'عربي' : 'EN',
                    onTap: ctl.toggleLanguage,
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-emergency'),
                    icon: 'sos',
                    tone: RowTone.amber,
                    title: l.emergencyContacts,
                    subtitle: contacts.isEmpty
                        ? l.emergencyNone
                        : l.emergencyCount(contacts.length),
                    chevron: true,
                    onTap: () =>
                        unawaited(context.push(AppRoutes.emergencyContacts)),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-privacy'),
                    icon: 'shield',
                    tone: RowTone.green,
                    title: l.sPrivacy,
                    subtitle: l.sPrivacyS,
                    chevron: true,
                    onTap: () => unawaited(context.push(AppRoutes.privacy)),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-about'),
                    icon: 'info',
                    title: l.sAbout,
                    chevron: true,
                    onTap: () => unawaited(context.push(AppRoutes.about)),
                  ),
                  const SizedBox(height: 8),
                  ActionRow(
                    key: const ValueKey('settings-sign-out'),
                    icon: 'logout',
                    tone: RowTone.amber,
                    title: l.sLogout,
                    subtitle: l.sLogoutS,
                    onTap: () async {
                      await ref.read(authRepositoryProvider).signOut();
                      if (!context.mounted) return;
                      showToast(context, l.toastLogout);
                      context.go(AppRoutes.welcome);
                    },
                  ),
                  if (dev) const _Developer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.profile`: the initial, the name and what that means; a guest gets
/// "Create account".
class _Profile extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = Theme.of(context).brightness == Brightness.dark;
    ref.watch(learnGuestProvider);
    final user = ref.watch(authRepositoryProvider).currentUser;
    final name = user?.name ?? l.guestName;
    final initial = user == null
        ? '?'
        : (name.isEmpty ? '?' : name.characters.first.toUpperCase());
    return Container(
      key: const ValueKey('settings-profile'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0x298E9CFF), Color(0x296F7CF0)]
              : const [Color(0x1F3446C9), Color(0x1F24309A)],
        ),
        border: Border.all(
          color: dark ? const Color(0x59B7C0FF) : const Color(0x4D3446C9),
          width: c.borderWidth,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4B5BD6), Color(0xFF24309A)],
              ),
            ),
            child: ExcludeSemantics(
              child: Text(
                initial,
                style: t.topTitle.copyWith(
                  fontSize: 20,
                  color: dark ? const Color(0xFF0E1440) : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: t.rowTitle.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user == null ? l.guestNote : l.signedInAsEmail(user.email),
                  style: t.rowSubtitle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ),
          if (user == null) ...[
            const SizedBox(width: 10),
            // `width:auto` in the prototype: as wide as its label (capped)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: IntrinsicWidth(
                child: IsharaButton(
                  key: const ValueKey('settings-create-account'),
                  label: l.createNow,
                  small: true,
                  onPressed: () =>
                      unawaited(context.push(AppRoutes.auth(signUp: true))),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The paired glove: its real name, state, battery and firmware;
/// Calibrate and Pair a new glove come back here (S8-8 pattern).
class _Glove extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final paired = ref.watch(profileControllerProvider).glove;
    final status = ref.watch(gloveStatusProvider).value ?? const GloveStatus();
    final connected = status.phase == GlovePhase.ready;
    final state = !connected
        ? l.gloveOff
        : switch (status.battery) {
            BatteryEvent(level: BatteryLevel.ok, percent: final p?) =>
              l.sumGloveBatt(p),
            BatteryEvent(level: BatteryLevel.low) => l.sumGloveLow,
            BatteryEvent(level: BatteryLevel.usb) => l.sumGloveUsb,
            _ => l.gloveOn,
          };
    final fw = status.info?.firmware;
    return Column(
      children: [
        ActionRow(
          key: const ValueKey('settings-glove'),
          icon: 'bt',
          title: paired?.name ?? l.gloveNone,
          subtitle: paired == null
              ? null
              : [
                  state,
                  if (connected && fw != null) l.gloveFirmware(fw),
                ].join(' · '),
          trailing: connected
              ? Text(
                  l.sCal,
                  style: context.text.rowValue.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.tealSoft,
                  ),
                )
              : null,
          onTap: connected
              ? () => unawaited(context.push(AppRoutes.calibrateBack(1)))
              : null,
        ),
        const SizedBox(height: 8),
        ActionRow(
          key: const ValueKey('settings-pair'),
          icon: 'plus',
          tone: RowTone.teal,
          title: l.sPair,
          subtitle: paired == null ? null : l.pairReplaceS,
          chevron: true,
          onTap: () => unawaited(context.push(AppRoutes.pairBack(1))),
        ),
      ],
    );
  }
}

/// S9-3: debug / profile builds only, while developer mode is on. English
/// only (a tool, like the mock panel).
class _Developer extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glove = ref.watch(devGloveSwitchProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Developer'),
        ActionRow(
          key: const ValueKey('settings-dev-glove'),
          icon: 'bt',
          title: 'Glove source',
          subtitle: 'Mock glove or the real glove over Bluetooth',
          value: glove.current,
          onTap: glove.toggle,
        ),
        const SizedBox(height: 8),
        ActionRow(
          key: const ValueKey('settings-dev-signs'),
          icon: 'hand',
          title: 'Sign preview',
          subtitle: 'Every avatar sign, front and side',
          chevron: true,
          onTap: () => unawaited(context.push(AppRoutes.signPreview)),
        ),
      ],
    );
  }
}
