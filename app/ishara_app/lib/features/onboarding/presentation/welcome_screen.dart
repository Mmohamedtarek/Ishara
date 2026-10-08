import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-welcome`. Skeleton until its feature step.
class WelcomeScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'welcome',
      title: l.welTitle,
      actions: [
        SkeletonAction(
          l.getStarted,
          () => context.push(AppRoutes.auth(signUp: true)),
        ),
        SkeletonAction(
          l.haveAccount,
          () => context.push(AppRoutes.auth(signUp: false)),
        ),
        SkeletonAction(l.guestLink, () => context.push(AppRoutes.setup)),
      ],
    );
  }
}
