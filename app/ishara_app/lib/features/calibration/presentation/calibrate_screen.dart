import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/calibration/application/calibration_controller.dart';
import 'package:ishara_app/features/calibration/presentation/calibrate_widgets.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-cal` (step 3 of 3): OPEN, FIST and TURN on the real glove
/// (BLE-CONTRACT §7), with the live hand, then `CAL SAVE` and Ready. Skip
/// only with a stored calibration (Q-K6).
class CalibrateScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CalibrateScreen> createState() => _CalibrateScreenState();
}

class _CalibrateScreenState extends ConsumerState<CalibrateScreen>
    with SingleTickerProviderStateMixin {
  // Drives the countdown; runs only while a step is capturing. The live
  // view redraws when samples arrive (`samplesSeen`).
  late final AnimationController _frame = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  bool _leaving = false;

  // Prototype SHAPES: what the drawing shows before the finger references
  // exist (it can't be live yet, Q-K7).
  static const _open = [.05, .05, .05, .05, .05];
  static const _fist = [.86, .94, .96, .93, .9];

  @override
  void dispose() {
    _frame.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return; // Back tapped twice, or Back and a swipe
    _leaving = true;
    await ref.read(calibrationControllerProvider.notifier).leave();
    if (mounted) context.pop();
  }

  Future<void> _skip() async {
    final l = AppLocalizations.of(context);
    final ok = await ref.read(calibrationControllerProvider.notifier).skip();
    if (!ok || !mounted) return;
    showToast(context, l.toastSkip);
    context.go(AppRoutes.readyAfter(skipped: true));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(calibrationControllerProvider);
    final ctl = ref.read(calibrationControllerProvider.notifier);
    ref.listen(calibrationControllerProvider, (prev, next) {
      if (next.phase == StepPhase.capturing) {
        if (!_frame.isAnimating) _frame.repeat();
      } else if (_frame.isAnimating) {
        _frame.stop();
      }
      if (next.phase == StepPhase.saved && prev?.phase != StepPhase.saved) {
        context.go(AppRoutes.readyAfter(skipped: false));
      }
    });
    final n = s.step.index + 1;
    final lead = switch (s.step) {
      CalStep.open => l.pose1s,
      CalStep.fist => l.pose2s,
      CalStep.turn => l.pose3s3,
    };
    final title = switch (s.step) {
      CalStep.open => l.pose1,
      CalStep.fist => l.pose2,
      CalStep.turn => l.pose3,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: OnboardingPage(
        screenKey: 'calibrate',
        top: OnboardingTopBar(back: true, step: 2, onBack: _leave),
        body: [
          PageTitle(title, eyebrow: l.stepOf(n), lead: lead),
          ValueListenableBuilder(
            valueListenable: ctl.samplesSeen,
            builder: (context, _, _) {
              final hand = ctl.hand;
              final live = hand.fingers;
              final illustrate =
                  s.step == CalStep.fist &&
                      (s.phase == StepPhase.capturing ||
                          s.phase == StepPhase.captured)
                  ? _fist
                  : _open;
              final holding =
                  s.step != CalStep.turn &&
                  (s.phase == StepPhase.idle || s.phase == StepPhase.capturing);
              return HandCard(
                bend: s.showFingers && live != null ? live : illustrate,
                bars: s.showFingers ? live : null,
                still: holding && s.connected ? hand.still : null,
                rotation: s.step == CalStep.turn ? hand.rotation : null,
                turning: s.step == CalStep.turn,
                live: s.connected && hand.latest != null,
              );
            },
          ),
          PoseChips(current: s.step, done: s.done),
          ?_problem(l, s),
          if (s.weakFingers.isNotEmpty)
            NoticeCard(
              key: const ValueKey('cal-weak'),
              icon: 'hand',
              title: l.weakTitle,
              body: l.weakBody(_fingerNames(l, s.weakFingers)),
            ),
          if (!s.canSkip && s.phase != StepPhase.saved)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l.skipNeedsCal,
                key: const ValueKey('cal-skip-hidden'),
                textAlign: TextAlign.center,
                style: context.text.rowSubtitle.copyWith(
                  fontSize: 12.5,
                  color: context.colors.muted,
                ),
              ),
            ),
        ],
        cta: CtaBar(
          children: [
            _CaptureButton(state: s, frame: _frame, onCapture: _action),
            if (s.canSkip && s.phase != StepPhase.saved)
              IsharaLink(
                key: const ValueKey('cal-skip'),
                label: l.ctaSkip,
                onPressed: s.phase == StepPhase.capturing ? null : _skip,
              ),
          ],
        ),
      ),
    );
  }

  void _action() {
    final s = ref.read(calibrationControllerProvider);
    final ctl = ref.read(calibrationControllerProvider.notifier);
    if (!s.connected) {
      unawaited(context.push(AppRoutes.pair));
      return;
    }
    // CAL SAVE failed: the glove still has the three steps; save again.
    if (s.phase == StepPhase.failed && s.done.contains(CalStep.turn)) {
      unawaited(ctl.retrySave());
      return;
    }
    unawaited(ctl.capture());
  }

  static String _fingerNames(AppLocalizations l, List<int> fingers) {
    final names = [l.fThumb, l.fIndex, l.fMiddle, l.fRing, l.fPinky];
    final sep = l.localeName == 'ar' ? '، ' : ', ';
    return fingers.map((i) => names[i]).join(sep);
  }

  Widget? _problem(AppLocalizations l, CalibrationState s) {
    if (s.phase != StepPhase.failed) return null;
    if (!s.connected) {
      return NoticeCard(
        key: const ValueKey('cal-disconnected'),
        icon: 'bt',
        title: l.disconnectedTitle,
        body: l.disconnectedBody,
      );
    }
    final (title, body) = switch (s.reason) {
      'MOVED' => (l.failMovedTitle, l.failMovedBody),
      'RANGE' => (l.failRangeTitle, l.failRangeBody),
      'MPU' => (l.mpuTitle, l.mpuBody),
      'CANCELLED' => (l.failCancelledTitle, l.failCancelledBody),
      _ => switch (s.failure) {
        GloveCommandRejectedFailure(:final error) when error.reason == 'BUSY' =>
          (l.busyTitle, l.busyBody),
        GloveCommandRejectedFailure() ||
        GloveBadCalibrationFailure() => (l.saveFailTitle, l.saveFailBody),
        _ => (l.linkLostTitle, l.linkLostBody),
      },
    };
    return NoticeCard(
      key: ValueKey('cal-fail-${s.reason ?? s.failure?.kind}'),
      icon: s.reason == 'MPU' ? 'bt' : 'hand',
      title: title,
      body: body,
    );
  }
}

