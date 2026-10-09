import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/ishara_mark.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#splash`: the mark, the name "Ishara" (Latin letters in both
/// languages), the tagline and the loading bar, popping in one after the
/// other; after 2.1 s (or a tap) the app moves on to Welcome.
class SplashScreen extends StatefulWidget {
  const new({super.key, this.hold = const Duration(milliseconds: 2100)});

  /// How long the splash stays (prototype `setTimeout(endSplash, 2100)`).
  final Duration hold;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // 0 → 1.7 s: pop-ins at 0 / .15 / .3 s (.6 s each), bar .2 → 1.7 s.
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  /// The mark's 300 ms move (prototype easing), on its own clock so the
  /// layout follows it only while it moves.
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _markMove = _move.drive(
    CurveTween(curve: IsharaMotion.ease),
  );
  Timer? _timer;
  bool _done = false;
  bool _shown = false;
  bool _startScheduled = false;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _start();
  }

  /// The splash's time starts after its first frame with a real size, not
  /// when it is built: on a cold start Android first lays the window out at
  /// 0 x 0 behind its own splash, and that can take longer than the splash.
  /// Called from layout; runs once, after that frame.
  void _onLaidOut(Size size) {
    if (_shown || _startScheduled || size.isEmpty) return;
    _startScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shown = true;
      _timer = Timer(widget.hold, _end);
      _start();
    });
  }

  void _start() {
    if (_reduce) {
      _a.value = 1;
      _move.value = 1;
    } else if (_shown && !_a.isAnimating && _a.value == 0) {
      _a.forward();
      _move.forward();
    }
  }

  void _end() {
    if (_done || !mounted) return;
    _done = true;
    context.go(AppRoutes.welcome);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _a.dispose();
    _move.dispose();
    super.dispose();
  }

  /// `popin .6s <delay> cubic-bezier(.2,.8,.2,1) both` on the 1.7 s clock.
  /// drive() adds no listener of its own, so these are made once.
  Animation<double> _popAt(double delayS) => _a.drive(
    CurveTween(
      curve: Interval(
        delayS / 1.7,
        (delayS + .6) / 1.7,
        curve: IsharaMotion.ease,
      ),
    ),
  );

  late final Animation<double> _nameIn = _popAt(.15);
  late final Animation<double> _tagIn = _popAt(.3);

  /// `.bar i { animation: load 1.5s .2s ease forwards }`.
  late final Animation<double> _bar = _a.drive(
    CurveTween(curve: const Interval(.2 / 1.7, 1, curve: Curves.ease)),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Material: the texts get the theme's text style (no debug fallback).
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        label: 'Ishara. ${l.tagline}',
        excludeSemantics: true,
        onTap: _end,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _end,
          child: DecoratedBox(
            key: const ValueKey('screen-splash'),
            decoration: BoxDecoration(
              color: c.bg,
              // radial-gradient(700px 500px at 50% 30%, A 0%, var(--bg) 65%)
              gradient: RadialGradient(
                center: const Alignment(0, -.4),
                radius: 1,
                colors: [
                  // dark: #1E2340 (splash only); light: #EFECE4 = stageB
                  if (dark) const Color(0xFF1E2340) else c.stageB,
                  c.bg,
                ],
                stops: const [0, .65],
                transform: const _Ellipse(),
              ),
            ),
            // The whole group is centred (prototype); the mark is laid out
            // by _SplashLayout so it can travel from the screen centre.
            child: CustomMultiChildLayout(
              delegate: _SplashLayout(_markMove, onLaidOut: _onLaidOut),
              children: [
                LayoutId(
                  id: _Part.group,
                  child: Column(
                    // only as tall as its content: the delegate centres it
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // the mark's place (the delegate puts the mark here)
                      const SizedBox.square(dimension: 88),
                      const SizedBox(height: 14),
                      PopIn(
                        animation: _nameIn,
                        child: Text(
                          // The app name is "Ishara" in Latin letters in every
                          // language (user decision).
                          'Ishara',
                          style: t.brand.copyWith(
                            fontSize: 34,
                            letterSpacing: t.isArabic ? 0 : -.02 * 34,
                            color: c.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      PopIn(
                        animation: _tagIn,
                        child: Text(
                          l.tagline,
                          style: t.rowSubtitle.copyWith(
                            fontSize: 14,
                            color: c.muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // .bar: 120 x 4, radius 2; fill teal → violet over 1.5 s
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Container(
                          width: 120,
                          height: 4,
                          color: c.track,
                          alignment: AlignmentDirectional.centerStart,
                          child: AnimatedBuilder(
                            animation: _bar,
                            builder: (context, _) => FractionallySizedBox(
                              widthFactor: _bar.value,
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [c.teal, c.violet],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LayoutId(id: _Part.mark, child: const IsharaMark.splash()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Part { group, mark }

/// Centres the group on the screen and puts the mark between the screen
/// centre (where the native launch screen shows it, [move] = 0) and its
/// place at the top of the group ([move] = 1). Computed from the real size
/// at every layout, so a late window size can't leave it stale.
class _SplashLayout extends MultiChildLayoutDelegate {
  new(this.move, {required this.onLaidOut}) : super(relayout: move);

  final Animation<double> move;

  /// Told the size at every layout (the splash starts at the first real one).
  final ValueChanged<Size> onLaidOut;

  @override
  void performLayout(Size size) {
    onLaidOut(size);
    final g = layoutChild(_Part.group, BoxConstraints.loose(size));
    final top = Offset(
      (size.width - g.width) / 2,
      (size.height - g.height) / 2,
    );
    positionChild(_Part.group, top);
    if (hasChild(_Part.mark)) {
      layoutChild(_Part.mark, BoxConstraints.tight(const Size.square(88)));
      final x = (size.width - 88) / 2;
      final centre = Offset(x, (size.height - 88) / 2);
      final place = Offset(x, top.dy);
      positionChild(_Part.mark, Offset.lerp(centre, place, move.value)!);
    }
  }

  @override
  bool shouldRelayout(_SplashLayout old) => old.move != move;
}

/// CSS `radial-gradient(700px 500px at 50% 30%, …)`: the gradient's circle
/// (radius = the box's shortest side) stretched into a 700 x 500 px ellipse
/// around its centre.
class _Ellipse extends GradientTransform {
  const new();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final cx = bounds.left + bounds.width * .5;
    final cy = bounds.top + bounds.height * .3;
    final r = bounds.shortestSide;
    // a window can be 0 x 0 before its first real size (seen on Android)
    if (r <= 0) return Matrix4.identity();
    return Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(700 / r, 500 / r, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }
}
