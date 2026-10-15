import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/hand_drawing.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

bool _dark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// `.handcard`: "Live from your glove" + LIVE, the hand drawing with the
/// finger bars (Q-K7: only once OPEN and FIST are done), the hold-still
/// indicator (Q-K7, OPEN / FIST) and the rotation track (TURN).
class HandCard extends StatelessWidget {
  const new({
    required this.bend,
    required this.bars,
    required this.still,
    required this.rotation,
    required this.turning,
    required this.live,
    super.key,
  });

  /// Bend per finger for the drawing, 0 open … 1 fist (null = no value).
  final List<double?> bend;

  /// Values for the finger bars, or null to hide them (Q-K7).
  final List<double?>? bars;

  /// Hold-still indicator: null hides it.
  final bool? still;

  /// Wrist rotation in degrees (TURN), null hides the track.
  final double? rotation;

  /// TURN: the drawing turns with the wrist.
  final bool turning;

  /// Samples are arriving (the LIVE badge blinks).
  final bool live;

  /// The hand drawing turns at most this far (prototype maximum).
  static const maxDrawnTurnDeg = 33.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = _dark(context);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final labelStyle = t.question.copyWith(
      fontSize: arabic ? 12 : 11.5,
      letterSpacing: arabic ? 0 : .03 * 11.5,
      color: c.muted,
    );
    String up(String s) => arabic ? s : s.toUpperCase();
    final rot = rotation;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.line),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0x246F7CF0), Color(0x991B1D24)]
              : const [Color(0x1424309A), Color(0x99FFFFFF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(up(l.liveFrom), style: labelStyle)),
              if (live) _LiveBadge(text: up(l.live), style: labelStyle),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Transform.rotate(
                // the prototype's drawing peaks at ±33° (setYaw 34 with
                // its easing); the number below keeps the real angle
                angle: turning && rot != null
                    ? rot.clamp(-maxDrawnTurnDeg, maxDrawnTurnDeg) *
                          math.pi /
                          180
                    : 0,
                alignment: const Alignment(.04, .84), // 52 % 92 %
                child: SizedBox(
                  width: 150,
                  height: 170,
                  child: CustomPaint(
                    painter: HandPainter(bend: bend, dark: dark),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: bars == null
                    ? Text(
                        l.fingersLater,
                        style: t.rowSubtitle.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: c.muted,
                        ),
                      )
                    : FingerBars(values: bars!),
              ),
            ],
          ),
          if (still case final s?)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _StillPill(still: s),
            ),
          if (rot != null) YawTrack(degrees: rot),
        ],
      ),
    );
  }
}

/// `.live`: violet text with a blinking dot.
class _LiveBadge extends StatefulWidget {
  const new({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
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
    final c = context.colors;
    final dark = _dark(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _a,
          builder: (context, child) => Opacity(
            // blink: 50 % → .3
            opacity: 1 - .7 * (1 - (2 * _a.value - 1).abs()),
            child: child,
          ),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.violet,
              boxShadow: dark
                  ? [BoxShadow(color: c.violet, blurRadius: 8)]
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(widget.text, style: widget.style.copyWith(color: c.violetSoft)),
      ],
    );
  }
}

/// Q-K7: during OPEN / FIST, whether the hand is still enough (the glove's
/// own 3 °/s rule, `LiveHand.still`).
class _StillPill extends StatelessWidget {
  const new({required this.still});
  final bool still;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final color = still ? c.okSoft : c.amberSoft;
    return Semantics(
      liveRegion: true,
      child: Row(
        key: ValueKey('cal-still-$still'),
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: still ? c.ok : c.amber,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            still ? l.handStill : l.handMoving,
            style: context.text.chip.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.yaw`: "Rotation", a track with a 14 px marker (±40° spans the track,
/// as in the prototype) and the angle.
class YawTrack extends StatelessWidget {
  const new({required this.degrees, super.key});

  final double degrees;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final d = degrees.round();
    final style = t.chip.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: c.sub,
    );
    return Semantics(
      label: l.yawLbl,
      value: '$d°',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 6),
        child: Row(
          children: [
            Text(l.yawLbl, style: style),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  final x = (degrees / 40 * .5).clamp(-.5, .5) * w;
                  return Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0x2E7F7F7F),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: w / 2 - 7 + x,
                          top: 0,
                          bottom: 0,
                          width: 14,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(
                                colors: [c.teal, c.violet],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                '${d > 0 ? '+' : ''}$d°',
                textAlign: TextAlign.end,
                textDirection: TextDirection.ltr,
                style: style.copyWith(
                  color: c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.poses`: Open, Fist, Turn; done ones show a green check, the current
/// one is highlighted.
class PoseChips extends StatelessWidget {
  const new({required this.current, required this.done, super.key});

  final CalStep current;
  final Set<CalStep> done;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = _dark(context);
    final labels = [l.p1, l.p2, l.p3];
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          for (final step in CalStep.values) ...[
            if (step.index > 0) const SizedBox(width: 6),
            Expanded(
              child: Builder(
                builder: (context) {
                  final isDone = done.contains(step);
                  final on = step == current && !isDone;
                  return Semantics(
                    label: labels[step.index],
                    selected: on,
                    checked: isDone,
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: on ? const Color(0x148E9CFF) : c.glass,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: on ? const Color(0x99B7C0FF) : c.line,
                        ),
                        boxShadow: dark
                            ? null
                            : const [
                                BoxShadow(
                                  color: Color(0x0D15171C),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDone ? c.ok : null,
                              border: Border.all(
                                color: isDone
                                    ? c.ok
                                    : on
                                    ? c.teal
                                    : c.ring,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: isDone
                                  ? IsharaIcon(
                                      'check',
                                      size: 12,
                                      color: dark
                                          ? const Color(0xFF0E1440)
                                          : Colors.white,
                                    )
                                  : Text(
                                      '${step.index + 1}',
                                      style: context.text.chip.copyWith(
                                        fontSize: 11,
                                        color: on ? c.tealSoft : c.muted,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              labels[step.index],
                              overflow: TextOverflow.ellipsis,
                              style: context.text.chip.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: on
                                    ? c.ink
                                    : isDone
                                    ? c.sub
                                    : c.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
