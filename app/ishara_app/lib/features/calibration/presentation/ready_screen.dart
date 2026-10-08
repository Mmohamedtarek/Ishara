import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-ready`. Skeleton until its feature step.
class ReadyScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'ready',
      title: l.doneTitle,
      actions: [
        SkeletonAction(l.ctaTalk, () => context.go(AppRoutes.talk)),
        SkeletonAction(l.ctaRedo, () => context.push(AppRoutes.calibrate)),
      ],
    );
  }
}
