import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/dashed_box.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// `#micCard` (`.mic-card`): who it is for, the mic state, the mic button
/// with its hint and level bars, and, face to face, the user's words for
/// the person opposite (`.mic-signs`). Face to face turns the card 180°
/// (0.6 s) so it faces that person.
class MicCard extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(talkSpeechProvider);
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final listening = s.mic == MicState.listening;
    return AnimatedRotation(
      turns: s.faceToFace ? .5 : 0,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 600),
      curve: IsharaMotion.ease,
      child: Container(
        key: const ValueKey('talk-mic-card'),
        // .mic-card: radius 22, panel-soft, line, padding 6 12 10,
        // shadow 0 10 26 var(--shadow)
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        decoration: BoxDecoration(
          color: c.panelSoft,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.line),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // .zone-label: padding 4 2, min height 26
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 26),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _ZoneLabel(
                        s.faceToFace ? l.themLabelF2f : l.themLabel,
                      ),
                    ),
                    _MicStateLabel(listening: listening),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
              child: Row(
                children: [
                  MicButton(
                    listening: listening,
                    onPressed: () =>
                        ref.read(talkSpeechProvider.notifier).tapMic(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _MicHint(state: s)),
                  if (listening) ...[
                    const SizedBox(width: 10),
                    const _LevelBars(),
                  ],
                ],
              ),
            ),
            if (_action(context, ref, s.mic) case final a?)
              Padding(padding: const EdgeInsets.only(top: 8), child: a),
            if (s.faceToFace) const _MicSigns(),
          ],
        ),
      ),
    );
  }

  /// D4 "Allow" / D5 "Open settings".
  static Widget? _action(BuildContext context, WidgetRef ref, MicState mic) {
    final l = AppLocalizations.of(context);
    final n = ref.read(talkSpeechProvider.notifier);
    return switch (mic) {
      MicState.permissionNeeded => IsharaButton(
        key: const ValueKey('talk-mic-allow'),
        label: l.allow,
        kind: IsharaButtonKind.ghost,
        small: true,
        onPressed: n.allowMic,
      ),
      MicState.permissionBlocked => IsharaButton(
        key: const ValueKey('talk-mic-settings'),
        label: l.openSettings,
        kind: IsharaButtonKind.ghost,
        small: true,
        onPressed: n.openSettings,
      ),
      _ => null,
    };
  }
}

/// `.zone-label` text: 11.5 px w800 muted, uppercase with .02em in English
/// (12 px, no case change in Arabic).
class _ZoneLabel extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Text(
      ar ? text : text.toUpperCase(),
      style: context.text.chip.copyWith(
        fontSize: ar ? 12 : 11.5,
        letterSpacing: ar ? 0 : 11.5 * .02,
        color: context.colors.muted,
      ),
    );
  }
}

/// `.mic-state`: a 7 px dot and "Mic ready" / "Listening…" (11 px w800);
/// listening: teal-soft, the dot glowing and blinking.
class _MicStateLabel extends StatelessWidget {
  const new({required this.listening});

  final bool listening;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final color = listening ? c.tealSoft : c.muted;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Blink(
            on: listening,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening ? c.teal : c.muted,
                boxShadow: listening
                    ? [BoxShadow(color: c.teal, blurRadius: 8)]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            listening ? l.listening : l.micIdle,
            style: context.text.chip.copyWith(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

/// `.mic`: 56 px round button with the prototype's gradient; listening it
/// pulses (1 s). Its accessible name is D18 ("Tap and speak").
class MicButton extends StatefulWidget {
  const new({required this.listening, required this.onPressed, super.key});

  final bool listening;
  final VoidCallback onPressed;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  void _sync() {
    final on = widget.listening && !MediaQuery.disableAnimationsOf(context);
    if (on && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!on && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MicButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    // .mic / light: linear-gradient(135deg, …)
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: light
          ? const [Color(0xFF4B5BD6), Color(0xFF3446C9)]
          : const [Color(0xFFA9B3FF), Color(0xFF6F7CF0)],
    );
    final fg = light ? Colors.white : const Color(0xFF0E1440);
    final glow = light ? const Color(0x593446C9) : const Color(0x738E9CFF);
    return Semantics(
      button: true,
      label: l.micLabel,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          // pulse: 50% → 0 8 34 rgba(142,156,255,.95) + 0 0 0 10 (.15)
          final k = 1 - (2 * _pulse.value - 1).abs();
          return Container(
            key: const ValueKey('talk-mic'),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(glow, const Color(0xF28E9CFF), k)!,
                  blurRadius: 24 + 10 * k,
                  offset: const Offset(0, 8),
                ),
                if (k > 0)
                  BoxShadow(
                    color: const Color(0x268E9CFF),
                    spreadRadius: 10 * k,
                  ),
              ],
            ),
            child: child,
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            child: Center(child: IsharaIcon('mic', size: 24, color: fg)),
          ),
        ),
      ),
    );
  }
}

