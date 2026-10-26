import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/blink.dart';
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
class MicCard extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MicCard> createState() => _MicCardState();
}

class _MicCardState extends ConsumerState<MicCard> {
  /// How far the held mic has slid toward cancel (for "Release to cancel").
  final _slide = ValueNotifier<double>(0);

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(talkSpeechProvider);
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final listening = s.mic == MicState.listening;
    final tapMode = micTapMode(context, ref);
    final n = ref.read(talkSpeechProvider.notifier);
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
                    _MicStateLabel(
                      listening: listening,
                      finishing: s.mic == MicState.finishing,
                    ),
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
                    finishing: s.mic == MicState.finishing,
                    tapMode: tapMode,
                    onPress: n.pressMic,
                    onRelease: n.releaseMic,
                    onCancel: n.cancelMic,
                    onTap: n.tapMic,
                    slide: _slide,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: listening
                        ? _RecordingStrip(
                            tapMode: tapMode,
                            slide: _slide,
                            since: s.recordingSince,
                          )
                        : _MicHint(state: s, tapMode: tapMode),
                  ),
                  if (listening) ...[
                    const SizedBox(width: 10),
                    _LevelBars(level: n.level),
                  ],
                ],
              ),
            ),
            if (_action(context, ref, s.mic) case final a?)
              Padding(padding: const EdgeInsets.only(top: 8), child: a),
            if (s.faceToFace) _MicSigns(tapMode: tapMode),
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
  const new({required this.listening, this.finishing = false});

  final bool listening;

  /// Released, waiting for the last words: "One moment…" (TV11), not "Mic
  /// ready" (user, 2026-10-26).
  final bool finishing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final active = listening || finishing;
    final color = active ? c.tealSoft : c.muted;
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
                color: active ? c.teal : c.muted,
                boxShadow: listening
                    ? [BoxShadow(color: c.teal, blurRadius: 8)]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            listening
                ? l.listening
                : finishing
                ? l.micFinishing
                : l.micIdle,
            style: context.text.chip.copyWith(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}

/// Whether Talk's mic records with taps (start, then send) instead of hold
/// to talk: Settings › Tap to start and stop, or a screen reader / Switch
/// Access is on (2026-10-26, user decision).
bool micTapMode(BuildContext context, WidgetRef ref) =>
    ref.watch(appSettingsControllerProvider.select((s) => s.micTap)) ||
    MediaQuery.accessibleNavigationOf(context);

/// `.mic`: 56 px round button with the prototype's gradient; recording it
/// grows and pulses (1 s).
///
/// Hold to talk (2026-10-26): pressing starts recording ([onPress]), letting
/// go sends it ([onRelease]); sliding toward the start side (left, right in
/// Arabic) past [cancelDistance] and letting go throws it away
/// ([onCancel]). In tap mode a tap starts and the next one sends
/// ([onTap]). The screen reader always gets tap actions, and "Cancel
/// recording" while recording.
class MicButton extends StatefulWidget {
  const new({
    required this.listening,
    required this.tapMode,
    required this.onPress,
    required this.onRelease,
    required this.onCancel,
    required this.onTap,
    required this.slide,
    this.finishing = false,
    super.key,
  });

  /// Written with how far the held mic has slid toward cancel.
  final ValueNotifier<double> slide;

  final bool listening;

  /// Released, waiting for the last words: not pressable.
  final bool finishing;
  final bool tapMode;
  final VoidCallback onPress;
  final VoidCallback onRelease;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  /// How far to slide before letting go cancels.
  static const cancelDistance = 90.0;

  /// How far the mic itself moves while sliding (it stays on the card).
  static const maxShift = 12.0;

  /// The mic's size while recording (WhatsApp-like grow).
  static const recordingScale = 1.3;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  /// The pointer holding the mic, and where it went down.
  int? _pointer;
  Offset _down = Offset.zero;
  double _slide = 0;

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
    // recording ended by itself (60 s, an error): forget the hold
    if (old.listening && !widget.listening) _setSlide(0);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _setSlide(double v) {
    if (_slide == v) return;
    setState(() => _slide = v);
    widget.slide.value = v;
  }

  void _onDown(PointerDownEvent e) {
    if (widget.tapMode || widget.finishing || _pointer != null) return;
    _pointer = e.pointer;
    _down = e.localPosition;
    _setSlide(0);
    widget.onPress();
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    final dx = e.localPosition.dx - _down.dx;
    // toward the start side: left in English, right in Arabic
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final toward = rtl ? dx : -dx;
    _setSlide(toward.clamp(0, MicButton.cancelDistance + 20).toDouble());
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final cancel = _slide >= MicButton.cancelDistance;
    _setSlide(0);
    cancel ? widget.onCancel() : widget.onRelease();
  }

  void _onCancelPointer(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    // the system took the touch (a call, a system gesture): throw it away
    _pointer = null;
    _setSlide(0);
    widget.onCancel();
  }

