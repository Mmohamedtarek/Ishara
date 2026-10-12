import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/dashed_box.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';
import 'package:ishara_app/features/talk/presentation/mic_card.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// `.me-zone`: "You · live from your glove" + LIVE, the live box, the type
/// box, Speak / Type / Clear, and the quick phrases (Q-T1, Q-T2, Q-T4).
class MeZone extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MeZone> createState() => _MeZoneState();
}

class _MeZoneState extends ConsumerState<MeZone> {
  bool _typing = false;
  final _typed = TextEditingController();
  final _typeFocus = FocusNode();

  @override
  void dispose() {
    _typed.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  void _send() {
    ref.read(talkGloveProvider.notifier).sendTyped(_typed.text);
    _typed.clear();
    setState(() => _typing = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final s = ref.watch(talkGloveProvider);
    final n = ref.read(talkGloveProvider.notifier);
    final hasSentence = s.sentence.isNotEmpty;
    // S7-2: "I sign" puts the live box first for screen readers.
    final signFirst =
        ref.watch(profileControllerProvider).role == UserRole.sign;
    return Semantics(
      sortKey: OrdinalSortKey(signFirst ? -1 : 1),
      explicitChildNodes: true,
      child: Container(
        key: const ValueKey('talk-me-zone'),
        // .me-zone: padding 8 14 6, bar gradient, line on top
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [c.bar2, c.bar2s],
          ),
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ZoneHeader(
              label: l.meLabel,
              liveText: l.live,
              live:
                  ref.watch(gloveStatusProvider).value?.phase ==
                  GlovePhase.ready,
            ),
            const LiveBox(),
            if (s.voiceMissing) const _VoiceMissing(),
            if (_typing)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _TypeBox(
                  controller: _typed,
                  focus: _typeFocus,
                  onSend: _send,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _SpeakButton(
                      speaking: s.speaking,
                      onPressed: hasSentence ? n.speakSentence : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _GhostButton(
                    key: const ValueKey('talk-type'),
                    icon: 'keyboard',
                    label: l.type,
                    onPressed: () {
                      setState(() => _typing = !_typing);
                      if (_typing) _typeFocus.requestFocus();
                    },
                  ),
                  const SizedBox(width: 8),
                  _GhostButton(
                    key: const ValueKey('talk-clear'),
                    icon: 'trash',
                    semanticLabel: l.clearLabel,
                    onPressed: n.endSentence,
                  ),
                ],
              ),
            ),
            const _QuickPhrases(),
          ],
        ),
      ),
    );
  }
}

/// `.zone-label` + `.live` (violet, blinking dot).
class _ZoneHeader extends StatelessWidget {
  const new({required this.label, required this.liveText, required this.live});

  final String label;
  final String liveText;

