// On a phone (mock glove, debug build default):
//   flutter test integration_test/flow_test.dart -d <device>
// For the review video, paced (pause on each screen, in ms):
//   flutter test integration_test/flow_test.dart -d <device> \
//     --dart-define=PACE_MS=1500
// Step 9 in one go, through the real app: the mock glove signs "hello" in
// Talk → History (today's conversation) → star it → Starred (a tap speaks
// it) → Settings → Avatar studio → 0.5x → Save → Talk, where a heard
// "hello" is signed at the saved 0.5x. Prints FLOW lines for the record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

import '../test/support/fake_speech.dart';

final _pace = Duration(
  milliseconds: int.parse(
    const String.fromEnvironment('PACE_MS', defaultValue: '0'),
  ),
);

Future<void> waitFor(
  WidgetTester t,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('not found: $f');
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Keeps the screen still for the video ([_pace] by default).
Future<void> linger(WidgetTester t, [Duration? d]) async {
  final end = DateTime.now().add(d ?? _pace);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapAndWait(WidgetTester t, Finder f) async {
  await waitFor(t, f);
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 400));
  await linger(t);
}

/// Brings a Settings row on screen (lazy list, from the top down).
Future<void> settingsRow(WidgetTester t, String key) async {
  final row = find.byKey(ValueKey(key));
  final list = find
      .descendant(
        of: find.byKey(const ValueKey('settings-body')),
        matching: find.byType(Scrollable),
      )
      .first;
  if (row.evaluate().isEmpty) {
    await t.scrollUntilVisible(row, 200, scrollable: list, maxScrolls: 40);
  }
  await t.ensureVisible(row);
  await t.pump(const Duration(milliseconds: 300));
}

/// The real page, recording the speed of every `play` the app sends.
class _Recording implements AvatarSurface {
  new(this._real, this.plays);
  final AvatarSurface _real;
  final List<(String, double)> plays;

  @override
  Stream<String> get messages => _real.messages;

  @override
  Future<void> send(Map<String, Object?> command) {
    if (command['cmd'] == 'play') {
      plays.add((command['label']! as String, command['speed']! as double));
    }
    return _real.send(command);
  }

  @override
  Widget buildView() => _real.buildView();

  @override
  Future<void> dispose() => _real.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Talk → History → star → Starred speaks → Avatar studio '
      '0.5x Save → Talk signs at 0.5x', (t) async {
    void mark(String what) => debugPrint('FLOW $what');
    final plays = <(String, double)>[];
    final store = MemoryKeyValueStore({
      'onboarding.done': true,
      'setup.spoken': 'en',
      'setup.role': 'sign',
      // the Mock panel shows only in developer mode (S9-3)
      'settings.developer': true,
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.talk),
          ),
          avatarSurfaceFactoryProvider.overrideWith((ref) {
            final real = avatarSurfaceFactory(ref);
            return real == null ? null : (s) => _Recording(real(s), plays);
          }),
          speechToTextProvider.overrideWithValue(
            FakeSpeechToText(heard: ['hello']),
          ),
          micPermissionsProvider.overrideWithValue(
            FakeMicPermissions(current: MicPermission.granted),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    await waitFor(t, find.byKey(const ValueKey('screen-talk')));
    final c = ProviderScope.containerOf(
      t.element(find.byKey(const ValueKey('screen-talk'))),
    );
    await linger(t);

    // 1. Talk: the mock glove signs "hello" (kit A/hello.csv, real pipeline)
    final source = c.read(gloveSourceProvider);
    final found = await source.scan().firstWhere((l) => l.isNotEmpty);
    await source.connect(found.first);
    await waitFor(t, find.text('Glove connected'));
    await tapAndWait(t, find.byKey(const ValueKey('talk-mock')));
    await tapAndWait(t, find.byKey(const ValueKey('mock-file-hello')));
    Navigator.of(t.element(find.byKey(const ValueKey('mock-person')))).pop();
    final repo = c.read(conversationRepositoryProvider);
    final end = DateTime.now().add(const Duration(seconds: 40));
    while (!repo.messages.any((m) => m.side == MessageSide.me)) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('no feed');
      await t.pump(const Duration(milliseconds: 200));
    }
    final me = repo.messages.lastWhere((m) => m.side == MessageSide.me);
    mark('1 Talk: signed "${me.text}"');
    await linger(t);

    // 2. History → the conversation → star
    await tapAndWait(t, find.text('History').last);
    final row = find.byKey(ValueKey('history-row-${me.conversationKey}'));
    await waitFor(t, row);
    mark("2 History: today's conversation");
    await tapAndWait(t, row);
    await tapAndWait(t, find.byKey(const ValueKey('star-0')));
    final phrase = c.read(savedPhrasesRepositoryProvider).phrases.single;
    expect(phrase.text, me.text);
    mark('3 starred: "${phrase.text}"');
    await tapAndWait(t, find.byKey(const ValueKey('conversation-back')));

    // 3. Starred: a tap speaks it (the phone's voice)
    await tapAndWait(t, find.byKey(const ValueKey('seg-1')));
    await tapAndWait(t, find.byKey(ValueKey('starred-${phrase.id}')));
    mark('4 Starred: tapped, spoken');
    await linger(t, _pace + const Duration(seconds: 1));

    // 4. Settings → Avatar studio → 0.5x → Save
    await tapAndWait(t, find.text('Settings').last);
    await waitFor(t, find.byKey(const ValueKey('settings-body')));
    await settingsRow(t, 'settings-avatar');
    await linger(t);
    await tapAndWait(t, find.byKey(const ValueKey('settings-avatar')));
    await waitFor(t, find.byKey(const ValueKey('studio-speed')));
    await linger(t, _pace * 2);
    await tapAndWait(t, find.byKey(const ValueKey('studio-speed')));
    await linger(t, _pace * 2);
    await tapAndWait(t, find.byKey(const ValueKey('studio-save')));
    expect(c.read(signSpeedProvider), .5);
    mark('5 Avatar studio: 0.5x saved');

    // 5. Talk: a heard "hello" is signed at the saved speed
    await tapAndWait(t, find.text('Talk').last);
    await waitFor(t, find.byKey(const ValueKey('screen-talk')));
    final ready = DateTime.now().add(const Duration(seconds: 60));
    while (c.read(avatarRuntimeProvider).value?.controller.status.value !=
        AvatarStatus.ready) {
      if (DateTime.now().isAfter(ready)) throw TimeoutException('no avatar');
      await t.pump(const Duration(milliseconds: 200));
    }
    plays.clear();
    // hold to talk: press, speak, let go
    final mic = find.byKey(const ValueKey('talk-mic'));
    await waitFor(t, mic);
    final hold = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(seconds: 1));
    await hold.up();
    final heard = DateTime.now().add(const Duration(seconds: 30));
    while (plays.isEmpty) {
      if (DateTime.now().isAfter(heard)) throw TimeoutException('no play');
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(plays.first, ('hello', .5));
    mark('6 Talk: heard "hello", signed ${plays.first}');
    await linger(t, _pace * 3);
  });
}
