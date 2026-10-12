import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/talk/application/talk_speech_controller.dart';
import 'package:ishara_app/features/talk/presentation/mic_card.dart';
import 'package:ishara_app/features/talk/presentation/talk_avatar_overlay.dart';
import 'package:ishara_app/features/talk/presentation/talk_feed.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-talk`. Step 7a: speech → sign (top bar, mic card, avatar
/// card with the caption, feed). The glove chip and the user's zone (live
/// box, Speak / Type / Clear, quick phrases) come with glove → text (7b).
class TalkScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Back from the phone's settings: a microphone permission given there
    // clears the mic card's notice.
    _life = AppLifecycleListener(
      onResume: () => ref.read(talkSpeechProvider.notifier).recheck(),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final privacy = ref.watch(
      talkSpeechProvider.select((s) => s.privacyNotice),
    );
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
                children: [
                  const MicCard(),
                  if (privacy) const _PrivacyLine(),
                  // .av-card: margin-top 8; avatar slot
                  // clamp(168px, 27vh, 268px)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      height: (size.height * .27).clamp(168, 268).toDouble(),
                      child: const AvatarStage(overlay: TalkAvatarOverlay()),
                    ),
                  ),
                ],
              ),
            ),
            // .feed: flex 1, min height 72
            const Expanded(child: TalkFeed()),
          ],
        ),
      ),
    );
  }
}

/// `header.top` of Talk (padding-bottom 4): the face-to-face toggle and the
/// language toggle. The glove chip at its start comes with step 7b.
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
            const Spacer(),
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