  /// The glove is streaming.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final style = context.text.chip.copyWith(
      fontSize: ar ? 12 : 11.5,
      letterSpacing: ar ? 0 : 11.5 * .02,
      color: c.muted,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 30),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(ar ? label : label.toUpperCase(), style: style),
            ),
            Blink(
              // only while the glove streams: "LIVE" with no glove isn't
              on: live,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.violet,
                  boxShadow: [BoxShadow(color: c.violet, blurRadius: 8)],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              ar ? liveText : liveText.toUpperCase(),
              style: style.copyWith(color: c.violetSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.live-box`: the user's words as they come (AI-SPEC §7): a tentative
/// word faded with "…" (tap: confirm and speak it, Q-T1), a cancelled one
/// fading out. With no words: what to do, or why nothing can come (D13
/// no glove, D14 no calibration, D15 recognizer stopped).
class LiveBox extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final s = ref.watch(talkGloveProvider);
    final glove = ref.watch(gloveStatusProvider).value ?? const GloveStatus();
    final placeholder = _placeholder(context, l, s, glove);
    return DashedBox(
      // .live-box (light): rgba(36,48,154,.06), dashed rgba(36,48,154,.4)
      color: light ? const Color(0x0F24309A) : const Color(0x1A6F7CF0),
      borderColor: light ? const Color(0x6624309A) : const Color(0x73C9CFFF),
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ConstrainedBox(
        // min-height 50 (phone) minus the padding
        constraints: const BoxConstraints(minHeight: 30),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: s.words.isEmpty
              ? placeholder
              : Wrap(
                  key: const ValueKey('talk-live-words'),
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final w in s.words)
                      _Word(word: w, key: ValueKey('live-${w.id}')),
                  ],
                ),
        ),
      ),
    );
  }

  static Widget _placeholder(
    BuildContext context,
    AppLocalizations l,
    TalkGloveState s,
    GloveStatus glove,
  ) {
    final c = context.colors;
    final style = context.text.liveBox.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: c.muted,
    );
    Widget withAction(String text, String action, VoidCallback onTap) => Row(
      children: [
        Expanded(child: Text(text, style: style)),
        IsharaLink(
          key: const ValueKey('talk-live-action'),
          label: action,
          onPressed: onTap,
        ),
      ],
    );
    if (s.recognitionFailed) {
      return withAction(
        l.liveStopped,
        l.connect,
        () => context.push(AppRoutes.pair),
      );
    }
    if (glove.phase != GlovePhase.ready) {
      return withAction(
        l.liveNoGlove,
        l.connect,
        () => context.push(AppRoutes.pair),
      );
    }
    if (glove.storedCalibration == StoredCalibration.none) {
      return withAction(
        l.liveNoCal,
        l.ctaCalNow,
        () => context.push(AppRoutes.calibrate),
      );
    }
    return Text(l.livePh, style: style);
  }
}

/// One live word; pops in (0.25 s). Tentative: faded with "…", a button.
class _Word extends ConsumerWidget {
  const new({required this.word, super.key});

  final LiveWord word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final tentative = word.state == LiveWordState.tentative;
    final gone = word.state == LiveWordState.cancelled;
    final text = Text(
      tentative ? '${word.text}…' : word.text,
      style: context.text.liveBox.copyWith(color: c.ink),
    );
    final shown = AnimatedOpacity(
      opacity: gone
          ? 0
          : tentative
          ? .45
          : 1,
      duration: reduce ? Duration.zero : TalkGlove.fadeOut,
      child: text,
    );
    final popped = TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: const Cubic(.2, .8, .2, 1),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - v)),
          child: Transform.scale(scale: .9 + .1 * v, child: child),
        ),
      ),
      child: shown,
    );
    if (!tentative) {
      return gone ? ExcludeSemantics(child: popped) : popped;
    }
    return Semantics(
      button: true,
      label: l.tentativeLabel(word.text),
      excludeSemantics: true,
      onTap: () => ref.read(talkGloveProvider.notifier).confirmByTap(word.id),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(talkGloveProvider.notifier).confirmByTap(word.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Align(widthFactor: 1, child: popped),
        ),
      ),
    );
  }
}

/// D16: the phone has no voice for the spoken language.
class _VoiceMissing extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final ar = ref.watch(profileControllerProvider).spoken == SpokenLanguage.ar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(
        l.ttsNoVoice(ar ? l.langNameAr : l.langNameEn),
        key: const ValueKey('talk-no-voice'),
        style: context.text.rowSubtitle.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.amberSoft,
        ),
      ),
    );
  }
}

/// `.typebox`: the field and the send button (Q-T2).
class _TypeBox extends StatelessWidget {
  const new({
    required this.controller,
    required this.focus,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('talk-type-field'),
            controller: controller,
            focusNode: focus,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: context.text.message.copyWith(fontSize: 15, color: c.ink),
            decoration: InputDecoration(
              hintText: l.typePh,
              filled: true,
              fillColor: c.input,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              constraints: const BoxConstraints(minHeight: 46),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xB3C9CFFF)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _GhostButton(
          key: const ValueKey('talk-type-send'),
          icon: 'arrow',
          semanticLabel: l.typeAddLabel,
          size: 46,
          onPressed: onSend,
        ),
      ],
    );
  }
}

/// `.actions .btn.speak`: 50 px, radius 16, the violet gradient; pulses
/// while speaking ("Speaking…"); disabled with no sentence (S7-22).
class _SpeakButton extends StatelessWidget {
  const new({required this.speaking, required this.onPressed});

  final bool speaking;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final enabled = onPressed != null;
    final fg = light ? Colors.white : const Color(0xFF0E1440);
    return Semantics(
      button: true,
      enabled: enabled,
      label: speaking ? l.speaking : l.speak,
      excludeSemantics: true,
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Container(
          key: const ValueKey('talk-speak'),
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: light
                  ? const [Color(0xFF3446C9), Color(0xFF24309A)]
                  : const [Color(0xFFC9CFFF), Color(0xFF6F7CF0)],
            ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: light
                          ? const Color(0x4D24309A)
                          : const Color(0x736F7CF0),
                      blurRadius: speaking ? 40 : 26,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onPressed,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IsharaIcon('speaker', color: fg),
                  const SizedBox(width: 8),
                  Text(
                    speaking ? l.speaking : l.speak,
                    style: context.text.button.copyWith(
                      fontSize: 15.5,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.actions .btn.ghost` (Type, with its label) and `.btn.sq` (Clear, the
/// send button: an icon with a screen-reader label).
class _GhostButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.onPressed,
    this.label,
    this.semanticLabel,
    this.size = 50,
    super.key,
  });

  final String icon;
  final String? label;
  final String? semanticLabel;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: c.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Container(
            height: size,
            constraints: BoxConstraints(minWidth: size),
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IsharaIcon(icon, color: c.ink),
                if (label case final text?) ...[
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: context.text.button.copyWith(
                      fontSize: 14,
                      color: c.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.quick`: SOS and the prototype's phrases, scrolling sideways with a
/// fade at the end (mirrored in RTL). Each is spoken and goes to the feed
/// (S7-18); SOS speaks a clear sentence (S7-7, D23) and shows D2.
class _QuickPhrases extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final n = ref.read(talkGloveProvider.notifier);
    final phrases = [
      (l.qThanks, l.qSayThanks),
      (l.qRepeat, l.qSayRepeat),
      (l.qSlower, l.qSaySlower),
      (l.qWrite, l.qSayWrite),
      (l.qDeaf, l.qSayDeaf),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ShaderMask(
        // mask-image: linear-gradient(to right, #000 86%, transparent)
        shaderCallback: (r) => LinearGradient(
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: const [0, .86, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          key: const ValueKey('talk-quick'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              _QuickChip(
                key: const ValueKey('talk-quick-sos'),
                label: 'SOS',
                semanticLabel: l.sos,
                sos: true,
                onTap: () {
                  n.quickPhrase(l.sosSay).ignore();
                  showToast(context, l.toastSosSpoken);
                },
              ),
              for (final (i, (label, say)) in phrases.indexed) ...[
                const SizedBox(width: 7),
                _QuickChip(
                  key: ValueKey('talk-quick-$i'),
                  label: label,
                  onTap: () => n.quickPhrase(say).ignore(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.quick button` (40 px min, padding 8 13, glass); `.sos` red.
class _QuickChip extends StatelessWidget {
  const new({
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.sos = false,
    super.key,
  });

  final String label;
  final String? semanticLabel;
  final bool sos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final light = Theme.of(context).brightness == Brightness.light;
    final (bg, border, fg) = !sos
        ? (c.glass, c.line, c.sub)
        : light
        ? (
            const Color(0x14C62B33),
            const Color(0x73C62B33),
            const Color(0xFFC62B33),
          )
        : (
            const Color(0x29F06E76),
            const Color(0x99F06E76),
            const Color(0xFFFFD3DA),
          );
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            alignment: Alignment.center,
            child: Text(
              label,
              style: context.text.chip.copyWith(fontSize: 13, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
