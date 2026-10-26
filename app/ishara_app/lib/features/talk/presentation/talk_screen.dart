import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/device/keep_screen_on.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';
import 'package:ishara_app/features/talk/presentation/glove_chip.dart';
import 'package:ishara_app/features/talk/presentation/me_zone.dart';
import 'package:ishara_app/features/talk/presentation/mic_card.dart';
import 'package:ishara_app/features/talk/presentation/mock_panel.dart';
import 'package:ishara_app/features/talk/presentation/talk_avatar_overlay.dart';
import 'package:ishara_app/features/talk/presentation/talk_feed.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-talk`: the glove chip and toggles, the mic card (speech →
/// sign), the avatar with its caption, the feed, and the user's zone (glove
/// → text, Speak / Type / Clear, quick phrases). The screen stays on while
/// Talk is visible and the app is in the foreground (S7-5).
class TalkScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen> {
  /// `.feed { min-height: 72px }`.
  static const _feedMin = 72.0;

  /// A smaller avatar stage shows nothing useful (the caption alone would
  /// fill it), so it is left out.
  static const _minStage = 120.0;

  late final AppLifecycleListener _life;
  bool _foreground = true;
  bool _visible = false;
  bool? _screenOn;

  /// Kept: [dispose] can't use `ref` (the widget is unmounting).
  late final KeepScreenOn _keepOn = ref.read(keepScreenOnProvider);
  late final TalkGlove _glove = ref.read(talkGloveProvider.notifier);
  late final TalkSpeech _speech;

  @override
  void initState() {
    super.initState();
    // read now: [dispose] can't use `ref`
    _speech = ref.read(talkSpeechProvider.notifier);
    _life = AppLifecycleListener(
      onStateChange: (s) {
        _foreground = s == AppLifecycleState.resumed;
        _syncScreen();
      },
      // Back from the phone's settings: a microphone permission given there
      // clears the mic card's notice.
      onResume: () => ref.read(talkSpeechProvider.notifier).recheck(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Another tab hides Talk without disposing it: its tickers stop.
    _visible = TickerMode.valuesOf(context).enabled;
    _syncScreen();
  }

  /// S7-5: on only while Talk is visible and the app is in the foreground.
  void _syncScreen() {
    final on = _visible && _foreground;
    _glove.setActive(active: _visible);
    // hold to talk: a recording never goes on out of sight (another tab,
    // the app in the background): it is thrown away
    if (!on) _speech.cancelMic().ignore();
    if (on == _screenOn) return;
    _screenOn = on;
    _keepOn.set(on: on).ignore();
  }

  @override
  void dispose() {
    _life.dispose();
    if (_screenOn ?? false) _keepOn.set(on: false).ignore();
    // Talk is gone: the glove's words are not Talk's any more.
    _glove.setActive(active: false);
    _speech.cancelMic().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final privacy = ref.watch(
      talkSpeechProvider.select((s) => s.privacyNotice),
    );
    // glove → text runs while Talk exists
    ref.listen(talkGloveProvider, (_, _) {});
    return Scaffold(
      key: const ValueKey('screen-talk'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TopBar(),
            // .them: padding 0 14
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const MicCard(), if (privacy) const _PrivacyLine()],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  // .av-card: margin-top 8; avatar clamp(168px, 27vh, 268px).
                  // The feed keeps its 72 px (.feed min-height): when notices
                  // or the keyboard take room, the avatar gives it up first,
                  // and below [_minStage] it isn't shown at all.
                  final want = (size.height * .27).clamp(168, 268).toDouble();
                  final room = box.maxHeight - 8 - _feedMin;
                  final stage = want < room ? want : room;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (stage >= _minStage)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                          child: SizedBox(
                            height: stage,
                            child: const AvatarStage(
                              overlay: TalkAvatarOverlay(),
                            ),
                          ),
                        ),
                      // .feed: flex 1
                      const Expanded(child: TalkFeed()),
                    ],
                  );
                },
              ),
            ),
            const MeZone(),
          ],
        ),
      ),
    );
  }
}

/// `header.top` of Talk (padding-bottom 4): the glove chip, the developer
/// panel (debug / profile, mock glove only), the face-to-face toggle and the
/// language toggle.
class _TopBar extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final f2f = ref.watch(talkSpeechProvider.select((s) => s.faceToFace));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            // the chip takes the free width (its text ellipsizes if needed)
            const Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: GloveChip(),
              ),
            ),
            const MockPanelButton(),
            const SizedBox(width: 8),
            IconCircleButton(
              key: const ValueKey('talk-f2f'),
              icon: 'flip',
              label: l.f2f,
              on: f2f,
              onPressed: () {
                ref.read(talkSpeechProvider.notifier).toggleFaceToFace();
                showToast(context, f2f ? l.toastF2fOff : l.toastF2fOn);
              },
            ),
            const SizedBox(width: 10),
            const LangToggle(),
          ],
        ),
      ),
    );
  }
}

/// D19 (Q-T3): what speech to text does with the other person's voice,
/// shown from the first use of the mic until "OK".
class _PrivacyLine extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('talk-privacy'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          IsharaIcon('shield', size: 16, color: c.sub),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l.privacySpeech,
              style: context.text.rowSubtitle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: c.sub,
              ),
            ),
          ),
          IsharaLink(
            key: const ValueKey('talk-privacy-ok'),
            label: l.ok,
            onPressed: () =>
                ref.read(talkSpeechProvider.notifier).dismissPrivacy(),
          ),
        ],
      ),
    );
  }
}