/// `.mic-hint` (12.5 px w700 sub, the bold part teal-soft): what to do, or
/// what went wrong (D4-D9).
class _MicHint extends ConsumerWidget {
  const new({required this.state});

  final TalkSpeechState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final base = context.text.rowSubtitle.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      height: 1.35,
      color: c.sub,
    );
    final strong = base.copyWith(color: c.tealSoft);
    final arabicVoice =
        ref.watch(profileControllerProvider).spoken == SpokenLanguage.ar;
    final plain = switch (state.mic) {
      MicState.permissionNeeded => l.micPermBody,
      MicState.permissionBlocked => l.micPermBodySettings,
      MicState.unavailable => l.sttUnavailable,
      MicState.languageMissing => arabicVoice ? l.sttNoArabic : l.sttNoEnglish,
      _ => switch (state.notice) {
        // D9 + D24: the phone's recognizer drops very short words said
        // alone (phone test 4); a short sentence works.
        MicNotice.nothingHeard =>
          '${l.sttNothingHeard}\n${l.sttTryShortSentence}',
        MicNotice.failed => l.authErrUnknown,
        MicNotice.none => null,
      },
    };
    final Widget text;
    if (state.mic == MicState.listening) {
      text = Text(l.listening, style: strong);
    } else if (plain != null) {
      text = Text(plain, style: base);
    } else {
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      final character = ref.watch(currentCharacterProvider);
      text = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: l.micHintStrong, style: strong),
            const TextSpan(text: ' '),
            TextSpan(
              text: l.micHintRest(
                character?.name(arabic: ar) ?? '',
                character?.icuGender ?? '',
              ),
            ),
          ],
        ),
        style: base,
      );
    }
    return Semantics(
      liveRegion: true,
      child: KeyedSubtree(key: const ValueKey('talk-mic-hint'), child: text),
    );
  }
}

/// `.bars`: six 3 px bars (22 px high) rising and falling 1 s apart by
/// 0.09 s, while listening. Reduced motion: still.
class _LevelBars extends StatefulWidget {
  const new();

  @override
  State<_LevelBars> createState() => _LevelBarsState();
}

class _LevelBarsState extends State<_LevelBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _a.stop();
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colors.tealSoft;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) => SizedBox(
          height: 22,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Transform.scale(
                  scaleY: _bar((_a.value - i * .09) % 1),
                  child: Container(
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// @keyframes bar: .25 → 1 → .25, ease-in-out.
  static double _bar(double t) =>
      .25 + .75 * Curves.easeInOut.transform(1 - (2 * t - 1).abs());
}

/// `.mic-signs` (face to face): the user's words for the person opposite
/// (the confirmed ones: what the voice has said), or "Waiting for signs…",
/// and "Tap the mic to reply".
class _MicSigns extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final l = AppLocalizations.of(context);
    final words = [
      for (final w in ref.watch(talkGloveProvider).sentence) w.text,
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DashedBox(
        // rgba(142,156,255,.1), 1 px dashed rgba(142,156,255,.4), radius 16
        color: const Color(0x1A8E9CFF),
        borderColor: const Color(0x668E9CFF),
        radius: 16,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                words.isEmpty ? l.waitSigns : words,
                key: const ValueKey('talk-mic-signs'),
                textAlign: TextAlign.center,
                style: words.isEmpty
                    ? t.micSigns.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.muted,
                      )
                    : t.micSigns.copyWith(color: c.ink),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.micReply,
              textAlign: TextAlign.center,
              style: t.chip.copyWith(fontSize: 11, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// `@keyframes blink` (50 %: opacity .3, 1 s) while [on]; reduced motion:
/// steady.
class Blink extends StatefulWidget {
  const new({required this.on, required this.child, super.key});

  final bool on;
  final Widget child;

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  void _sync() {
    final run = widget.on && !MediaQuery.disableAnimationsOf(context);
    if (run && !_a.isAnimating) {
      _a.repeat();
    } else if (!run && _a.isAnimating) {
      _a
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Blink old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (context, child) =>
        Opacity(opacity: 1 - .7 * (1 - (2 * _a.value - 1).abs()), child: child),
    child: widget.child,
  );
}
