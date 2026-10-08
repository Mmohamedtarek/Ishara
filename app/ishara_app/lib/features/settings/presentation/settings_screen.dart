import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-settings`. Skeleton until its feature step.
class SettingsScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'settings',
      title: l.setTitle,
      actions: [
        SkeletonAction(l.sCal, () => context.push(AppRoutes.calibrate)),
        SkeletonAction(l.sPair, () => context.push(AppRoutes.pair)),
        SkeletonAction(l.avTitle, () => context.push(AppRoutes.avatarStudio)),
        SkeletonAction(l.sLogout, () => context.go(AppRoutes.welcome)),
      ],
    );
  }
}
