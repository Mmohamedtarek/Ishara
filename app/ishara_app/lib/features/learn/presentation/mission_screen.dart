import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/avatar/avatar_bubble.dart';
import 'package:ishara_app/core/avatar/avatar_card_parts.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';
import 'package:ishara_app/features/learn/presentation/learn_modules_ui.dart';
import 'package:ishara_app/features/learn/presentation/mission_widgets.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-mission`: close, the step bar and the XP chip; the
/// avatar (250 px); then pick-the-meaning, "your turn" or the result.
class MissionScreen extends ConsumerStatefulWidget {
  const new({required this.moduleId, super.key});

  final String moduleId;

  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen>
    with WidgetsBindingObserver {
  MissionControllerProvider get _provider =>
      missionControllerProvider(widget.moduleId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // in the background the avatar was paused: the step's loop ended
    if (state == AppLifecycleState.resumed) {
      ref.read(_provider.notifier).resumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // on stage = not covered (Pair, Calibrate on top) and not leaving
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    // after the frame: hiding cancels a running window (a state change),
    // and this runs during the build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(_provider.notifier).setVisible(visible: visible);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = ref.watch(_provider);
    ref.listen(_provider.select((s) => s.unavailable), (_, gone) {
      if (gone && context.mounted && context.canPop()) context.pop();
    });
    final catalogue = ref.watch(signCatalogueProvider).value;
    final step = s.step;
    final plan = s.plan;
    return Scaffold(
      key: const ValueKey('screen-mission'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(state: s),
            // #s-mission .avatar-slot: 250 px, margin 0 16
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 250,
                child: AvatarStage(
                  overlay: _AvatarOverlay(
                    moduleId: widget.moduleId,
                    state: s,
                    catalogue: catalogue,
                  ),
                ),
              ),
            ),
            Expanded(
              child: plan == null || catalogue == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      key: const ValueKey('mission-body'),
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                      child: switch (step) {
                        final QuizStep q => QuizBody(
                          step: q,
                          state: s,
                          catalogue: catalogue,
                          onPick: ref.read(_provider.notifier).pick,
                        ),
                        final PracticeStep p => PracticeBody(
                          step: p,
                          state: s,
                          catalogue: catalogue,
                        ),
                        null when s.result != null => ResultBody(
                          result: s.result!,
                          daily: plan.isDaily,
                        ),
                        null => const SizedBox.shrink(),
                      },
                    ),
            ),
            if (plan != null) _Cta(moduleId: widget.moduleId, state: s),
          ],
        ),
      ),
    );
  }
}

/// `#s-mission .top`: close, `.segs` (done / on), the XP chip (`.chip.a`).
class _TopBar extends StatelessWidget {
  const new({required this.state});

