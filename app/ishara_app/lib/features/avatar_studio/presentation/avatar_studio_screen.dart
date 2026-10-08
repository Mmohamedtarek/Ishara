import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-avatar`. Skeleton until its feature step.
class AvatarStudioScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'avatar',
      title: l.avTitle,
      actions: [SkeletonAction(l.saveAvatar, () => context.pop())],
    );
  }
}
