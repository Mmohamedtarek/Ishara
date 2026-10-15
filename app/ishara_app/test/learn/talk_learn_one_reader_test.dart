import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/auth/auth_providers.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/device/keep_screen_on.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/ui/ishara_tab_bar.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/domain/practice_check.dart';
import 'package:ishara_app/features/talk/application/talk_glove_controller.dart';

import '../support/fake_learn.dart';
import '../support/fake_speech.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// DECISIONS 2026-10-13: Talk and Learn read the same recognizer; exactly
/// one of them acts on its events. Talk only while it is visible, a
/// mission only inside a practice window.
void main() {
  testWidgets('a practice window: the mission passes, Talk shows and speaks '
      'nothing; back on Talk, Talk does', (t) async {
    rootBundle.clear();
    addTearDown(rootBundle.clear);
    // the conversation must not end (active_s) while the test taps along
    final talk = TalkFakes()..timeout = const Duration(minutes: 5);
    final rig = LearnRig(recognition: talk.feed);
    addTearDown(rig.dispose);
    addTearDown(talk.feed.dispose);
    t.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await rig.kv.setString('setup.spoken', 'en');
    await t.runAsync(() => rig.glove.connect(rig.glove.found.single));
    final router = buildRouter(initialLocation: AppRoutes.talk);
    addTearDown(router.dispose);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(delay: Duration.zero),
          ),
          ...rig.overrides,
          conversationTimeoutProvider.overrideWithValue(
            AsyncData(talk.timeout),
          ),
          textToSpeechProvider.overrideWithValue(talk.tts),
          keepScreenOnProvider.overrideWithValue(talk.screen),
          speechToTextProvider.overrideWithValue(FakeSpeechToText()),
          micPermissionsProvider.overrideWithValue(
            FakeMicPermissions(current: MicPermission.granted),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    rig.avatar.loaded();
    await settle(t, n: 10);
    final c = ProviderScope.containerOf(t.element(_key('screen-talk')));
    TalkGloveState talkState() => c.read(talkGloveProvider);

    // Talk visible: it shows and speaks the glove's word
    talk.feed.word('hello');
    await settle(t);
    expect(talkState().words.map((w) => w.label), ['hello']);
    expect(talk.tts.spoken, ['hello']);

    // Learn → Start here → quiz → your turn
    await tapIt(
      t,
      find.descendant(
        of: find.byType(IsharaTabBar),
        matching: find.text('Learn'),
      ),
    );
    await settle(t, n: 10);
    await tapIt(t, _key('learn-module-start'));
    await settle(t, n: 10);
    await tapIt(t, _key('tile-hello'));
    await tapIt(t, _key('mission-check'));
    await tapIt(t, _key('mission-check'));
    await tapIt(t, _key('mission-sign'));
    final talkWords = talkState().words;
    talk.feed.confirm('hello');
    await settle(t);
    final mission = c.read(missionControllerProvider('start'));
    expect(mission.practice!.phase, PracticePhase.passed);
    // Talk ignored it: no new word, nothing spoken
    expect(talkState().words, talkWords);
    expect(talkWords.map((w) => w.label), ['hello']);
    expect(talk.tts.spoken, ['hello']);

    // outside a window the mission ignores events (Talk is hidden too)
    talk.feed.word('yes');
    await settle(t);
    expect(talk.tts.spoken, ['hello']);

    // back on Talk: Talk acts again, the mission is gone
    await tapIt(t, _key('mission-close'));
    await settle(t, n: 10);
    await tapIt(
      t,
      find.descendant(
        of: find.byType(IsharaTabBar),
        matching: find.text('Talk'),
      ),
    );
    await settle(t, n: 10);
    talk.feed.word('thanks');
    await settle(t);
    expect(talk.tts.spoken, ['hello', 'thank you']);
  });
}
