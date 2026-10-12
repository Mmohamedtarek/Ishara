import 'package:flutter/material.dart';

/// A box with a 1 px dashed border (CSS `border: 1px dashed`), as the
/// prototype's `.mic-signs` and `.live-box`.
class DashedBox extends StatelessWidget {
  const new({
    required this.color,
    required this.borderColor,
    required this.radius,
    required this.padding,
    required this.child,
    super.key,
  });

  final Color color;
  final Color borderColor;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedRRect(borderColor, radius),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    ),
  );
}

class _DashedRRect extends CustomPainter {
  new(this.color, this.radius);

  final Color color;
  final double radius;

  // Chrome draws 1 px dashes about 3 px long with 3 px gaps.
  static const _dash = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.5),
      Radius.circular(radius),
    );
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += _dash * 2) {
        canvas.drawPath(m.extractPath(d, d + _dash), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}
