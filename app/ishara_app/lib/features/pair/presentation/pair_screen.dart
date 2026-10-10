import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/features/pair/application/pair_controller.dart';
import 'package:ishara_app/features/pair/presentation/pair_widgets.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-pair` (step 2 of 3): find the glove, connect with the three
/// real checks (Q-K3), then calibrate. Adds the states the prototype lacks
/// (permissions, Bluetooth off, not found, failed checks).
class PairScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen>
    with WidgetsBindingObserver {
  bool _tips = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(pairControllerProvider);
      if (s.stage != PairStage.connected) {
        unawaited(ref.read(pairControllerProvider.notifier).start());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the phone's settings (permission or Bluetooth changed there):
  /// check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final s = ref.read(pairControllerProvider);
    if (s.stage == PairStage.permissionDenied ||
        s.stage == PairStage.bluetoothProblem) {
      unawaited(ref.read(pairControllerProvider.notifier).start());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final s = ref.watch(pairControllerProvider);
    final ctl = ref.read(pairControllerProvider.notifier);

    final (status, sub) = switch (s.stage) {
      PairStage.permission || PairStage.scanning => (l.scanning, l.scanningSub),
      PairStage.found => (l.found, l.foundSub),
      PairStage.connecting => (l.connecting, l.connectingSub),
      PairStage.connected => (l.connected, l.connectedSub),
      PairStage.notFound => (l.notFound, l.notFoundSub),
      PairStage.permissionDenied ||
      PairStage.bluetoothProblem ||
      PairStage.failed => (null, null),
    };

    final selected = s.status.device;
    final cards = switch (s.stage) {
      PairStage.found => [
        for (final g in s.gloves)
          GloveCard(glove: g, state: s, onConnect: () => ctl.connect(g)),
      ],
      PairStage.connecting || PairStage.connected || PairStage.failed
          when selected != null =>
        [GloveCard(glove: selected, state: s, onConnect: null)],
      _ => const <Widget>[],
    };

    final showTips =
        s.stage == PairStage.notFound ||
        (_tips &&
            (s.stage == PairStage.scanning || s.stage == PairStage.found));
    final scanAgain =
        s.stage == PairStage.connected ||
        s.stage == PairStage.notFound ||
        s.stage == PairStage.failed ||
        s.stage == PairStage.bluetoothProblem;

    return OnboardingPage(
      screenKey: 'pair',
      top: const OnboardingTopBar(back: true, step: 1),
      body: [
        PageTitle(l.pairTitle, lead: l.pairLeadTrue),
        PairRadar(found: s.stage == PairStage.connected),
        if (status != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(
                status,
                key: const ValueKey('pair-status'),
                textAlign: TextAlign.center,
                style: t.rowTitle.copyWith(fontSize: 16, color: c.ink),
              ),
            ),
          ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              sub,
              textAlign: TextAlign.center,
              style: t.rowSubtitle.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
        for (final (i, card) in cards.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          card,
        ],
        ?_notice(context, s, ctl),
        if (showTips) const PairTips(),
      ],
      cta: CtaBar(
        children: [
          IsharaButton(
            key: const ValueKey('pair-cta'),
            label: switch (s.stage) {
              PairStage.connected => l.ctaCal,
              PairStage.found || PairStage.connecting => l.ctaConnectFirst,
              _ => l.ctaConnect,
            },
            arrow: true,
            onPressed: s.stage == PairStage.connected
                ? () => context.push(AppRoutes.calibrate)
                : null,
          ),
          if (scanAgain)
            IsharaLink(
              key: const ValueKey('pair-scan-again'),
              label: l.ctaAgain,
              onPressed: () {
                setState(() => _tips = false);
                unawaited(ctl.scanAgain());
              },
            )
          else if (s.stage == PairStage.scanning || s.stage == PairStage.found)
            IsharaLink(
              key: const ValueKey('pair-help'),
              label: l.ctaHelp,
              onPressed: () => setState(() => _tips = !_tips),
            ),
        ],
      ),
    );
  }

  /// The card for the states the prototype lacks.
  Widget? _notice(BuildContext context, PairState s, PairController ctl) {
    final l = AppLocalizations.of(context);
    switch (s.stage) {
      case PairStage.permissionDenied:
        final forGood = s.permission == GlovePermission.permanentlyDenied;
        return NoticeCard(
          key: const ValueKey('pair-permission'),
          icon: 'bt',
          title: l.permTitle,
          body: forGood ? l.permBodySettings : l.permBody,
          action: IsharaButton(
            label: forGood ? l.openSettings : l.allow,
            small: true,
            onPressed: forGood ? ctl.openSettings : ctl.start,
          ),
        );
      case PairStage.bluetoothProblem:
        final (title, body) = switch (s.bluetooth) {
          BluetoothProblem.off => (l.btOffTitle, l.btOffBody),
          BluetoothProblem.locationOff => (l.locOffTitle, l.locOffBody),
          BluetoothProblem.unauthorized => (l.permTitle, l.permLocationBody),
          BluetoothProblem.unsupported => (l.btOffTitle, l.btUnsupported),
          BluetoothProblem.notReady || null => (l.btOffTitle, l.btNotReady),
        };
        return NoticeCard(
          key: const ValueKey('pair-bluetooth'),
          icon: 'bt',
          title: title,
          body: body,
        );
      case PairStage.failed:
        final (title, body) = s.mpuFail
            ? (l.mpuTitle, l.mpuBody)
            : switch (s.failure) {
                GloveProtocolMismatchFailure() => (l.protoTitle, l.protoBody),
                GloveConnectFailure() => (l.connFailTitle, l.connFailBody),
                _ => (l.linkLostTitle, l.linkLostBody),
              };
        return NoticeCard(
          key: const ValueKey('pair-failed'),
          icon: 'bt',
          title: title,
          body: body,
          action: IsharaButton(
            key: const ValueKey('pair-try-again'),
            label: l.tryAgain,
            small: true,
            kind: IsharaButtonKind.ghost,
            onPressed: ctl.scanAgain,
          ),
        );
      case PairStage.permission ||
          PairStage.scanning ||
          PairStage.found ||
          PairStage.notFound ||
          PairStage.connecting ||
          PairStage.connected:
        return null;
    }
  }
}
