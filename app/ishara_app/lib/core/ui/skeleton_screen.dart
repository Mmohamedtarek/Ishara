import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

/// A navigation action on a [SkeletonScreen].
@immutable
class SkeletonAction {
  const new(this.label, this.onPressed);
  final String label;
  final VoidCallback onPressed;
}

/// Temporary body for screens that later steps build for real.
///
/// It shows the screen's real title (from the ARB files) and the prototype's
/// exits, so the navigation, the theme and RTL can be tested end to end.
/// Every use is replaced by the real screen in its feature step.
class SkeletonScreen extends ConsumerWidget {
  const new({
    required this.screenKey,
    required this.title,
    this.actions = const [],
    super.key,
  });

  /// Stable id used by tests (`skeleton-<screenKey>`).
  final String screenKey;
  final String title;
  final List<SkeletonAction> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appSettingsControllerProvider).language;
    return Scaffold(
      key: ValueKey('skeleton-$screenKey'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const ValueKey('skeleton-lang'),
                  onPressed: () => ref
                      .read(appSettingsControllerProvider.notifier)
                      .toggleLanguage(),
                  child: Text(language == AppLanguage.en ? 'ع' : 'EN'),
                ),
              ),
              Text(title, style: context.text.h1),
              const SizedBox(height: 18),
              for (final a in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: a.onPressed,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(a.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
