import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/device/app_info.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/avatar_studio/presentation/avatar_studio_screen.dart';
import 'package:ishara_app/features/settings/application/data_export.dart';
import 'package:ishara_app/features/settings/presentation/about_screen.dart';
import 'package:ishara_app/features/settings/presentation/privacy_screen.dart';
import 'package:ishara_app/features/settings/presentation/settings_screen.dart';

import '../support/fake_learn.dart';
import '../support/fake_sos.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

class _Sharer implements FileSharer {
  final shared = <(String, Uint8List)>[];
  @override
  Future<void> share(Uint8List bytes, {required String name}) async =>
      shared.add((name, bytes));
}

Future<ProviderContainer> _pump(
  WidgetTester t,
  Widget screen, {
  MemoryKeyValueStore? store,
  FakeAuthRepository? auth,
  AppLanguage language = AppLanguage.en,
  List<Override> extra = const [],
}) async {
  addTearDown(rootBundle.clear);
  final talk = TalkFakes();
  addTearDown(talk.feed.dispose);
  await pumpScreen(
    t,
    screen,
    language: language,
    harness: Harness(
      store: store ?? MemoryKeyValueStore({'setup.spoken': 'en'}),
      auth: auth,
    ),
    overrides: [
      ...talk.overrides,
      ...SosFakes().overrides,
      appVersionProvider.overrideWithValue(const AsyncData('1.0.0 (1)')),
      ...extra,
    ],
  );
  return ProviderScope.containerOf(t.element(find.byType(Scaffold).first));
}

Future<void> _scrollTo(WidgetTester t, String key) async {
  final built = find.byKey(ValueKey(key), skipOffstage: false);
  if (built.evaluate().isNotEmpty) {
    await t.ensureVisible(built);
    await t.pump();
    return;
  }
  await t.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    200,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('settings-body')),
      matching: find.byType(Scrollable),
    ),
  );
}

