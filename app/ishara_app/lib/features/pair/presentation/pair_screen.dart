import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-pair`. Skeleton until its feature step.
class PairScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'pair',
      title: l.pairTitle,
      actions: [
        SkeletonAction(l.ctaCal, () => context.push(AppRoutes.calibrate)),
      ],
    );
  }
}
