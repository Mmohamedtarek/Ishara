import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/router/tab_shell.dart';
import 'package:ishara_app/core/router/transitions.dart';
import 'package:ishara_app/features/avatar_studio/presentation/avatar_studio_screen.dart';
import 'package:ishara_app/features/calibration/presentation/calibrate_screen.dart';
import 'package:ishara_app/features/calibration/presentation/ready_screen.dart';
import 'package:ishara_app/features/dev/presentation/sign_preview_screen.dart';
import 'package:ishara_app/features/history/presentation/history_screen.dart';
import 'package:ishara_app/features/learn/presentation/learn_screen.dart';
import 'package:ishara_app/features/learn/presentation/mission_screen.dart';
import 'package:ishara_app/features/onboarding/presentation/auth_screen.dart';
import 'package:ishara_app/features/onboarding/presentation/setup_screen.dart';
import 'package:ishara_app/features/onboarding/presentation/splash_screen.dart';
import 'package:ishara_app/features/onboarding/presentation/welcome_screen.dart';
import 'package:ishara_app/features/pair/presentation/pair_screen.dart';
import 'package:ishara_app/features/settings/presentation/settings_screen.dart';
import 'package:ishara_app/features/talk/presentation/talk_screen.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

GoRoute _route(
  String path,
  Widget Function(GoRouterState s) build, {
  ScreenEntrance entrance = ScreenEntrance.slide,
}) => GoRoute(
  path: path,
  pageBuilder: (context, s) =>
      isharaPage(key: s.pageKey, entrance: entrance, child: build(s)),
);

/// Builds the router. Navigation follows the prototype: `go` / `back` form a
/// stack, and choosing a tab clears it (`tab()` in the prototype).
GoRouter buildRouter({String initialLocation = AppRoutes.splash}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    _route(AppRoutes.splash, (_) => const SplashScreen()),
    _route(AppRoutes.welcome, (_) => const WelcomeScreen()),
    _route(
      AppRoutes.authPath,
      (s) => AuthScreen(signUp: s.uri.queryParameters['mode'] == 'signup'),
    ),
    _route(AppRoutes.setup, (_) => const SetupScreen()),
    _route(AppRoutes.pair, (_) => const PairScreen()),
    _route(AppRoutes.calibrate, (_) => const CalibrateScreen()),
    _route(
      AppRoutes.ready,
      (s) => ReadyScreen(skipped: s.uri.queryParameters['skipped'] == '1'),
      entrance: ScreenEntrance.pop,
    ),
    _route(
      AppRoutes.missionPath,
      (s) => MissionScreen(moduleId: s.pathParameters['moduleId']!),
      entrance: ScreenEntrance.pop,
    ),
    _route(AppRoutes.avatarStudio, (_) => const AvatarStudioScreen()),
    // Developer tool: no entry point in release builds.
    if (!kReleaseMode)
      _route(AppRoutes.signPreview, (_) => const SignPreviewScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => TabShell(shell: shell),
      branches: [
        for (final (path, screen) in [
          (AppRoutes.talk, const TalkScreen()),
          (AppRoutes.learn, const LearnScreen()),
          (AppRoutes.history, const HistoryScreen()),
          (AppRoutes.settings, const SettingsScreen()),
        ])
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: path,
                pageBuilder: (context, s) =>
                    NoTransitionPage(key: s.pageKey, child: screen),
              ),
            ],
          ),
      ],
    ),
  ],
);

/// The app's router, created once.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = buildRouter();
  ref.onDispose(router.dispose);
  return router;
}