/// `#calCta`: Start capture → counting (fill + "Hold still… n" / "Keep
/// turning… n") → Captured ✓; Saving…; Try again / Pair again.
class _CaptureButton extends StatelessWidget {
  const new({
    required this.state,
    required this.frame,
    required this.onCapture,
  });

  final CalibrationState state;
  final Animation<double> frame;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = state;
    switch (s.phase) {
      case StepPhase.capturing:
        return AnimatedBuilder(
          animation: frame,
          builder: (context, _) {
            final total = CalibrationState.durationOf(s.step);
            final elapsed = clock.now().difference(s.startedAt ?? clock.now());
            final p = (elapsed.inMilliseconds / total.inMilliseconds).clamp(
              0.0,
              1.0,
            );
            final left = ((total - elapsed).inMilliseconds / 1000).ceil().clamp(
              0,
              total.inSeconds,
            );
            return IsharaButton(
              key: const ValueKey('cal-cta'),
              kind: IsharaButtonKind.counting,
              progress: p,
              label: '${s.step == CalStep.turn ? l.ctaTurn : l.ctaHold} $left',
              onPressed: () {},
            );
          },
        );
      case StepPhase.captured:
      case StepPhase.saved:
        return IsharaButton(
          key: const ValueKey('cal-cta'),
          kind: IsharaButtonKind.ok,
          label: '${l.ctaCaptured} ✓',
          onPressed: () {},
        );
      case StepPhase.saving:
        return IsharaButton(
          key: const ValueKey('cal-cta'),
          kind: IsharaButtonKind.counting,
          label: l.saving,
          busy: true,
          onPressed: () {},
        );
      case StepPhase.failed:
        return IsharaButton(
          key: const ValueKey('cal-cta'),
          label: s.connected ? l.tryAgain : l.pairAgain,
          arrow: !s.connected,
          onPressed: onCapture,
        );
      case StepPhase.idle:
        return IsharaButton(
          key: const ValueKey('cal-cta'),
          label: l.ctaCapture,
          onPressed: s.connected ? onCapture : null,
        );
    }
  }
}
