import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/cast_picker.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/list_ui.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/settings/presentation/settings_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-avatar` (`renderAvatarScreen`), Q-A2: the avatar
/// (looping a sign as the preview), who signs (only with a choice,
/// S5-13), the speed (1x → 0.5x → 1.5x) and Save, which keeps both
/// (Talk, Learn and Setup read them). Leaving with changes asks first.
class AvatarStudioScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<AvatarStudioScreen> createState() => _AvatarStudioState();
}

class _AvatarStudioState extends ConsumerState<AvatarStudioScreen> {
  late String? _character = ref.read(currentCharacterProvider)?.id;
  late double _speed = ref.read(signSpeedProvider);
  AvatarController? _playing;

  // A character not chosen yet (the cast still loading) is no change.
  bool get _changed =>
      (_character != null &&
          _character != ref.read(currentCharacterProvider)?.id) ||
      _speed != ref.read(signSpeedProvider);

  /// Back to where the studio was opened from (Settings).
  void _leave() =>
      context.canPop() ? context.pop() : context.go(AppRoutes.settings);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
  }

  @override
  void dispose() {
    // the preview loop must not follow the user to Talk
    _playing?.stop();
    super.dispose();
  }

  /// The pack's greeting sign, looped at the chosen speed.
  void _preview() {
    if (!mounted) return;
    final avatar = ref.read(avatarRuntimeProvider).value?.controller;
    final sign = avatar?.library.greeting;
    if (avatar == null || sign == null) return;
    _playing = avatar;
    final id = _character;
    if (id != null && id != avatar.character) avatar.setCharacter(id);
    avatar.play(sign, speed: _speed, loop: true);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final id = _character;
    if (id != null) await ref.read(savedCharacterProvider.notifier).save(id);
    await ref.read(signSpeedProvider.notifier).save(_speed);
    if (!mounted) return;
    showToast(context, l.toastSaved);
    _leave();
  }

  Future<bool> _confirmLeave() async {
    if (!_changed) return true;
    final l = AppLocalizations.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('studio-discard'),
        title: Text(l.discardTitle),
        content: Text(l.discardBody),
        actions: [
          TextButton(
            key: const ValueKey('studio-keep'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.keepEditing),
          ),
          TextButton(
            key: const ValueKey('studio-discard-action'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.discardAction),
          ),
        ],
      ),
    );
    if (leave == true) {
      // back to the saved character for everyone else
      final saved = ref.read(currentCharacterProvider)?.id;
      final avatar = _playing;
      if (saved != null && avatar != null && avatar.character != saved) {
        avatar.setCharacter(saved, greet: false);
      }
    }
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cast = ref.watch(avatarCastProvider).value;
    final shown = cast?.byId(_character) ?? ref.watch(currentCharacterProvider);
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) _leave();
      },
      child: Scaffold(
        key: const ValueKey('screen-avatar'),
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(
                leading: IconCircleButton(
                  key: const ValueKey('studio-back'),
                  icon: 'back',
                  label: l.back,
                  onPressed: () async {
                    if (await _confirmLeave() && context.mounted) _leave();
                  },
                ),
                title: l.avTitle,
                lead: l.avSub(
                  shown?.name(arabic: ar) ?? '',
                  shown?.icuGender ?? '',
                ),
              ),
              // #s-avatar .avatar-slot: 300 px, margin 0 16 12
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(height: 300, child: AvatarStage()),
              ),
              Expanded(
                child: ListView(
                  key: const ValueKey('studio-body'),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  children: [
                    CastPicker(
                      selected: _character,
                      onSelect: (id) {
                        setState(() => _character = id);
                        _preview();
                        final ch = cast?.byId(id);
                        if (ch != null) {
                          showToast(
                            context,
                            l.toastAvatar(ch.name(arabic: ar), ch.icuGender),
                          );
                        }
                      },
                    ),
                    ActionRow(
                      key: const ValueKey('studio-speed'),
                      icon: 'clock',
                      tone: RowTone.teal,
                      title: l.avSpeed,
                      subtitle: l.avSpeedS,
                      value: '${speedLabel(_speed)}x',
                      onTap: () {
                        setState(() => _speed = SignSpeed.next(_speed));
                        _preview();
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
                      child: Opacity(
                        opacity: .8,
                        child: Text(
                          l.avCredit,
                          key: const ValueKey('studio-credit'),
                          style: context.text.rowSubtitle.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: c.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              CtaBar(
                children: [
                  IsharaButton(
                    key: const ValueKey('studio-save'),
                    label: l.saveAvatar,
                    onPressed: () => unawaited(_save()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
