import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-mission`. Skeleton until its feature step.
class MissionScreen extends StatelessWidget {
  const new({required this.moduleId, super.key});

  final String moduleId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'mission',
      title: l.mStart,
      actions: [
        SkeletonAction(l.backToLearn, () => context.go(AppRoutes.learn)),
      ],
    );
  }
}
