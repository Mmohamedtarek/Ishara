import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/theme/ishara_tokens.dart';
import 'package:ishara_app/core/ui/blink.dart';
import 'package:ishara_app/core/ui/hand_drawing.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/application/practice_hand.dart';
import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:ishara_app/features/learn/domain/mission_plan.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';
import 'package:ishara_app/features/learn/presentation/learn_modules_ui.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

bool _dark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// `.sheet-h`: 40 × 4, `--track`, margin 10 auto 6.
class _SheetHandle extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: context.colors.track,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// `.ask`: 16 px w900 centred, a 12 px muted line under it.
class _Ask extends StatelessWidget {
  const new(this.title, this.small);

  final String title;
  final String small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.rowTitle.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              small,
              textAlign: TextAlign.center,
              style: t.rowSubtitle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick the meaning: 4 tiles (`.tiles`), then the feedback (`.fb`).
class QuizBody extends StatelessWidget {
  const new({
    required this.step,
    required this.state,
    required this.catalogue,
    required this.onPick,
    super.key,
  });

  final QuizStep step;
  final MissionState state;
  final SignCatalogue catalogue;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = learnLanguage(context);
    String word(String label) =>
        catalogue.byLabel(label)?.wordsIn(lang).word ?? '';
    final answer = word(step.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHandle(),
        _Ask(l.pickWord, l.watchSub),
        // .tiles: 2 columns, gap 10; each tile 92 px high
        Column(
          key: const ValueKey('mission-tiles'),
          children: [
            for (var r = 0; r < step.options.length; r += 2) ...[
              if (r > 0) const SizedBox(height: 10),
              Row(
                children: [
                  for (final (i, o)
                      in step.options.skip(r).take(2).indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 92,
                        child: _Tile(
                          key: ValueKey('tile-$o'),
                          icon: catalogue.byLabel(o)?.icon ?? 'hand',
                          word: word(o),
                          selected: state.picked == o,
                          mark: !state.checked
                              ? null
                              : o == step.label
                              ? true
                              : o == state.picked
                              ? false
                              : null,
                          onTap: state.checked ? null : () => onPick(o),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        if (state.checked && state.correct)
          MissionFeedback(
            key: const ValueKey('mission-fb-good'),
            good: true,
            icon: 'check',
            text: l.correct(answer),
            xp: LearnRules.quizXp,
          )
        else if (state.checked)
          MissionFeedback(
            key: const ValueKey('mission-fb-bad'),
            good: false,
            icon: 'replay',
            text: l.wrongA(answer),
          ),
      ],
    );
  }
}

/// `.tile`: 92 px, radius 20, glass, 1.5 px line border; icon (30 px,
/// teal-soft) and the word. `.on` (picked), `.right`, `.wrong`.
class _Tile extends StatelessWidget {
  const new({
    required this.icon,
    required this.word,
    required this.selected,
    required this.mark,
    required this.onTap,
    super.key,
  });

  final String icon;
  final String word;
  final bool selected;

  /// After Check: true = the right answer, false = the wrong pick.
  final bool? mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    final radius = BorderRadius.circular(20);
    final (Color bg, Color border) = switch (mark) {
      true => (dark ? const Color(0x294ABE84) : const Color(0x1F1F7A4D), c.ok),
      false => (
        dark ? const Color(0x24F06E76) : const Color(0x14C62B33),
        c.danger,
      ),
      null when selected => (
        dark ? const Color(0x1F8E9CFF) : const Color(0x143446C9),
        const Color(0xCCB7C0FF),
      ),
      null => (c.glass, c.line),
    };
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: word,
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: border, width: 1.5),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IsharaIcon(
                  icon,
                  size: 30,
                  color: mark == true ? c.okSoft : c.tealSoft,
                ),
                const SizedBox(height: 6),
                Text(
                  word,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.rowTitle.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: c.ink,
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

/// `.fb.good` / `.fb.bad`: an icon, the text, and "+10 XP" when earned;
/// pops in (reduced motion: shown at once). Screen readers announce it.
class MissionFeedback extends StatefulWidget {
  const new({
    required this.good,
    required this.icon,
    required this.text,
    this.xp,
    super.key,
  });

  final bool good;
  final String icon;
  final String text;
  final int? xp;

  @override
  State<MissionFeedback> createState() => _MissionFeedbackState();
}

class _MissionFeedbackState extends State<MissionFeedback>
    with SingleTickerProviderStateMixin {
  // popin .3s ease both
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _a.value = 1;
    } else if (_a.value == 0 && !_a.isAnimating) {
      _a.forward();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = _dark(context);
    final good = widget.good;
    final fg = good ? c.okSoft : c.amberSoft;
    final (bg, border) = good
        ? (
            dark ? const Color(0x244ABE84) : const Color(0x1A1F7A4D),
            dark ? const Color(0x734ABE84) : const Color(0x591F7A4D),
          )
        : (
            dark ? const Color(0x24F2A33A) : const Color(0x1AF2A33A),
            dark ? const Color(0x73FACD8C) : const Color(0x59F2A33A),
          );
    final style = context.text.rowTitle.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w800,
      color: fg,
    );
    final curve = CurvedAnimation(parent: _a, curve: IsharaMotion.ease);
    return Semantics(
      liveRegion: true,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .2),
            end: Offset.zero,
          ).animate(curve),
          child: Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                IsharaIcon(widget.icon, color: fg),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.text, style: style)),
                if (widget.xp case final xp?) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.glass,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '+$xp ${l.xp}',
                      style: style.copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Your turn": the live hand (`.split`), the glove's state when it can't
/// be used (S8-1), and the outcome.
class PracticeBody extends ConsumerWidget {
  const new({
    required this.step,
    required this.state,
    required this.catalogue,
    super.key,
  });

  final PracticeStep step;
  final MissionState state;
  final SignCatalogue catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final name = ref.watch(currentCharacterProvider)?.name(arabic: ar) ?? '';
    final word =
        catalogue.byLabel(step.label)?.wordsIn(learnLanguage(context)).word ??
        '';
    final p = state.practice;
    final block = state.block;
    final finished =
        p?.phase == PracticePhase.passed || p?.phase == PracticePhase.failed;
    // the attempt running, or the next one
    final tryNo = p == null
        ? null
        : switch (p.phase) {
            PracticePhase.counting => p.attempt,
            PracticePhase.retry => p.attempt + 1,
            _ => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetHandle(),
        _Ask(l.yourTurn, l.yourTurnSign('“$word”')),
        if (block != null && !finished)
          _BlockCard(block: block)
        else
          _Split(match: p?.matchPercent),
        if (tryNo != null && (block == null || finished))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.practiceTry(tryNo, LearnRules.practiceAttempts),
              key: const ValueKey('mission-try'),
              textAlign: TextAlign.center,
              style: context.text.rowSubtitle.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: c.muted,
              ),
            ),
          ),
        if (p != null)
          switch (p.phase) {
            PracticePhase.passed => MissionFeedback(
              key: const ValueKey('mission-fb-good'),
              good: true,
              icon: 'check',
              text: (p.matchPercent ?? 0) >= LearnRules.greatMatchPercent
                  ? l.greatMatch(p.matchPercent ?? 0)
                  : l.goodMatch(p.matchPercent ?? 0),
              xp: LearnRules.practiceXp,
            ),
            PracticePhase.retry => MissionFeedback(
              key: ValueKey('mission-fb-retry-${p.attempt}'),
              good: false,
              icon: 'replay',
              text: p.otherSignSeen ? l.practiceOther(name) : l.practiceNothing,
            ),
            PracticePhase.failed => MissionFeedback(
              key: const ValueKey('mission-fb-out'),
              good: false,
              icon: 'replay',
              text: l.practiceOut('“$word”'),
            ),
            _ => const SizedBox.shrink(),
          },
      ],
    );
  }
}

