import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/features/pair/application/pair_controller.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

bool _dark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// `.radar` (230 px): three rippling rings (2.4 s, 0.8 s apart), a sweep
/// (2.2 s turn, 70° fade, drawn in the 35-70 % band), a dashed grid and the
/// 84 px core with the blinking blue LED. [found]: green core, steady LED, no
/// rings or sweep. Reduced motion: no animation.
class PairRadar extends StatefulWidget {
  const new({required this.found, super.key});

  final bool found;

  @override
  State<PairRadar> createState() => _PairRadarState();
}

class _PairRadarState extends State<PairRadar>
    with SingleTickerProviderStateMixin {
  // One clock for every loop: 13.2 s is a whole number of 2.4 s, 2.2 s and
  // 1 s periods (lcm), so nothing jumps when it wraps.
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 13200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PairRadar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = !widget.found && !MediaQuery.disableAnimationsOf(context);
    if (run && !_t.isAnimating) {
      _t.repeat();
    } else if (!run && _t.isAnimating) {
      _t.stop();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    final found = widget.found;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Center(
          child: SizedBox.square(
            dimension: 230,
            child: AnimatedBuilder(
              animation: _t,
              builder: (context, _) {
                final s = _t.value * 13.2; // seconds
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size.square(230),
                      painter: _RadarPainter(
                        seconds: found || reduce ? null : s,
                        dark: dark,
                      ),
                    ),
                    _Core(
                      found: found,
                      ledOn: found || reduce || (s % 1) < .5,
                      color: found ? c.okSoft : c.tealSoft,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  new({required this.seconds, required this.dark});

  /// Time for the rings and the sweep; null = none (found / reduced motion).
  final double? seconds;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    // .grid: dashed circle and a dashed circle inset 18 %
    final gridColor = dark ? const Color(0x24FFFFFF) : const Color(0x2415171C);
    _dashedCircle(canvas, center, r - .5, gridColor);
    _dashedCircle(
      canvas,
      center,
      r * .64,
      dark ? const Color(0x1FFFFFFF) : gridColor,
    );
    final s = seconds;
    if (s == null) return;
    // .ring ×3: ripple 2.4 s ease-out, delays 0 / .8 / 1.6 s
    for (final delay in const [0.0, .8, 1.6]) {
      final p = ((s - delay) % 2.4) / 2.4;
      final e = Curves.easeOut.transform(p);
      final scale = .35 + (1.05 - .35) * e;
      final opacity = .9 * (1 - e);
      canvas.drawCircle(
        center,
        r * scale - .75,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Color.fromRGBO(142, 156, 255, .35 * opacity),
      );
    }
    // .sweep: 70° fading wedge in the 35-70 % band, one turn per 2.2 s
    final angle = (s % 2.2) / 2.2 * 2 * math.pi;
    final band = Rect.fromCircle(center: center, radius: r * .7);
    final shader = SweepGradient(
      colors: const [Color(0x528E9CFF), Color(0x008E9CFF), Color(0x008E9CFF)],
      stops: const [0, 70 / 360, 1],
      transform: GradientRotation(angle - math.pi / 2),
    ).createShader(band);
    canvas.drawCircle(
      center,
      r * .525,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .35,
    );
  }

  static void _dashedCircle(Canvas c, Offset o, double r, Color color) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    const dash = 3.0;
    final n = (2 * math.pi * r / (dash * 2)).floor();
    for (var i = 0; i < n; i++) {
      final a = i * 2 * math.pi / n;
      c.drawArc(Rect.fromCircle(center: o, radius: r), a, dash / r, false, p);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.seconds != seconds || old.dark != dark;
}

/// `.radar .core` (84 px) with the LED (9 px at top 12 / right 12).
class _Core extends StatelessWidget {
  const new({required this.found, required this.ledOn, required this.color});

  final bool found;
  final bool ledOn;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    final led = found ? c.ok : const Color(0xFF3B82F6);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-.3, -.4),
          colors: dark
              ? const [Color(0xFF262B3A), Color(0xFF171A22)]
              : const [Colors.white, Color(0xFFF1EEE7)],
        ),
        border: Border.all(
          color: found
              ? const Color(0xB34ABE84)
              : dark
              ? const Color(0x73B7C0FF)
              : const Color(0x733446C9),
          width: 1.5,
        ),
        boxShadow: found
            ? const [
                BoxShadow(color: Color(0x1A4ABE84), spreadRadius: 10),
                BoxShadow(color: Color(0x4D4ABE84), blurRadius: 40),
              ]
            : dark
            ? const [
                BoxShadow(color: Color(0x148E9CFF), spreadRadius: 10),
                BoxShadow(color: Color(0x408E9CFF), blurRadius: 40),
              ]
            : const [
                BoxShadow(color: Color(0x143446C9), spreadRadius: 10),
                BoxShadow(color: Color(0x333446C9), blurRadius: 30),
              ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IsharaIcon('hand', size: 40, color: color),
          Positioned(
            top: 12,
            right: 12,
            child: Opacity(
              opacity: ledOn ? 1 : .3,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: led,
                  boxShadow: [BoxShadow(color: led, blurRadius: 10)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signal strength from RSSI (dBm). DRAFT thresholds (Q-K2 asks for the
/// real RSSI; no source defines the bands): ≥ −60 strong (4 bars), ≥ −70
/// good (3), ≥ −80 fair (2), else weak (1).
int signalBars(int rssi) => rssi >= -60
    ? 4
    : rssi >= -70
    ? 3
    : rssi >= -80
    ? 2
    : 1;

String signalLabel(AppLocalizations l, int rssi) => switch (signalBars(rssi)) {
  4 => l.sigStrong,
  3 => l.sigGood,
  2 => l.sigFair,
  _ => l.sigWeak,
};

/// `.sig`: four bars (5, 8, 11, 12 px), unlit ones at 35 %.
class SignalBars extends StatelessWidget {
  const new({required this.bars, super.key});

  final int bars;

  @override
  Widget build(BuildContext context) {
    final ok = context.colors.ok;
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, h) in const [5.0, 8.0, 11.0, 12.0].indexed) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 3,
              height: h,
              decoration: BoxDecoration(
                color: ok.withValues(alpha: i < bars ? 1 : .35),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.batt`: an 18 × 9 battery filled to [percent] (null = unknown).
class BatteryIcon extends StatelessWidget {
  const new({required this.percent, this.low = false, super.key});

  final int? percent;
  final bool low;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = low ? c.danger : c.ok;
    return Container(
      width: 18,
      height: 9,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        border: Border.all(color: c.muted, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: ((percent ?? (low ? 15 : 0)) / 100).clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

/// The battery line of a connected glove (Q-K2: real `#BAT`).
String? batteryText(AppLocalizations l, BatteryEvent? b) => switch (b) {
  null => null,
  BatteryEvent(level: BatteryLevel.ok, percent: final p?) => l.battPercent(p),
  BatteryEvent(level: BatteryLevel.low) => l.battLow,
  BatteryEvent(level: BatteryLevel.usb) => l.battUsb,
  _ => null,
};

/// `.dev`: a glove card (name, signal, battery and firmware once connected),
/// its Connect button and, while connecting, the three checks.
class GloveCard extends StatelessWidget {
  const new({
    required this.glove,
    required this.state,
    required this.onConnect,
    super.key,
  });

  final DiscoveredGlove glove;
  final PairState state;

  /// Null hides the Connect button.
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = _dark(context);
    final battery = state.status.device?.id == glove.id
        ? state.status.battery
        : null;
    final fw = state.status.device?.id == glove.id
        ? state.status.info?.firmware
        : null;
    final batt = batteryText(l, battery);
    final showChecks =
        state.stage == PairStage.connecting ||
        state.stage == PairStage.connected ||
        state.stage == PairStage.failed;
    final details = [?batt, if (fw != null) l.firmware(fw)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0x148E9CFF) : const Color(0x0F3446C9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark ? const Color(0x59B7C0FF) : const Color(0x4D3446C9),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconTile(icon: 'bt', size: 46, radius: 14, iconSize: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      glove.name,
                      style: t.rowTitle.copyWith(fontSize: 15.5, color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Semantics(
                      label:
                          '${signalLabel(l, glove.rssi)}, '
                          '${l.rssiDbm(glove.rssi)}',
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          SignalBars(bars: signalBars(glove.rssi)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${signalLabel(l, glove.rssi)} · '
                              '${l.rssiDbm(glove.rssi)}',
                              style: t.rowSubtitle.copyWith(
                                fontSize: 12.5,
                                color: c.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (battery != null &&
                              battery.level != BatteryLevel.usb) ...[
                            BatteryIcon(
                              percent: battery.percent,
                              low: battery.level == BatteryLevel.low,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              details.join(' · '),
                              style: t.rowSubtitle.copyWith(
                                fontSize: 12.5,
                                color: c.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (onConnect != null) ...[
            const SizedBox(height: 10),
            IsharaButton(
              key: ValueKey('pair-connect-${glove.id}'),
              label: l.connect,
              small: true,
              onPressed: onConnect,
            ),
          ],
          if (showChecks) ...[
            const SizedBox(height: 10),
            _Checks(checks: state.checks),
          ],
        ],
      ),
    );
  }
}

/// `.checks`: the three pairing checks (Q-K3), each waiting / running
/// (spinner) / ok (green check) / failed.
class _Checks extends StatelessWidget {
  const new({required this.checks});

  final List<CheckState> checks;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final labels = [l.c1, l.c2Sensors, l.c3];
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _Check(label: labels[i], state: checks[i]),
          ],
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const new({required this.label, required this.state});

  final String label;
  final CheckState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    final active = state != CheckState.waiting;
    final badge = switch (state) {
      CheckState.waiting => _ring(c.ring),
      CheckState.running => SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.teal),
      ),
      CheckState.ok => _filled(
        c.ok,
        IsharaIcon(
          'check',
          size: 12,
          color: dark ? const Color(0xFF0E1440) : Colors.white,
        ),
      ),
      CheckState.failed => _filled(
        c.danger,
        const IsharaIcon('x', size: 12, color: Colors.white),
      ),
    };
    return Semantics(
      label: label,
      value: state.name,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: active ? 1 : .5,
        child: Row(
          children: [
            badge,
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: context.text.rowSubtitle.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: active ? c.ink : c.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _ring(Color color) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
  );

  static Widget _filled(Color color, Widget child) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    child: Center(child: child),
  );
}

/// `.tips`: "Glove not showing up?" and numbered tips (S6-3 drafts).
class PairTips extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final tips = [l.tipOn, l.tipNear, l.tipOtherPhone, l.tip3];
    return Container(
      key: const ValueKey('pair-tips'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.tipsTitle, style: t.rowTitle.copyWith(fontSize: 14)),
          for (final (i, tip) in tips.indexed) ...[
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x298E9CFF),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: t.chip.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: c.tealSoft,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tip,
                    style: t.rowSubtitle.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      color: c.sub,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
