import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/toast.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/domain/learn_catalog.dart';
import 'package:ishara_app/features/learn/domain/learn_progress.dart';
import 'package:ishara_app/features/learn/domain/learn_rules.dart';
import 'package:ishara_app/features/learn/presentation/learn_modules_ui.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

bool _dark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Prototype screen `#s-learn` (`renderLearn`): streak, guest banner, the
/// real stats, the module path (Q-L1) and the daily challenge (Q-L2). Every
/// number comes from the activity log.
class LearnScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends ConsumerState<LearnScreen>
    with WidgetsBindingObserver {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    // shown again: a new day may have started (streak, daily challenge).
    // After the frame: this runs during the build.
    if (visible && !_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.invalidate(learnTodayProvider);
      });
    }
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) {
      ref.invalidate(learnTodayProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = ref.watch(learnProgressProvider).value;
    final catalogue = ref.watch(signCatalogueProvider).value;
    final guest = ref.watch(learnGuestProvider);
    return Scaffold(
      key: const ValueKey('screen-learn'),
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(streak: progress?.streak ?? 0),
            Expanded(
              child: progress == null || catalogue == null
                  ? const SizedBox.shrink()
                  : ListView(
                      key: const ValueKey('learn-body'),
                      // .screen .body: padding 4 18 14
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                      children: [
                        if (guest) const _GuestBanner(),
                        _Stats(progress: progress),
                        _Path(progress: progress, catalogue: catalogue),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.top`: "Learn signs" + "Watch Nour, then sign it with your glove", and
/// the streak chip (`.chip.a`, flame).
class _Header extends ConsumerWidget {
  const new({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final name = ref.watch(currentCharacterProvider)?.name(arabic: ar) ?? '';
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.learnTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.topTitle.copyWith(color: c.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(l.learnSub(name), style: t.topSubtitle),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _Chip(
              key: const ValueKey('learn-streak'),
              icon: 'flame',
              value: '$streak',
              text: l.days,
              semantics: '$streak ${l.days}',
            ),
          ],
        ),
      ),
    );
  }
}

/// `.chip.a`: amber glass, an icon, the number in `amber-soft`, a word.
class _Chip extends StatelessWidget {
  const new({
    required this.icon,
    required this.value,
    required this.semantics,
    this.text,
    super.key,
  });

  final String icon;
  final String value;
  final String? text;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    final style = context.text.chip.copyWith(color: c.ink);
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: dark ? const Color(0x24F2A33A) : const Color(0x1AF2A33A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: dark ? const Color(0x66FACD8C) : const Color(0x59F2A33A),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IsharaIcon(icon, size: 14, color: c.ink),
            const SizedBox(width: 7),
            Text(value, style: style.copyWith(color: c.amberSoft)),
            if (text case final w?) ...[
              const SizedBox(width: 7),
              Text(w, style: style),
            ],
          ],
        ),
      ),
    );
  }
}

/// `.banner` (guest mode): what stays on the phone, and "Save" (create an
/// account).
class _GuestBanner extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final dark = _dark(context);
    final style = context.text.rowSubtitle.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      height: 1.35,
      color: c.amberSoft,
    );
    return Container(
      key: const ValueKey('learn-guest'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dark ? const Color(0x1FF2A33A) : const Color(0x14F2A33A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? const Color(0x59FACD8C) : const Color(0x59F2A33A),
        ),
      ),
      child: Row(
        children: [
          IsharaIcon('guest', size: 18, color: c.amberSoft),
          const SizedBox(width: 10),
          Expanded(child: Text(l.guestBanner, style: style)),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            child: Material(
              color: dark ? const Color(0x33F2A33A) : const Color(0x24F2A33A),
              shape: StadiumBorder(
                side: BorderSide(
                  color: dark
                      ? const Color(0x80FACD8C)
                      : const Color(0x73F2A33A),
                ),
              ),
              child: InkWell(
                key: const ValueKey('learn-guest-save'),
                customBorder: const StadiumBorder(),
                onTap: () =>
                    unawaited(context.push(AppRoutes.auth(signUp: true))),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      l.save,
                      style: style.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.stats`: XP (amber), signs learned (teal), medals (violet).
class _Stats extends StatelessWidget {
  const new({required this.progress});

  final LearnProgress progress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          _Stat(
            key: const ValueKey('learn-xp'),
            value: progress.xp,
            label: l.xp,
            color: c.amberSoft,
          ),
          const SizedBox(width: 8),
          _Stat(
            key: const ValueKey('learn-signs'),
            value: progress.signsLearned,
            label: l.signsLearned,
            color: c.tealSoft,
          ),
          const SizedBox(width: 8),
          _Stat(
            key: const ValueKey('learn-medals'),
            value: progress.medals,
            label: l.medals,
            color: c.violetSoft,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const new({
    required this.value,
    required this.label,
    required this.color,
    super.key,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Expanded(
      child: Semantics(
        container: true,
        label: '$value $label',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.glass,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: t.stat.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(ar ? label : label.toUpperCase(), style: t.statLabel),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.path`: the modules (done / hero / locked) and the daily challenge.
class _Path extends ConsumerWidget {
  const new({required this.progress, required this.catalogue});

  final LearnProgress progress;
  final SignCatalogue catalogue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // the prototype's hero: the module to do next
    final hero = progress.modules
        .where((m) => m.unlocked && !m.finished)
        .firstOrNull;
    final dailyDone = progress.dailyDoneToday;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in progress.modules) ...[
          _ModuleTile(
            key: ValueKey('learn-module-${m.module.id}'),
            look: ModuleLook.of(m.module.id),
            subtitle: m.unlocked
                ? moduleSubtitle(
                    context,
                    m.module.id,
                    m.module.signs,
                    catalogue,
                  )
                : l.locked,
            count: '${l.signsCount(m.total)} · ${m.passed}/${m.total}',
            countLabel: l.passedOf(m.passed, m.total),
            progress: m.passed / m.total,
            xp: _moduleXp(m.module),
            done: m.finished,
            hero: identical(m, hero),
            locked: !m.unlocked,
            onTap: m.unlocked
                ? () => unawaited(context.push(AppRoutes.mission(m.module.id)))
                : () => showToast(context, l.locked),
          ),
          const SizedBox(height: 10),
        ],
        _ModuleTile(
          key: const ValueKey('learn-daily'),
          look: ModuleLook.daily,
          subtitle: dailyDone
              ? l.dailyDoneToday
              : l.mDailySigns(LearnRules.dailySigns),
          xp: LearnRules.dailyBonusXp,
          done: dailyDone,
          onTap: () =>
              unawaited(context.push(AppRoutes.mission(LearnCatalog.dailyId))),
        ),
      ],
    );
  }

  /// What the module can earn (Q-L2: quiz +10, practice +15 per sign).
  int _moduleXp(LearnModule m) {
    var xp = 0;
    for (final label in m.signs) {
      final sign = catalogue.byLabel(label);
      if (sign == null || !sign.avatar) continue;
      xp += LearnRules.quizXp;
      if (sign.glove && !m.watchOnly) xp += LearnRules.practiceXp;
    }
    return xp;
  }
}

/// `.mod`: icon tile, title, subtitle (or the locked text), "5 signs · 2/5"
/// and the progress bar, and the XP chip (`+125`, `✓ 125` when done).
class _ModuleTile extends StatelessWidget {
  const new({
    required this.look,
    required this.subtitle,
    required this.xp,
    required this.onTap,
    this.count,
    this.countLabel,
    this.progress,
    this.done = false,
    this.hero = false,
    this.locked = false,
    super.key,
  });

  final ModuleLook look;
  final String subtitle;
  final String? count;
  final String? countLabel;
  final double? progress;
  final int xp;
  final bool done;
  final bool hero;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.colors;
    final t = context.text;
    final dark = _dark(context);
    final radius = BorderRadius.circular(22);
    final sub = t.rowSubtitle.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.35,
      color: c.muted,
    );
    final title = look.title(l);
    final tile = Container(
      decoration: BoxDecoration(
        color: hero ? null : c.glass,
        gradient: hero
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? const [Color(0x2E8E9CFF), Color(0x2E6F7CF0)]
                    : const [Color(0x1F3446C9), Color(0x1F24309A)],
              )
            : null,
        borderRadius: radius,
        border: Border.all(
          color: hero
              ? (dark ? const Color(0x66B7C0FF) : const Color(0x593446C9))
              : c.line,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: look.colors,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: IsharaIcon(look.icon, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.rowTitle.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(subtitle, style: sub),
                      if (count case final n?) ...[
                        const SizedBox(height: 3),
                        Text(n, style: sub),
                      ],
                      if (progress case final p?) ...[
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Container(
                            height: 6,
                            color: c.track,
                            alignment: AlignmentDirectional.centerStart,
                            child: FractionallySizedBox(
                              widthFactor: p.clamp(0.0, 1.0),
                              heightFactor: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: LinearGradient(
                                    colors: [c.teal, c.violet],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _XpChip(xp: xp, done: done, locked: locked),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: [title, subtitle, ?countLabel, '+$xp ${l.xp}'].join('. '),
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(opacity: locked ? .55 : 1, child: tile),
    );
  }
}

/// `.mod .xp` (amber), `.done` (green, with a check), `.locked` (muted).
class _XpChip extends StatelessWidget {
  const new({required this.xp, required this.done, required this.locked});

  final int xp;
  final bool done;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = _dark(context);
    final (bg, border, fg) = locked
        ? (c.glass, c.line, c.muted)
        : done
        ? (
            dark ? const Color(0x244ABE84) : const Color(0x1A1F7A4D),
            dark ? const Color(0x664ABE84) : const Color(0x591F7A4D),
            c.okSoft,
          )
        : (
            dark ? const Color(0x24F2A33A) : const Color(0x1AF2A33A),
            dark ? const Color(0x59FACD8C) : const Color(0x4DF2A33A),
            c.amberSoft,
          );
    final style = context.text.chip.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w900,
      color: fg,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done) ...[
            IsharaIcon('check', size: 12, color: fg),
            const SizedBox(width: 3),
            Text('$xp', style: style),
          ] else
            Text('+$xp', style: style),
        ],
      ),
    );
  }
}