  void _cancelAction() {
    widget.onCancel();
    final l = AppLocalizations.of(context);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        l.micCancelled,
        Directionality.of(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final reduce = MediaQuery.disableAnimationsOf(context);
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
    final label = !widget.tapMode
        ? l.micHoldLabel
        : widget.listening
        ? l.micStopLabel
        : l.micStartLabel;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final button = AnimatedBuilder(
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
                BoxShadow(color: const Color(0x268E9CFF), spreadRadius: 10 * k),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          // hold to talk works on the raw pointer (below); a tap only
          // records in tap mode
          onTap: widget.tapMode && !widget.finishing ? widget.onTap : null,
          child: Center(child: IsharaIcon('mic', size: 24, color: fg)),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      enabled: !widget.finishing,
      excludeSemantics: true,
      onTap: widget.finishing ? null : widget.onTap,
      customSemanticsActions: widget.listening
          ? {CustomSemanticsAction(label: l.micCancelAction): _cancelAction}
          : null,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancelPointer,
        child: Transform.translate(
          // the held mic leans toward cancel; it sits at the card's start
          // edge, so it moves only a little (the finger slides further)
          offset: Offset(
            (rtl ? 1 : -1) * _slide.clamp(0, MicButton.maxShift).toDouble(),
            0,
          ),
          child: AnimatedScale(
            scale: widget.listening ? MicButton.recordingScale : 1,
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 150),
            child: Opacity(opacity: widget.finishing ? .6 : 1, child: button),
          ),
        ),
      ),
    );
  }
}

/// While recording: a blinking red dot and the time, then "‹ Slide to
/// cancel" (hold to talk; "Release to cancel" once slid far enough) or
/// "Stop and send" (tap mode).
class _RecordingStrip extends StatefulWidget {
  const new({required this.tapMode, required this.slide, this.since});

  final bool tapMode;
  final ValueNotifier<double> slide;

  /// When recording started (the timer counts from it).
  final DateTime? since;

  @override
  State<_RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<_RecordingStrip>
    with SingleTickerProviderStateMixin {
  late final _ticker = createTicker(_tick);
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _tick(Duration.zero);
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final since = widget.since;
    final s = since == null
        ? elapsed.inSeconds
        : clock
              .now()
              .difference(since)
              .inSeconds
              .clamp(0, TalkSpeech.maxRecording.inSeconds);
    if (s != _seconds) setState(() => _seconds = s);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final base = context.text.rowSubtitle.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      height: 1.35,
      color: c.sub,
    );
    final time =
        '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Row(
      key: const ValueKey('talk-mic-recording'),
      children: [
        // the mic grew over this side: keep clear of it
        const SizedBox(width: 6),
        Blink(
          on: true,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c.danger),
          ),
        ),
        const SizedBox(width: 6),
        ExcludeSemantics(
          child: Text(
            time,
            key: const ValueKey('talk-mic-timer'),
            style: base.copyWith(
              color: c.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: widget.tapMode
              // the mic button already says it to screen readers
              ? ExcludeSemantics(
                  child: Text(
                    l.micStopLabel,
                    style: base,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : ValueListenableBuilder<double>(
                  valueListenable: widget.slide,
                  builder: (context, slide, _) {
                    final armed = slide >= MicButton.cancelDistance;
                    final text = Text(
                      armed ? l.micReleaseCancel : l.micSlideCancel,
                      key: const ValueKey('talk-mic-slide'),
                      overflow: TextOverflow.ellipsis,
                      style: base.copyWith(color: armed ? c.danger : c.sub),
                    );
                    if (armed) return text;
                    // the start-side arrow (mirrored in Arabic: it points
                    // right there)
                    return Row(
                      children: [
                        IsharaIcon('back', size: 13, color: c.sub),
                        const SizedBox(width: 3),
                        Flexible(child: text),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// `.mic-hint` (12.5 px w700 sub, the bold part teal-soft): what to do, or
/// what went wrong (D4-D9).
class _MicHint extends ConsumerWidget {
  const new({required this.state, required this.tapMode});

  final TalkSpeechState state;
  final bool tapMode;

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
          '${tapMode ? l.sttNothingHeard : l.sttNothingHeardHold}'
              '\n${l.sttTryShortSentence}',
        MicNotice.failed => l.authErrUnknown,
        MicNotice.tooShort => l.micTooShort,
        MicNotice.none => null,
      },
    };
    final Widget text;
    if (state.mic == MicState.listening) {
      text = Text(l.listening, style: strong);
    } else if (state.mic == MicState.finishing) {
      text = Text(l.micFinishing, style: strong);
    } else if (plain != null) {
      text = Text(plain, style: base);
    } else {
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      final character = ref.watch(currentCharacterProvider);
      text = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: tapMode ? l.micTapStrong : l.micHoldStrong,
              style: strong,
            ),
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

/// `.bars`: six 3 px bars (22 px high). The prototype animates them; here
/// they follow the microphone's loudness while recording (hold to talk:
/// a live level indicator), each bar a little different.
class _LevelBars extends StatelessWidget {
  const new({required this.level});

  final ValueListenable<double> level;

  /// Each bar's share of the level, so they don't move as one.
  static const _weights = [.55, .85, 1.0, .75, .95, .65];

  @override
  Widget build(BuildContext context) {
    final color = context.colors.tealSoft;
    // reduced motion: the bars stay still (as the prototype's do)
    final still = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: ValueListenableBuilder<double>(
        valueListenable: still ? const AlwaysStoppedAnimation(.5) : level,
        builder: (context, v, _) => SizedBox(
          key: const ValueKey('talk-mic-level'),
          height: 22,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Transform.scale(
                  scaleY: .25 + .75 * (v * _weights[i]).clamp(0, 1),
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
}

/// `.mic-signs` (face to face): the user's words for the person opposite
/// (the confirmed ones: what the voice has said), or "Waiting for signs…",
/// and "Tap the mic to reply".
class _MicSigns extends ConsumerWidget {
  const new({required this.tapMode});

  final bool tapMode;

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
              tapMode ? l.micReply : l.micReplyHold,
              textAlign: TextAlign.center,
              style: t.chip.copyWith(fontSize: 11, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
