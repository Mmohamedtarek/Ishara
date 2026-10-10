import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/avatar/avatar_bubble.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/core/ui/ishara_icon.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-welcome`: the avatar waves `hello` under "Hi, I'm Nour!",
/// the promise, three features, and the ways in (create an account, sign
/// in, guest).
class WelcomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // Prototype onShow.welcome: the greeting sign at 1x once the avatar is
    // up. The pack's library names its greeting (no label in the code).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final runtime = await ref.read(avatarRuntimeProvider.future);
        if (!mounted) return;
        final library = await ref.read(avatarLibraryProvider.future);
        final greeting = library.greeting;
        if (mounted && greeting != null) runtime.controller.play(greeting);
      } on Object catch (e, st) {
        // no avatar: it stays as it is (the stage shows its own state)
        Log('welcome').failure(
          'greeting',
          UnexpectedFailure('greeting', cause: e, stackTrace: st),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.text;
    final character = ref.watch(currentCharacterProvider);
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final name = character?.name(arabic: arabic) ?? '';
    final gender = character?.icuGender ?? '';
    return OnboardingPage(
      screenKey: 'welcome',
      top: const OnboardingTopBar(brand: true),
      body: [
        // #s-welcome .hero: height 264, margin 0 16
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 264,
            child: AvatarStage(
              overlay: name.isEmpty ? null : AvatarBubble(l.hiNour(name)),
            ),
          ),
        ),
        // #s-welcome h1: 28 px, margin-top 16
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Semantics(
            header: true,
            child: Text(l.welTitle, style: t.h1.copyWith(fontSize: 28)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(l.welLead(name, gender), style: t.lead),
        ),
        // .feat: margin 10 0 14, gap 8 (its top margin collapses into the
        // lead's 14 px bottom margin, as in CSS)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            children: [
              _Feature(icon: 'hand', text: l.f1),
              const SizedBox(height: 8),
              _Feature(icon: 'mic', text: l.f2, violet: true),
              const SizedBox(height: 8),
              _Feature(icon: 'book', text: l.f3),
            ],
          ),
        ),
      ],
      cta: CtaBar(
        children: [
          IsharaButton(
            key: const ValueKey('welcome-get-started'),
            label: l.getStarted,
            arrow: true,
            onPressed: () => context.push(AppRoutes.auth(signUp: true)),
          ),
          IsharaButton(
            key: const ValueKey('welcome-sign-in'),
            label: l.haveAccount,
            kind: IsharaButtonKind.ghost,
            small: true,
            onPressed: () => context.push(AppRoutes.auth(signUp: false)),
          ),
          IsharaLink(
            key: const ValueKey('welcome-guest'),
            label: l.guestLink,
            onPressed: () => context.push(AppRoutes.setup),
          ),
        ],
      ),
    );
  }
}

/// `.feat div`: a 30 px tinted icon and a line of text (13.5 px w700, sub).
class _Feature extends StatelessWidget {
  const new({required this.icon, required this.text, this.violet = false});

  final String icon;
  final String text;
  final bool violet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: violet ? const Color(0x2E6F7CF0) : const Color(0x248E9CFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: IsharaIcon(
              icon,
              size: 16,
              color: violet ? c.violetSoft : c.tealSoft,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: context.text.rowSubtitle.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: c.sub,
            ),
          ),
        ),
      ],
    );
  }
}
