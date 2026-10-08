import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/skeleton_screen.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype screen `#s-auth`. Skeleton until its feature step.
class AuthScreen extends StatelessWidget {
  const new({required this.signUp, super.key});

  /// `data-arg="signup"` vs `"signin"` in the prototype.
  final bool signUp;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SkeletonScreen(
      screenKey: 'auth',
      title: signUp ? l.createTitle : l.welcomeBack,
      actions: [
        SkeletonAction(
          signUp ? l.createAccount : l.signIn,
          () => context.push(AppRoutes.setup),
        ),
      ],
    );
  }
}
