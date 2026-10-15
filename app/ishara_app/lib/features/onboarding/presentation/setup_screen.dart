import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/cast_picker.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/ui/onboarding_ui.dart';
import 'package:ishara_app/core/ui/sign_language_picker.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

/// Prototype `#s-setup` (step 1 of 3): who uses the phone, the sign language
/// (ASL; ArSL shows "coming soon", sign rule 8), the voice. Every answer is
/// saved as it is chosen (S6-2). The avatar choice appears only when there is
/// more than one character (`AvatarCast.showPicker`, S5-13): with Nour alone
/// there is none.
class SetupScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final profile = ref.watch(profileControllerProvider);
    final p = ref.read(profileControllerProvider.notifier);
    return OnboardingPage(
      screenKey: 'setup',
      top: const OnboardingTopBar(back: true, step: 0),
      body: [
        PageTitle(l.setupTitle, lead: l.setupLead),
        QuestionLabel(l.qWho),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              OptCard(
                key: const ValueKey('setup-who-sign'),
                icon: 'hand',
                title: l.whoSign,
                subtitle: l.whoSignS,
                selected: profile.role == UserRole.sign,
                onTap: () => p.setRole(UserRole.sign),
              ),
              const SizedBox(height: 10),
              OptCard(
                key: const ValueKey('setup-who-speak'),
                icon: 'mic',
                teal: true,
                title: l.whoSpeak,
                subtitle: l.whoSpeakS,
                selected: profile.role == UserRole.speak,
                onTap: () => p.setRole(UserRole.speak),
              ),
            ],
          ),
        ),
        QuestionLabel(l.qSignLang),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: SignLanguagePicker(),
        ),
        QuestionLabel(l.qSpoken),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // prototype order: العربية, English (each in its own script)
              ChoicePill(
                key: const ValueKey('setup-voice-ar'),
                label: 'العربية',
                cairo: true,
                selected: profile.spoken == SpokenLanguage.ar,
                onTap: () => p.setSpoken(SpokenLanguage.ar),
              ),
              ChoicePill(
                key: const ValueKey('setup-voice-en'),
                label: 'English',
                selected: profile.spoken == SpokenLanguage.en,
                onTap: () => p.setSpoken(SpokenLanguage.en),
              ),
            ],
          ),
        ),
        // S6-9: the Avatar studio's picker; nothing with one character
        CastPicker(
          selected: ref.watch(currentCharacterProvider)?.id,
          onSelect: (id) =>
              ref.read(savedCharacterProvider.notifier).save(id).ignore(),
        ),
      ],
      cta: CtaBar(
        children: [
          IsharaButton(
            key: const ValueKey('setup-continue'),
            label: l.continueLabel,
            arrow: true,
            onPressed: () => context.push(AppRoutes.pair),
          ),
        ],
      ),
    );
  }
}
