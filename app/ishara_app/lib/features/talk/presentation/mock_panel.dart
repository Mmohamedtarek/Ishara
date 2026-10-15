import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/glove/mock/mock_controls.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

/// S7-24: the developer panel. A "Mock" button in Talk's top bar, only in
/// debug / profile builds with the mock glove; it plays the kit's mock
/// files through the real pipeline (frames → recognizer → Decider), so
/// Talk shows what the recognizer really produces. English only, like the
/// sign preview (developer tool).
class MockPanelButton extends ConsumerWidget {
  const new({super.key});

  /// Visible here: never in release builds, only with the mock glove, and
  /// only while developer mode is on (S9-3).
  static bool shown(WidgetRef ref) =>
      !kReleaseMode &&
      ref.watch(developerModeProvider) &&
      ref.watch(mockControlsProvider) != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!shown(ref)) return const SizedBox.shrink();
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Mock glove files',
      excludeSemantics: true,
      child: TextButton(
        key: const ValueKey('talk-mock'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          foregroundColor: c.amberSoft,
          shape: StadiumBorder(side: BorderSide(color: c.line)),
        ),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: c.panel,
          builder: (_) => const _MockSheet(),
        ),
        child: const Text('Mock'),
      ),
    );
  }
}

class _MockSheet extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_MockSheet> createState() => _MockSheetState();
}

class _MockSheetState extends ConsumerState<_MockSheet> {
  @override
  Widget build(BuildContext context) {
    final glove = ref.watch(mockControlsProvider);
    final labels = ref.watch(packLabelsProvider).value;
    if (glove == null) return const SizedBox.shrink();
    final person = glove.person;
    final files = ['sentences', 'everyday', ...?labels?.all];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mock glove: play a file through the real pipeline',
              style: context.text.rowTitle,
            ),
            const SizedBox(height: 8),
            SegmentedButton<MockPerson>(
              key: const ValueKey('mock-person'),
              segments: const [
                ButtonSegment(value: MockPerson.a, label: Text('Person A')),
                ButtonSegment(value: MockPerson.b, label: Text('Person B')),
              ],
              selected: {person},
              onSelectionChanged: (p) async {
                await glove.setPerson(p.single);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in files)
                      ActionChip(
                        key: ValueKey('mock-file-$f'),
                        label: Text(f),
                        onPressed: () => glove.play(f),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('mock-stop'),
              onPressed: glove.stop,
              child: const Text('Stop (back to rest)'),
            ),
          ],
        ),
      ),
    );
  }
}
