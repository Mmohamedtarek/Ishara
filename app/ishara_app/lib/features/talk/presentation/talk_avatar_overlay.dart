import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';
import 'package:ishara_app/features/talk/presentation/mic_card.dart';
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
    // .pill.on: #C9CFFF, border rgba(201,207,255,.5); dot #8E9CFF glowing
    final on = signing ? const Color(0xFFC9CFFF) : Colors.white;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xB3121318),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: signing ? const Color(0x80C9CFFF) : const Color(0x33FFFFFF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Blink(
              on: signing,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: signing
                      ? const Color(0xFF8E9CFF)
                      : context.colors.muted,
                  boxShadow: signing
                      ? const [
                          BoxShadow(color: Color(0xFF8E9CFF), blurRadius: 8),
                        ]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              signing ? l.avSigning(gender) : l.avReady,
              style: context.text.chip.copyWith(fontSize: 11.5, color: on),
            ),
          ],
        ),
      ),
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
        _CtlButton(
          key: const ValueKey('talk-replay'),
          semanticLabel: l.replay,
          onPressed: () => ref.read(talkSpeechProvider.notifier).replay(),
          child: const IsharaIcon('replay', size: 15, color: Colors.white),
        ),
        const SizedBox(width: 6),
        _CtlButton(
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

/// `#avatar .ctl button`: 36 px high (min width 36, padding 0 9), round,
/// rgba(18,19,24,.7) with a white 20 % border; a 5 px larger touch area.
class _CtlButton extends StatelessWidget {
  const new({
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
    super.key,
  });

  final String semanticLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    onTap: onPressed,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xB3121318),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: child,
        ),
      ),
    ),
  );
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
    final s = ref.watch(talkSpeechProvider);
    final character = ref.watch(currentCharacterProvider);
    final name = character?.name(arabic: ar) ?? '';
    final gender = character?.icuGender ?? '';
    final label = l.avSigningFor(gender);
    final words = <(String, bool)>[
      for (var i = 0; i < s.sentence.length; i++)
        for (final w in s.sentence[i].words) (w, i == s.active),
    ];
    final runtime = ref.watch(avatarRuntimeProvider).value;
    return _ReportHeight(
      onHeight: (h) => runtime?.controller.reframe(captionHeight: h),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: Container(
          key: const ValueKey('talk-caption'),
          // padding 16 12 9; rgba(18,19,24,.9) → .55 at 60 % → 0
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 9),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xE6121318), Color(0x8C121318), Color(0x00121318)],
              stops: [0, .6, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(
                  ar ? label : label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: t.chip.copyWith(
                    fontSize: ar ? 12 : 11,
                    letterSpacing: ar ? 0 : 11 * .05,
                    color: const Color(0xFFC9CFFF),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              if (words.isEmpty)
                Text(
                  l.avIdle(name, gender),
                  textAlign: TextAlign.center,
                  style: t.caption,
                )
              else
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    for (final (w, on) in words)
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Calls [onHeight] with the child's height after each layout that changes
/// it.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const new({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  _RenderReportHeight createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  new(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