  final MissionState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final total = state.plan?.steps.length ?? 0;
    final at = state.result != null ? total : state.index;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            IconCircleButton(
              key: const ValueKey('mission-close'),
              icon: 'x',
              label: l.closeLabel,
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go(AppRoutes.learn),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: total == 0
                    ? null
                    : l.missionStepOf((at + 1).clamp(1, total), total),
                excludeSemantics: true,
                child: Row(
                  children: [
                    for (var i = 0; i < total; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i < at
                                ? c.violet
                                : i == at
                                ? c.violetSoft
                                : c.track,
                            boxShadow: i == at
                                ? [
                                    BoxShadow(
                                      color: dark
                                          ? const Color(0xCCC9CFFF)
                                          : const Color(0x663446C9),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              label: '+${state.xp} ${l.xp}',
              excludeSemantics: true,
              child: Container(
                key: const ValueKey('mission-xp'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0x24F2A33A)
                      : const Color(0x1AF2A33A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: dark
                        ? const Color(0x66FACD8C)
                        : const Color(0x59F2A33A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IsharaIcon('bolt', size: 14, color: c.ink),
                    const SizedBox(width: 7),
                    Text(
                      '+${state.xp}',
                      style: context.text.chip.copyWith(color: c.amberSoft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the mission lays over the avatar (`avState`): the pill, Replay and
/// speed, the caption ("Watch Nour" + the word on a practice step), and on
/// the result the "Mission complete!" bubble (no pill, no controls).
class _AvatarOverlay extends ConsumerWidget {
  const new({
    required this.moduleId,
    required this.state,
    required this.catalogue,
  });

  final String moduleId;
  final MissionState state;
  final SignCatalogue? catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.text;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final character = ref.watch(currentCharacterProvider);
    final name = character?.name(arabic: ar) ?? '';
    final gender = character?.icuGender ?? '';
    final runtime = ref.watch(avatarRuntimeProvider).value;
    final speed = ref.watch(signSpeedProvider);
    final step = state.step;
    if (state.result != null) {
      return AvatarBubble(l.missionDone);
    }
    if (step == null) return const SizedBox.shrink();
    final sign = catalogue?.byLabel(step.label);
    final word = sign?.wordsIn(learnLanguage(context)).word ?? '';
    final speedLabel = '${_fmt(speed)}x';
    return Stack(
      fit: StackFit.expand,
      children: [
        PositionedDirectional(
          top: 12,
          start: 12,
          child: AvatarPill(on: true, text: l.avSigning(gender)),
        ),
        PositionedDirectional(
          top: 10,
          end: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarCtlButton(
                key: const ValueKey('mission-replay'),
                semanticLabel: l.replay,
                onPressed: () => ref
                    .read(missionControllerProvider(moduleId).notifier)
                    .replay(),
                child: const IsharaIcon(
                  'replay',
                  size: 15,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 6),
              AvatarCtlButton(
                key: const ValueKey('mission-speed'),
                semanticLabel: '${l.toastSpeed} $speedLabel',
                onPressed: () {
                  ref.read(signSpeedProvider.notifier).cycle();
                  showToast(
                    context,
                    '${l.toastSpeed} ${_fmt(ref.read(signSpeedProvider))}x',
                  );
                },
                child: Text(
                  speedLabel,
                  style: t.chip.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // sign rule 5: in debug builds, a sign not yet checked against a
        // reference says so
        if (kDebugMode && sign != null && !sign.verified)
          const PositionedDirectional(
            top: 52,
            start: 12,
            child: ReviewMarker(),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AvatarCaptionBox(
            key: const ValueKey('mission-caption'),
            label: l.watch(name),
            onHeight: (h) => runtime?.controller.reframe(captionHeight: h),
            // quiz: no word (it's the question); practice: the word
            child: Text(
              step is PracticeStep ? word : ' ',
              textAlign: TextAlign.center,
              style: t.caption,
            ),
          ),
        ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
}

/// `#missionCta`: Check / Next, Sign now (counting, Try again, Next), the
/// glove's action and "Continue without practice", Back to Learn.
class _Cta extends ConsumerWidget {
  const new({required this.moduleId, required this.state});

  final String moduleId;
  final MissionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctl = ref.read(missionControllerProvider(moduleId).notifier);
    final step = state.step;
    final List<Widget> children;
    if (state.result != null) {
      children = [
        IsharaButton(
          key: const ValueKey('mission-back'),
          label: l.backToLearn,
          kind: IsharaButtonKind.violet,
          arrow: true,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.learn),
        ),
      ];
    } else if (step is QuizStep) {
      children = [
        IsharaButton(
          key: const ValueKey('mission-check'),
          label: state.checked ? l.next : l.checkAnswer,
          arrow: state.checked,
          onPressed: state.checked
              ? ctl.next
              : state.picked == null
              ? null
              : ctl.check,
        ),
      ];
    } else if (step is PracticeStep) {
      children = _practice(context, l, ctl);
    } else {
      children = const [];
    }
    return CtaBar(children: children);
  }

  List<Widget> _practice(
    BuildContext context,
    AppLocalizations l,
    MissionController ctl,
  ) {
    final p = state.practice;
    if (p == null) return const [];
    final finished =
        p.phase == PracticePhase.passed || p.phase == PracticePhase.failed;
    if (finished) {
      return [
        IsharaButton(
          key: const ValueKey('mission-next'),
          label: l.next,
          kind: p.phase == PracticePhase.passed
              ? IsharaButtonKind.ok
              : IsharaButtonKind.primary,
          arrow: true,
          onPressed: ctl.next,
        ),
      ];
    }
    final block = state.block;
    if (block != null) {
      return [
        ?blockAction(context, l, block, ctl.leaveForGlove),
        IsharaLink(
          key: const ValueKey('mission-skip'),
          label: l.skipPractice,
          onPressed: ctl.skipPractice,
        ),
      ];
    }
    if (p.phase == PracticePhase.counting) {
      return [
        _CountingButton(
          key: ValueKey('mission-counting-${p.attempt}'),
          label: '${l.holdSign} ${p.secondsLeft}',
          start: p.progress,
        ),
      ];
    }
    return [
      IsharaButton(
        key: const ValueKey('mission-sign'),
        label: p.phase == PracticePhase.retry ? l.again : l.signNow,
        onPressed: ctl.signNow,
      ),
    ];
  }
}

/// The glove's action for a practice block (S8-1): Connect → Pair,
/// Calibrate now → Calibrate; none while reconnecting or stopped. Both come
/// back to this step, its attempts reset (S8-8, [onLeave]).
Widget? blockAction(
  BuildContext context,
  AppLocalizations l,
  PracticeBlock block,
  VoidCallback onLeave,
) => switch (block) {
  PracticeBlock.noGlove || PracticeBlock.mpuFail => IsharaButton(
    key: const ValueKey('mission-connect'),
    label: l.connect,
    onPressed: () {
      onLeave();
      unawaited(context.push(AppRoutes.pairBack(1)));
    },
  ),
  PracticeBlock.notCalibrated => IsharaButton(
    key: const ValueKey('mission-calibrate'),
    label: l.ctaCalNow,
    onPressed: () {
      onLeave();
      unawaited(context.push(AppRoutes.calibrateBack(1)));
    },
  ),
  PracticeBlock.reconnecting || PracticeBlock.stopped => null,
};

/// `.btn.counting` with its `.ring` filling over the 8 s window, animated
/// here (the controller only publishes whole seconds). One per attempt.
class _CountingButton extends StatefulWidget {
  const new({required this.label, required this.start, super.key});

  final String label;

  /// How much of the window had passed when this attempt was shown.
  final double start;

  @override
  State<_CountingButton> createState() => _CountingButtonState();
}

class _CountingButtonState extends State<_CountingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: LearnRules.practiceWindow,
    value: widget.start,
  )..forward();

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fill,
    builder: (context, _) => IsharaButton(
      key: const ValueKey('mission-sign'),
      label: widget.label,
      kind: IsharaButtonKind.counting,
      progress: _fill.value,
      onPressed: () {},
    ),
  );
}
