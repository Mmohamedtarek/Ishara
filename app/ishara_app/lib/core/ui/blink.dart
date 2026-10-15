import 'package:flutter/material.dart';

/// `@keyframes blink` (50 %: opacity .3, 1 s) while [on]; reduced motion:
/// steady.
class Blink extends StatefulWidget {
  const new({required this.on, required this.child, super.key});

  final bool on;
  final Widget child;

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  void _sync() {
    final run = widget.on && !MediaQuery.disableAnimationsOf(context);
    if (run && !_a.isAnimating) {
      _a.repeat();
    } else if (!run && _a.isAnimating) {
      _a
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Blink old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (context, child) =>
        Opacity(opacity: 1 - .7 * (1 - (2 * _a.value - 1).abs()), child: child),
    child: widget.child,
  );
}
