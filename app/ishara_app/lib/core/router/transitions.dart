import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';

/// How a screen enters, as in the prototype CSS.
enum ScreenEntrance {
  /// `.screen`: fade in while sliding 22 px in from the end side
  /// (from the start side in RTL).
  slide,

  /// `.screen.pop`: fade in, rise 14 px and grow from 98 % (Ready, Mission).
  pop,
}

/// A page that moves like the prototype's `show()`:
/// * push: the covered screen disappears at once and the new screen plays its
///   entrance (0.38 s, cubic-bezier(.2,.8,.2,1));
/// * back: the leaving screen disappears at once and the revealed screen plays
///   its own entrance again.
/// With reduced motion (system setting) screens switch at once, like the
/// prototype's `prefers-reduced-motion` rule.
CustomTransitionPage<void> isharaPage({
  required LocalKey key,
  required Widget child,
  ScreenEntrance entrance = ScreenEntrance.slide,
}) => CustomTransitionPage<void>(
  key: key,
  child: child,
  transitionDuration: IsharaMotion.screen,
  reverseTransitionDuration: IsharaMotion.screen,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      PrototypeRouteTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        entrance: entrance,
        child: child,
      ),
);

/// Route transition with the prototype's semantics (see [isharaPage]).
///
/// [animation] runs 0 -> 1 when this route is pushed and 1 -> 0 when it is
/// popped. [secondaryAnimation] runs 0 -> 1 when another route covers this one
/// and 1 -> 0 when that route is popped, revealing this one again.
class PrototypeRouteTransition extends StatelessWidget {
  const new({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    this.entrance = ScreenEntrance.slide,
    super.key,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final ScreenEntrance entrance;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([animation, secondaryAnimation]),
    child: child,
    builder: (context, child) {
      // Leaving (popped): hidden at once.
      if (animation.status == AnimationStatus.reverse) {
        return _hidden(child!);
      }
      final sec = secondaryAnimation;
      // Being covered by a new screen: hidden at once.
      if (sec.value > 0 &&
          (sec.status == AnimationStatus.forward ||
              sec.status == AnimationStatus.completed)) {
        return _hidden(child!);
      }
      // Revealed by Back: replay this screen's entrance.
      final progress = sec.status == AnimationStatus.reverse
          ? ReverseAnimation(sec)
          : animation;
      return ScreenEntranceTransition(
        animation: progress,
        entrance: entrance,
        child: child!,
      );
    },
  );

  static Widget _hidden(Widget child) =>
      IgnorePointer(child: Opacity(opacity: 0, child: child));
}

/// The entrance animation itself, reusable for tab switches.
class ScreenEntranceTransition extends StatelessWidget {
  const new({
    required this.animation,
    required this.child,
    this.entrance = ScreenEntrance.slide,
    super.key,
  });

  final Animation<double> animation;
  final Widget child;
  final ScreenEntrance entrance;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // drive() adds no listener of its own (a CurvedAnimation built here would
    // leave one on the parent at every rebuild).
    final t = animation.drive(CurveTween(curve: IsharaMotion.ease));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final v = t.value;
        final Matrix4 m;
        switch (entrance) {
          case ScreenEntrance.slide:
            final dx = (1 - v) * IsharaMotion.slideOffset * (rtl ? -1 : 1);
            m = Matrix4.translationValues(dx, 0, 0);
          case ScreenEntrance.pop:
            final s = IsharaMotion.popScale + (1 - IsharaMotion.popScale) * v;
            m = Matrix4.translationValues(
              0,
              (1 - v) * IsharaMotion.popOffset,
              0,
            )..scaleByDouble(s, s, 1, 1);
        }
        return Opacity(
          opacity: v.clamp(0, 1),
          child: Transform(
            transform: m,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }
}
