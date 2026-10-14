import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
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
                    painter: _HandPainter(bend: bend, dark: dark),
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

/// `.fingers` / `.fr`: name, bar (teal → violet), percent. A finger without
/// a usable value (weak sensor) shows "—".
class FingerBars extends StatelessWidget {
  const new({required this.values, super.key});

  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = _dark(context);
    final names = [l.fThumb, l.fIndex, l.fMiddle, l.fRing, l.fPinky];
    final style = t.chip.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: c.sub,
    );
    return Column(
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(height: 7),
          Semantics(
            label: names[i],
            value: values[i] == null ? '—' : '${(values[i]! * 100).round()}%',
            excludeSemantics: true,
            child: Row(
              children: [
                SizedBox(width: 52, child: Text(names[i], style: style)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      height: 8,
                      color: dark ? c.track : const Color(0x1415171C),
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: values[i] ?? 0,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: [c.teal, c.violet],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    values[i] == null ? '—' : '${(values[i]! * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: style.copyWith(
                      color: c.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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

/// The prototype's `HAND_SVG` (viewBox 200 × 220): ghost outlines, palm,
/// fingers that shorten with bend (`scaleY(1 − .62 v)` from the base,
/// "bent" over .45), the thumb turned −42°, the sensor box and its knob.
class _HandPainter extends CustomPainter {
  new({required this.bend, required this.dark});

  final List<double?> bend;
  final bool dark;

  // finger rects: x, y, w, h, r (index, middle, ring, pinky); thumb inside
  // rotate(-42 56 130)
  static const _fingers = [
    (61.0, 30.0, 19.0, 76.0, 9.5),
    (84.0, 20.0, 19.0, 86.0, 9.5),
    (107.0, 26.0, 19.0, 80.0, 9.5),
    (130.0, 42.0, 18.0, 64.0, 9.0),
  ];
  static const _thumb = (47.0, 74.0, 19.0, 58.0, 9.5);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 200, size.height / 220);
    final ghost = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = dark ? const Color(0x24FFFFFF) : const Color(0x2415171C);
    final palmFill = Paint()
      ..color = dark ? const Color(0x0FFFFFFF) : const Color(0x0A15171C);
    final palmStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = dark ? const Color(0x59FFFFFF) : const Color(0x4D15171C);

    void dashed(RRect r) {
      final path = Path()..addRRect(r);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 8) {
          canvas.drawPath(m.extractPath(d, d + 4), ghost);
        }
      }
    }

    RRect rr((double, double, double, double, double) f) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(f.$1, f.$2, f.$3, f.$4),
          Radius.circular(f.$5),
        );

    void finger((double, double, double, double, double) f, double? v) {
      final value = v ?? 0;
      final bent = value > .45;
      final s = 1 - .62 * value;
      final r = Rect.fromLTWH(f.$1, f.$2 + f.$4 * (1 - s), f.$3, f.$4 * s);
      final shape = RRect.fromRectAndRadius(r, Radius.circular(f.$5));
      canvas
        ..drawRRect(
          shape,
          Paint()
            ..color = dark
                ? (bent ? const Color(0x8C6F7CF0) : const Color(0x478E9CFF))
                : (bent ? const Color(0x7324309A) : const Color(0x403446C9)),
        )
        ..drawRRect(
          shape,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = dark
                ? (bent ? const Color(0xFFC9CFFF) : const Color(0xE6B7C0FF))
                : (bent ? const Color(0xFF24309A) : const Color(0xE63446C9)),
        );
    }

    for (final f in _fingers) {
      dashed(rr(f));
    }
    canvas
      ..save()
      ..translate(56, 130)
      ..rotate(-42 * math.pi / 180)
      ..translate(-56, -130);
    dashed(rr(_thumb));
    canvas.restore();

    final palm = RRect.fromRectAndRadius(
      const Rect.fromLTWH(55, 100, 94, 96),
      const Radius.circular(30),
    );
    canvas
      ..drawRRect(palm, palmFill)
      ..drawRRect(palm, palmStroke);
    for (final (i, f) in _fingers.indexed) {
      finger(f, bend[i + 1]);
    }
    canvas
      ..save()
      ..translate(56, 130)
      ..rotate(-42 * math.pi / 180)
      ..translate(-56, -130);
    finger(_thumb, bend[0]);
    canvas.restore();

    // the glove's sensor box and its LED knob
    final box = RRect.fromRectAndRadius(
      const Rect.fromLTWH(86, 128, 32, 22),
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(box, Paint()..color = const Color(0xCC121318))
      ..drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x4DFFFFFF),
      )
      ..drawCircle(
        const Offset(112, 134),
        2.5,
        Paint()
          ..color = dark ? const Color(0xFF8E9CFF) : const Color(0xFF3446C9),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_HandPainter old) =>
      old.dark != dark || !_same(old.bend, bend);

  static bool _same(List<double?> a, List<double?> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return a.length == b.length;
  }
}
