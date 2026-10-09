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
    with SingleTickerProviderStateMixin {
  // 0 → 1.7 s: pop-ins at 0 / .15 / .3 s (.6 s each), bar .2 → 1.7 s.
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.hold, _end);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _a.value = 1;
    } else if (!_a.isAnimating && _a.value == 0) {
      _a.forward();
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

  late final Animation<double> _markIn = _popAt(0);
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
    return Semantics(
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
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PopIn(animation: _markIn, child: const IsharaMark.splash()),
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
                    style: t.rowSubtitle.copyWith(fontSize: 14, color: c.muted),
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
        ),
      ),
    );
  }
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
    return Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(700 / r, 500 / r, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }
}
