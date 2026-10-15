import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

// The live hand, shared by Calibrate and Learn's practice step.

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
    final dark = Theme.of(context).brightness == Brightness.dark;
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

/// The prototype's `HAND_SVG` (viewBox 200 × 220): ghost outlines, palm,
/// fingers that shorten with bend (`scaleY(1 − .62 v)` from the base,
/// "bent" over .45), the thumb turned −42°, the sensor box and its knob.
class HandPainter extends CustomPainter {
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
  bool shouldRepaint(HandPainter old) =>
      old.dark != dark || !_same(old.bend, bend);

  static bool _same(List<double?> a, List<double?> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return a.length == b.length;
  }
}
