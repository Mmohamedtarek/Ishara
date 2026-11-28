import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_card_parts.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// What Talk lays over the avatar (`#avatar`): the Ready / Signing pill,
/// Replay and the speed button, and the caption with the word being signed
/// highlighted (prototype `avSign`).
class TalkAvatarOverlay extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    children: [
      PositionedDirectional(top: 12, start: 12, child: _Pill()),
      PositionedDirectional(top: 10, end: 10, child: _Controls()),
      Positioned(left: 0, right: 0, bottom: 0, child: _Caption()),
    ],
  );
}

/// `#avatar .pill`: "Ready", or "Signing" with a glowing blinking dot.
class _Pill extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final signing = ref.watch(talkSpeechProvider.select((s) => s.signing));
    final gender = ref.watch(currentCharacterProvider)?.icuGender ?? '';
    return AvatarPill(
      on: signing,
      text: signing ? l.avSigning(gender) : l.avReady,
    );
  }
}

/// `#avatar .ctl`: Replay and the speed (1x → 0.5x → 1.5x).
class _Controls extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final speed = ref.watch(signSpeedProvider);
    final label = '${_fmt(speed)}x';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AvatarCtlButton(
          key: const ValueKey('talk-replay'),
          semanticLabel: l.replay,
          onPressed: () => ref.read(talkSpeechProvider.notifier).replay(),
          child: const IsharaIcon('replay', size: 15, color: Colors.white),
        ),
        const SizedBox(width: 6),
        AvatarCtlButton(
          key: const ValueKey('talk-speed'),
          semanticLabel: '${l.toastSpeed} $label',
          onPressed: () {
            ref.read(signSpeedProvider.notifier).cycle();
            showToast(
              context,
              '${l.toastSpeed} ${_fmt(ref.read(signSpeedProvider))}x',
            );
          },
          child: Text(
            label,
            style: context.text.chip.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// 1 → "1", 0.5 → "0.5" (prototype `speeds[si] + 'x'`).
  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

/// `#avatar .cap`: a dark fade from the bottom; "Signing for you" (11 px
/// w800 #C9CFFF, uppercase in English) over the sentence, each word a chip
/// that lights up (#C9CFFF on #0E1440) while its sign plays. Before any
/// sentence: "Nour will sign what they say". Its height keeps the avatar's
/// signing space above it (`reframe`).
class _Caption extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.text;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    if (!ref.watch(appSettingsControllerProvider.select((s) => s.subtitles))) {
      // S9-2: subtitles off: no caption, the avatar takes the full height
      final runtime = ref.watch(avatarRuntimeProvider).value;
      return ReportHeight(
        key: const ValueKey('talk-caption-off'),
        onHeight: (h) => runtime?.controller.reframe(captionHeight: h),
        child: const SizedBox(width: double.infinity, height: 0),
      );
    }
    final s = ref.watch(talkSpeechProvider);
    final character = ref.watch(currentCharacterProvider);
    final name = character?.name(arabic: ar) ?? '';
    final gender = character?.icuGender ?? '';
    final label = l.avSigningFor(gender);
    // a word with no sign stays grey and never lights up (NS1)
    final words = <(String, bool, bool)>[
      for (var i = 0; i < s.sentence.length; i++)
        for (final w in s.sentence[i].words)
          (w, i == s.active, SpeechToSign.noSign(s.sentence[i])),
    ];
    final runtime = ref.watch(avatarRuntimeProvider).value;
    return AvatarCaptionBox(
      key: const ValueKey('talk-caption'),
      label: label,
      onHeight: (h) => runtime?.controller.reframe(captionHeight: h),
      child: words.isEmpty
          ? Text(
              l.avIdle(name, gender),
              textAlign: TextAlign.center,
              style: t.caption,
            )
          : Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                for (final (w, on, none) in words)
                  if (none)
                    Semantics(
                      label: '$w, ${l.noSignYet}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          w,
                          style: t.caption.copyWith(
                            color: (t.caption.color ?? Colors.white).withValues(
                              alpha: .55,
                            ),
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                            decorationColor: (t.caption.color ?? Colors.white)
                                .withValues(alpha: .55),
                          ),
                        ),
                      ),
                    )
                  else
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: on ? const Color(0xFFC9CFFF) : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        w,
                        style: t.caption.copyWith(
                          color: on ? const Color(0xFF0E1440) : null,
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
