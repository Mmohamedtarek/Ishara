import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-ready`: done (or skipped calibration), the glove and the
/// answers, then Talk. No "96 % accuracy" (Q-K5). Reaching it finishes
/// onboarding: the app starts on Talk from now on (S6-2).
class ReadyScreen extends ConsumerStatefulWidget {
  const new({this.skipped = false, super.key});

  /// Calibration was skipped (prototype `state.calibrated === false`).
  final bool skipped;

  @override
  ConsumerState<ReadyScreen> createState() => _ReadyScreenState();
}

class _ReadyScreenState extends ConsumerState<ReadyScreen> {
  @override
  void initState() {
    super.initState();
    // after the first frame: providers can't change while the tree builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(profileControllerProvider.notifier).finishOnboarding(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final profile = ref.watch(profileControllerProvider);
    final glove =
        ref.watch(gloveStatusProvider).value ??
        ref.read(gloveSourceProvider).status;
    final sign = ref.watch(activeSignLanguageProvider);
    final name = glove.device?.name ?? profile.glove?.name;
    final skipped = widget.skipped;
    final battery = glove.battery;
    final gloveLine = switch (battery) {
      BatteryEvent(level: BatteryLevel.ok, percent: final p?) => l.sumGloveBatt(
        p,
      ),
      BatteryEvent(level: BatteryLevel.low) => l.sumGloveLow,
      BatteryEvent(level: BatteryLevel.usb) => l.sumGloveUsb,
      _ => l.connected,
    };
    final connected = glove.phase == GlovePhase.ready;
    return OnboardingPage(
      screenKey: 'ready',
      top: const OnboardingTopBar(),
      body: [
        // .done-hero: padding 14 0 6, centred
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Column(
            children: [
              const _BigCheck(),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  skipped ? l.doneTitleSkip : l.doneTitle,
                  textAlign: TextAlign.center,
                  style: t.h1,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                skipped ? l.doneLeadSkip : l.doneLead,
                textAlign: TextAlign.center,
                style: t.lead,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (name != null) ...[
          InfoRow(
            key: const ValueKey('ready-glove'),
            icon: 'bt',
            title: name,
            subtitle: connected ? gloveLine : null,
            value: connected ? l.ready : null,
            valueColor: c.okSoft,
          ),
          const SizedBox(height: 8),
        ],
        InfoRow(
          key: const ValueKey('ready-answers'),
          icon: 'hand',
          teal: true,
          title: sign == SignLanguage.asl ? l.asl : l.arsl,
          subtitle:
              '${profile.spoken == SpokenLanguage.ar ? l.voiceAr : l.voiceEn}'
              ' · '
              '${profile.role == UserRole.sign ? l.roleSign : l.roleSpeak}',
        ),
      ],
      cta: CtaBar(
        children: [
          IsharaButton(
            key: const ValueKey('ready-talk'),
            kind: IsharaButtonKind.violet,
            label: l.ctaTalk,
            arrow: true,
            onPressed: () => context.go(AppRoutes.talk),
          ),
          IsharaLink(
            key: const ValueKey('ready-calibrate'),
            label: skipped ? l.ctaCalNow : l.ctaRedo,
            onPressed: () => context.push(AppRoutes.calibrate),
          ),
        ],
      ),
    );
  }
}

/// `.bigcheck` (110 px): the circle draws in 1 s (after .1 s), the tick in
/// .5 s (after .8 s), a soft green glow pulses (2 s). Reduced motion: drawn.
class _BigCheck extends StatefulWidget {
  const new();

  @override
  State<_BigCheck> createState() => _BigCheckState();
}

class _BigCheckState extends State<_BigCheck> with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _draw.value = 1;
      _glow.stop();
    } else {
      if (_draw.value == 0 && !_draw.isAnimating) _draw.forward();
      if (!_glow.isAnimating) _glow.repeat();
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = context.colors.ok;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 110,
        child: AnimatedBuilder(
          animation: Listenable.merge([_draw, _glow]),
          builder: (context, _) {
            final s = _draw.value * 1.3; // seconds
            final circle = IsharaMotion.ease.transform(
              ((s - .1) / 1).clamp(0.0, 1.0),
            );
            final tick = Curves.ease.transform(((s - .8) / .5).clamp(0.0, 1.0));
            // glow: 50 % → opacity .5
            final glow = 1 - .5 * (1 - (2 * _glow.value - 1).abs());
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -14,
                  top: -14,
                  right: -14,
                  bottom: -14,
                  child: Opacity(
                    opacity: glow,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x594ABE84), Color(0x004ABE84)],
                          stops: [0, .65],
                        ),
                      ),
                    ),
                  ),
                ),
                CustomPaint(
                  size: const Size.square(110),
                  painter: _CheckPainter(circle: circle, tick: tick, ok: ok),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  new({required this.circle, required this.tick, required this.ok});

  final double circle;
  final double tick;
  final Color ok;

  @override
  void paint(Canvas canvas, Size size) {
    // circle r 56 (viewBox 120), stroke 5, drawn clockwise
    canvas
      ..scale(size.width / 120)
      ..drawArc(
        Rect.fromCircle(center: const Offset(60, 60), radius: 56),
        0,
        2 * math.pi * circle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = ok,
      );
    // check M36 62 l16 16 32-34, stroke 7
    final path = Path()
      ..moveTo(36, 62)
      ..lineTo(52, 78)
      ..lineTo(84, 44);
    for (final m in path.computeMetrics()) {
      canvas.drawPath(
        m.extractPath(0, m.length * tick),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ok,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.circle != circle || old.tick != tick || old.ok != ok;
}