void main() {
  group('Settings', () {
    testWidgets('a guest: "Guest", Create account; no glove paired', (t) async {
      await _pump(t, const SettingsScreen());
      expect(find.text('Guest'), findsOneWidget);
      expect(_key('settings-create-account'), findsOneWidget);
      expect(find.text('No glove paired'), findsOneWidget);
      await tapIt(t, _key('settings-create-account'));
      expect(find.text('route:/auth?mode=signup'), findsOneWidget);
    });

    testWidgets('signed in: the name and email; sign out', (t) async {
      final auth = FakeAuthRepository(delay: Duration.zero);
      await auth.createAccount(
        name: 'Mona',
        email: 'm@x.co',
        password: 'secret123',
      );
      await _pump(t, const SettingsScreen(), auth: auth);
      expect(find.text('Mona'), findsOneWidget);
      expect(find.text('Signed in as m@x.co'), findsOneWidget);
      expect(_key('settings-create-account'), findsNothing);
      await _scrollTo(t, 'settings-sign-out');
      await tapIt(t, _key('settings-sign-out'));
      expect(auth.currentUser, isNull);
      expect(find.text('route:/welcome'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('every switch changes the real setting and is a labelled '
        'switch for TalkBack', (t) async {
      final sem = t.ensureSemantics();
      final c = await _pump(t, const SettingsScreen());
      AppSettings s() => c.read(appSettingsControllerProvider);
      for (final (key, read) in <(String, bool Function())>[
        ('settings-subtitles', () => s().subtitles),
        ('settings-vibrate', () => s().vibrate),
        ('settings-big-text', () => s().bigText),
        ('settings-contrast', () => s().highContrast),
      ]) {
        await _scrollTo(t, key);
        final before = read();
        expect(
          t.getSemantics(_key(key)).flagsCollection.isToggled,
          before ? Tristate.isTrue : Tristate.isFalse,
          reason: key,
        );
        await tapIt(t, _key(key));
        expect(read(), !before, reason: key);
      }
      sem.dispose();
    });

    testWidgets('appearance: System / Light / Dark (Q-D3); language', (
      t,
    ) async {
      final c = await _pump(t, const SettingsScreen());
      await _scrollTo(t, 'settings-theme');
      expect(c.read(appSettingsControllerProvider).themeMode, ThemeMode.system);
      await tapIt(
        t,
        find.descendant(of: _key('settings-theme'), matching: _key('seg-2')),
      );
      expect(c.read(appSettingsControllerProvider).themeMode, ThemeMode.dark);
      await _scrollTo(t, 'settings-language');
      await tapIt(t, _key('settings-language'));
      expect(c.read(appSettingsControllerProvider).language, AppLanguage.ar);
    });

    testWidgets('avatar row shows the saved speed and opens the studio', (
      t,
    ) async {
      final c = await _pump(t, const SettingsScreen());
      await c.read(signSpeedProvider.notifier).save(.5);
      await settle(t);
      await _scrollTo(t, 'settings-avatar');
      expect(find.text('Sign speed 0.5x'), findsOneWidget);
      await tapIt(t, _key('settings-avatar'));
      expect(find.text('route:/avatar'), findsOneWidget);
    });

    testWidgets('Pair and Calibrate come back to Settings (?back=1)', (
      t,
    ) async {
      await _pump(t, const SettingsScreen());
      await tapIt(t, _key('settings-pair'));
      expect(find.text('route:/pair?back=1'), findsOneWidget);
    });

    testWidgets('no "coming soon" rows; no voice or unsure-word rows', (
      t,
    ) async {
      await _pump(t, const SettingsScreen());
      for (final gone in [
        'Coming next in the design',
        'Voice',
        'Ask me about unsure words',
        'Dark mode',
      ]) {
        expect(
          find.text(gone, skipOffstage: false),
          findsNothing,
          reason: gone,
        );
      }
    });

    testWidgets('developer section: only in developer mode', (t) async {
      final c = await _pump(t, const SettingsScreen());
      await _scrollTo(t, 'settings-sign-out');
      expect(_key('settings-dev-glove'), findsNothing);
      c.read(developerModeProvider.notifier).set(on: true);
      await settle(t);
      await _scrollTo(t, 'settings-dev-glove');
      expect(find.text('mock'), findsOneWidget);
    });
  });

  group('About', () {
    testWidgets('version, credits (RB-1), licences; 7 taps toggle developer '
        'mode with a toast', (t) async {
      final c = await _pump(t, const AboutScreen());
      expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
      expect(
        find.text(
          'Avatars: Avaturn and Avatar SDK (MetaPerson) sample models, for '
          'non-commercial use.',
        ),
        findsOneWidget,
      );
      for (var i = 0; i < 6; i++) {
        await t.tap(_key('about-version'));
        await t.pump();
      }
      expect(c.read(developerModeProvider), isFalse);
      await t.tap(_key('about-version'));
      await t.pump();
      expect(c.read(developerModeProvider), isTrue);
      expect(find.text('Developer mode on'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await tapIt(t, _key('about-licences'));
      expect(find.byType(LicensePage), findsOneWidget);
    });
  });

  group('Privacy', () {
    testWidgets('says what stays where (speech line, location); export '
        'shares the JSON; clear asks first and keeps starred phrases', (
      t,
    ) async {
      final sharer = _Sharer();
      final store = MemoryKeyValueStore({'setup.spoken': 'en'});
      final c = await _pump(
        t,
        const PrivacyScreen(),
        store: store,
        extra: [fileSharerProvider.overrideWithValue(sharer)],
      );
      expect(_key('privacy-speech'), findsOneWidget);
      expect(_key('privacy-location'), findsOneWidget);
      final repo = c.read(conversationRepositoryProvider);
      await repo.add(
        TalkMessage(
          side: MessageSide.me,
          text: 'hello',
          at: DateTime(2026, 10, 14),
        ),
      );
      await c.read(savedPhrasesRepositoryProvider).star('hello');
      await tapIt(t, _key('privacy-export'));
      expect(sharer.shared.single.$1, 'ishara-data.json');
      final data = jsonDecode(
        utf8.decode(sharer.shared.single.$2),
      ) as Map<String, Object?>;
      expect(data['conversation'], isA<Map<String, Object?>>());
      await tapIt(t, _key('privacy-clear'));
      await tapIt(t, _key('clear-cancel'));
      expect(repo.messages, hasLength(1));
      await tapIt(t, _key('privacy-clear'));
      await tapIt(t, _key('clear-confirm'));
      expect(repo.messages, isEmpty);
      expect(c.read(savedPhrasesRepositoryProvider).phrases, hasLength(1));
      await t.pump(const Duration(seconds: 3));
    });
  });

  group('Avatar studio', () {
    testWidgets('no picker with Nour alone; speed 1x → 0.5x; Save keeps it; '
        'the preview loops the greeting', (t) async {
      final rig = LearnRig();
      addTearDown(rig.dispose);
      final c = await _pump(
        t,
        const AvatarStudioScreen(),
        extra: [rig.overrides.last],
      );
      rig.avatar.loaded();
      await settle(t);
      expect(find.byKey(const ValueKey('cast-nour')), findsNothing);
      expect(_key('studio-credit'), findsOneWidget);
      expect(rig.avatar.plays.last, ('hello', 1.0, true));
      await tapIt(t, _key('studio-speed'));
      expect(find.text('0.5x'), findsOneWidget);
      expect(rig.avatar.plays.last, ('hello', .5, true));
      expect(c.read(signSpeedProvider), 1, reason: 'not saved yet');
      await tapIt(t, _key('studio-save'));
      expect(c.read(signSpeedProvider), .5);
      expect(find.text('Saved'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('leaving with a change asks first; Discard keeps the saved '
        'speed', (t) async {
      final c = await _pump(t, const AvatarStudioScreen());
      await tapIt(t, _key('studio-speed'));
      await tapIt(t, _key('studio-back'));
      expect(_key('studio-discard'), findsOneWidget);
      await tapIt(t, _key('studio-keep'));
      expect(_key('screen-avatar'), findsOneWidget);
      await tapIt(t, _key('studio-back'));
      await tapIt(t, _key('studio-discard-action'));
      expect(c.read(signSpeedProvider), 1);
    });

    testWidgets('without a change Back leaves at once', (t) async {
      await _pump(t, const AvatarStudioScreen());
      await tapIt(t, _key('studio-back'));
      expect(_key('studio-discard'), findsNothing);
    });
  });
}
