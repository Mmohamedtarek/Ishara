import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-talk`. Skeleton until its feature step.
class TalkScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'talk',
      title: l.tabTalk,
      actions: [
        SkeletonAction(l.setTitle, () => context.go(AppRoutes.settings)),
      ],
    );
  }
}