/// `.split`: "Your turn · live" with the live hand drawing (and the match
/// ring once passed), "Live from your glove" with the finger bars.
class _Split extends ConsumerWidget {
  const new({required this.match});

  final int? match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = _dark(context);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final live = ref.watch(practiceHandProvider);
    String up(String s) => ar ? s : s.toUpperCase();
    final label = context.text.chip.copyWith(
      fontSize: ar ? 11.5 : 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: ar ? 0 : 10.5 * .04,
      color: c.muted,
    );
    BoxDecoration pane() => BoxDecoration(
      color: c.glass,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.line),
    );
    return ValueListenableBuilder(
      valueListenable: live.revision,
      builder: (context, _, _) {
        final fingers = live.hand.fingers;
        final bend = fingers ?? const <double?>[0, 0, 0, 0, 0];
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 190),
                  decoration: pane(),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                            child: Row(
                              children: [
                                Blink(
                                  on: true,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: c.violet,
                                      boxShadow: [
                                        BoxShadow(
                                          color: c.violet,
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    up('${l.yourTurn} · ${l.live}'),
                                    overflow: TextOverflow.ellipsis,
                                    style: label,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Center(
                            child: ExcludeSemantics(
                              child: SizedBox(
                                height: 150,
                                width: 150 * 200 / 220,
                                child: CustomPaint(
                                  painter: HandPainter(bend: bend, dark: dark),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (match case final m?)
                        PositionedDirectional(
                          bottom: 8,
                          end: 8,
                          child: _MatchRing(percent: m),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 190),
                  decoration: pane(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                        child: Text(up(l.liveFrom), style: label),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: FingerBars(
                          values:
                              fingers ?? const [null, null, null, null, null],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// `.match`: 52 px, dark centre, the % (Q-L4) in the dark theme's
/// ok-soft (the light theme's dark green is unreadable on the prototype's
/// dark centre); the 3 px ring fills to the %, the rest is `--track` (the
/// prototype's ring is a fixed half).
class _MatchRing extends StatelessWidget {
  const new({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox.square(
      key: const ValueKey('mission-match'),
      dimension: 52,
      child: CustomPaint(
        painter: _RingPainter(
          value: percent / 100,
          color: c.ok,
          track: c.track,
        ),
        child: Center(
          child: Text(
            '$percent%',
            style: context.text.chip.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF9FE0BD),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const new({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centre = Offset(r, r);
    canvas.drawCircle(centre, r, Paint()..color = const Color(0xCC121318));
    final rect = Rect.fromCircle(center: centre, radius: r - 1.5);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas
      ..drawArc(rect, 0, 2 * math.pi, false, stroke..color = track)
      ..drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value.clamp(0, 1),
        false,
        stroke..color = color,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

/// Why the glove can't be used now (S8-1), with the step 6 / 7 texts.
class _BlockCard extends StatelessWidget {
  const new({required this.block});

  final PracticeBlock block;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final (String title, String? body) = switch (block) {
      PracticeBlock.noGlove => (l.gloveOff, l.liveNoGlove),
      PracticeBlock.notCalibrated => (l.liveNoCal, null),
      PracticeBlock.reconnecting => (l.gloveReconnecting, null),
      PracticeBlock.mpuFail => (l.mpuTitle, l.mpuBody),
      PracticeBlock.stopped => (l.liveStopped, null),
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: ValueKey('mission-block-${block.name}'),
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: c.glass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0x29F2A33A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: block == PracticeBlock.reconnecting
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: c.amberSoft,
                        ),
                      )
                    : IsharaIcon('bt', size: 18, color: c.amberSoft),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: t.rowTitle.copyWith(fontSize: 14, color: c.ink),
                  ),
                  if (body case final b?) ...[
                    const SizedBox(height: 4),
                    Text(
                      b,
                      style: t.rowSubtitle.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        color: c.sub,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.result`: the medal (Q-L2: ≥ 80 %), "Mission complete!", what it
/// unlocked, and `.sumgrid` (XP earned, accuracy, time).
class ResultBody extends StatelessWidget {
  const new({required this.result, required this.daily, super.key});

  final MissionResult result;
  final bool daily;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final lead = result.unlockedNext
        ? l.missionDoneS
        : daily || result.moduleFinished
        ? l.missionNice
        : l.missionKeepGoing;
    final secs = result.seconds;
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        children: [
          // .result: gap 6; medal margin-bottom 8, h1 margin 4 0 6, p.lead
          // margin-bottom 14, .sumgrid margin-top 10
          if (result.medal) const _Medal() else const SizedBox(height: 14),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              l.missionDone,
              textAlign: TextAlign.center,
              style: t.h1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            lead,
            key: const ValueKey('mission-result-lead'),
            textAlign: TextAlign.center,
            style: t.lead,
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              _Sum(
                key: const ValueKey('result-xp'),
                value: '+${result.xp}',
                label: l.xpLbl,
                color: c.amberSoft,
              ),
              const SizedBox(width: 8),
              _Sum(
                key: const ValueKey('result-accuracy'),
                value: '${result.accuracyPercent}%',
                label: l.accuracyLbl,
                color: c.okSoft,
              ),
              const SizedBox(width: 8),
              _Sum(
                key: const ValueKey('result-time'),
                value: time,
                label: l.timeLbl,
                color: c.ink,
              ),
            ],
          ),
          if (!result.medal) ...[
            const SizedBox(height: 10),
            Text(
              l.noMedal((LearnRules.medalAccuracy * 100).round()),
              key: const ValueKey('mission-no-medal'),
              textAlign: TextAlign.center,
              style: t.rowSubtitle.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.medal`: 96 px, gold radial gradient, the medal icon; pops in.
class _Medal extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dark = _dark(context);
    return Semantics(
      label: l.medalEarned,
      image: true,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('mission-medal'),
        width: 96,
        height: 96,
        margin: const EdgeInsets.only(top: 6, bottom: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // radial-gradient(circle at 35% 30%, …): CSS sizes it to the
          // farthest corner, 0.955 of the side from there
          gradient: const RadialGradient(
            center: Alignment(-.3, -.4),
            radius: .955,
            colors: [Color(0xFFFDE68A), Color(0xFFD97706)],
            stops: [0, .7],
          ),
          boxShadow: [
            BoxShadow(
              color: dark ? const Color(0x59F2A33A) : const Color(0x40F2A33A),
              blurRadius: dark ? 40 : 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: const Center(
          child: IsharaIcon('medal', size: 46, color: Color(0xFF3B2A00)),
        ),
      ),
    );
  }
}

/// `.sumgrid div`: a value (18 px w900) over a label (11 px muted).
class _Sum extends StatelessWidget {
  const new({
    required this.value,
    required this.label,
    required this.color,
    super.key,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.glass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
          ),
          child: Column(
            children: [
              Text(value, style: t.stat.copyWith(fontSize: 18, color: color)),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: t.rowSubtitle.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sign rule 5 (debug builds only, English): this sign's form hasn't been
/// checked against a reference yet.
class ReviewMarker extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('mission-review'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xCCD97706),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      'being reviewed',
      style: context.text.chip.copyWith(fontSize: 10.5, color: Colors.white),
    ),
  );
}
