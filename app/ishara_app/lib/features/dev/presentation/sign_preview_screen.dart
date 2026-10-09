import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

/// Developer tool (debug / profile builds only, not localized): plays every
/// avatar sign, freezes it at any moment and shows it from the front or the
/// side, to check it against the vocabulary and the references (sign rules
/// 1–2) and to compare FIVE / FOUR and TWO / NO (Q-A6).
class SignPreviewScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignPreviewScreen> createState() => _SignPreviewState();
}

/// Camera angles: 0 = front, -90 = from the signer's right side.
const _views = <(String, double)>[
  ('Front', 0),
  ('Side (right)', -90),
  ('3/4', -40),
  ('Side (left)', 90),
];

class _SignPreviewState extends ConsumerState<SignPreviewScreen> {
  String? _label;
  double _view = 0;
  double _t = 0;
  double _speed = 1;
  bool _frozen = true;

  AvatarController? _seen;

  AvatarController? get _c =>
      _seen ??= ref.read(avatarRuntimeProvider).value?.controller;

  @override
  void dispose() {
    // The avatar is shared: leave it as other screens expect it (front
    // view, not frozen, ready pose).
    _seen
      ?..preview()
      ..stop();
    super.dispose();
  }

  void _show({String? label, double? view, double? t}) {
    final c = _c;
    setState(() {
      if (label != null) {
        _label = label;
        _t = 0;
      }
      if (view != null) _view = view;
      if (t != null) _t = t;
      _frozen = true;
    });
    c?.preview(label: _label, t: _t, view: _view);
  }

  void _play({required bool loop}) {
    final label = _label;
    if (label == null) return;
    setState(() => _frozen = false);
    _c
      ?..preview(view: _view)
      ..play(label, speed: _speed, loop: loop);
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ref.watch(avatarRuntimeProvider).value;
    final catalogue = ref.watch(signCatalogueProvider).value;
    final library = runtime?.controller.library;
    final t = context.text;
    final c = context.colors;
    final sorted = library?.labels.toList()?..sort();
    // The first sign until one is picked (no label is hard-coded here).
    final label = _label ??= sorted?.first;
    final sign = label == null ? null : catalogue?.byLabel(label);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign preview (dev)')),
      body: library == null || catalogue == null || label == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 340, child: AvatarStage()),
                const SizedBox(height: 12),
                if (runtime != null)
                  ValueListenableBuilder(
                    valueListenable: runtime.controller.status,
                    builder: (_, s, _) => Text(
                      'Avatar: ${s.name}',
                      style: t.rowSubtitle.copyWith(color: c.sub),
                    ),
                  ),
                Text(
                  '${sign?.wordsIn(SpokenLanguage.en).word ?? label}'
                  '  ·  $label',
                  style: t.rowTitle,
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    if (sign != null && sign.glove) const _Tag('glove'),
                    if (sign != null && !sign.avatar)
                      const _Tag('pending approval (avatar: false)'),
                    if (sign != null && !sign.verified)
                      const _Tag('being reviewed'),
                  ],
                ),
                if (sign != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(sign.description, style: t.rowSubtitle),
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (name, v) in _views)
                      ChoiceChip(
                        label: Text(name),
                        selected: _view == v,
                        onSelected: (_) => _show(view: v),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      't = ${_t.toStringAsFixed(2)} s',
                      style: t.rowSubtitle,
                    ),
                    Expanded(
                      child: Slider(
                        value: _t,
                        max: library.lastFrameTime(label),
                        onChanged: (v) => _show(t: v),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    FilledButton(
                      onPressed: () => _play(loop: false),
                      child: const Text('Play'),
                    ),
                    OutlinedButton(
                      onPressed: () => _play(loop: true),
                      child: const Text('Loop'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        _c?.stop();
                        setState(() => _frozen = false);
                      },
                      child: const Text('Stop'),
                    ),
                    for (final s in const [.5, 1.0, 1.5])
                      ChoiceChip(
                        label: Text('${s}x'),
                        selected: _speed == s,
                        onSelected: (_) => setState(() => _speed = s),
                      ),
                  ],
                ),
                if (!_frozen)
                  Text('playing', style: t.rowSubtitle.copyWith(color: c.sub)),
                const Divider(),
                Text('Compare (Q-A6)', style: t.rowTitle),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (a, b) in library.previewPairs)
                      for (final l in [a, b])
                        if (library.has(l))
                          ActionChip(
                            key: ValueKey('compare-$a-$b-$l'),
                            label: Text(l.toUpperCase()),
                            onPressed: () => _show(label: l),
                          ),
                  ],
                ),
                const Divider(),
                Text('All signs', style: t.rowTitle),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final l in sorted!)
                      ChoiceChip(
                        key: ValueKey('sign-$l'),
                        label: Text(
                          (catalogue.byLabel(l)?.avatar ?? false) ? l : '$l *',
                        ),
                        selected: label == l,
                        onSelected: (_) => _show(label: l),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '* new animation, not used in the app until approved '
                  '(sign rule 2)',
                  style: t.rowSubtitle.copyWith(color: c.sub),
                ),
              ],
            ),
    );
  }
}

class _Tag extends StatelessWidget {
  const new(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(text, style: context.text.rowSubtitle),
    visualDensity: VisualDensity.compact,
  );
}
