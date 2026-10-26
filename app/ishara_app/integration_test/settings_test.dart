// On the emulator (WebView + WebGL):
//   flutter test integration_test/settings_test.dart -d <device>
// Settings persist across an app restart: the Avatar studio saves 0.5x,
// the app restarts on the same store, and Talk signs a heard sentence at
// 0.5x on the real avatar page. Switches and the theme survive the restart
// too. Prints SETTINGS lines for the record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

import '../test/support/fake_speech.dart';

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

Future<void> tapAndWait(WidgetTester t, Finder f) async {
  await waitFor(t, f);
  await t.tap(f.first);
  await t.pump(const Duration(milliseconds: 400));
}

/// Brings a Settings row on screen, scrolling down then up (lazy list).
Future<void> settingsRow(WidgetTester t, String key) async {
  final row = find.byKey(ValueKey(key));
  final list = find
      .descendant(
        of: find.byKey(const ValueKey('settings-body')),
        matching: find.byType(Scrollable),
      )
      .first;
  if (row.evaluate().isEmpty) {
    // from the top, downwards
    await t.drag(list, const Offset(0, 4000));
    await t.pump(const Duration(milliseconds: 600));
    await t.scrollUntilVisible(row, 200, scrollable: list, maxScrolls: 40);
  }
  await t.ensureVisible(row);
  await t.pump(const Duration(milliseconds: 200));
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

  testWidgets('the studio speed and the switches survive a restart; Talk '
      'signs at the saved speed', (t) async {
    void mark(String what) => debugPrint('SETTINGS $what');
    final store = MemoryKeyValueStore({
      'onboarding.done': true,
      'setup.spoken': 'en',
      'setup.role': 'sign',
    });
    final plays = <(String, double)>[];
    setUpLogging(sink: (l) => debugPrint('SETTINGS log $l'));
    ProviderContainer? running;

    Future<ProviderContainer> launch(
      String route, {
      List<Override> extra = const [],
      bool webView = true,
    }) async {
      // a restart: the old app (and its one WebView) goes away first
      await t.pumpWidget(const SizedBox());
      await t.pump();
      running?.dispose();
      await t.pump(const Duration(milliseconds: 500));
      final c = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: route),
          ),
          avatarSurfaceFactoryProvider.overrideWith((ref) {
            // one WebGL page per process, as on a phone: the 1st run has
            // none (the emulator's GPU host crashes on a second one)
            final real = webView ? avatarSurfaceFactory(ref) : null;
            return real == null ? null : (s) => _Recording(real(s), plays);
          }),
          ...extra,
        ],
      );
      running = c;
      await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const IsharaApp()),
      );
      return c;
    }

    // 1st run: Settings → switches, theme → Avatar studio → 0.5x → Save
    var c = await launch(AppRoutes.settings, webView: false);
    await waitFor(t, find.byKey(const ValueKey('settings-body')));
    for (final key in ['settings-vibrate', 'settings-subtitles']) {
      await settingsRow(t, key);
      await tapAndWait(t, find.byKey(ValueKey(key)));
    }
    await settingsRow(t, 'settings-theme');
    await tapAndWait(
      t,
      find.descendant(
        of: find.byKey(const ValueKey('settings-theme')),
        matching: find.byKey(const ValueKey('seg-2')),
      ),
    );
    await settingsRow(t, 'settings-avatar');
    await tapAndWait(t, find.byKey(const ValueKey('settings-avatar')));
    await waitFor(t, find.byKey(const ValueKey('studio-speed')));
    await tapAndWait(t, find.byKey(const ValueKey('studio-speed')));
    await tapAndWait(t, find.byKey(const ValueKey('studio-save')));
    expect(c.read(signSpeedProvider), .5);
    mark('saved 0.5x; vibrate on, subtitles off, dark');
    await t.pump(const Duration(seconds: 3));

    // 2nd run (a restart: new providers, same store) → Talk hears "hello"
    plays.clear();
    c = await launch(
      AppRoutes.talk,
      extra: [
        speechToTextProvider.overrideWithValue(
          FakeSpeechToText(heard: ['hello']),
        ),
        micPermissionsProvider.overrideWithValue(
          FakeMicPermissions(current: MicPermission.granted),
        ),
      ],
    );
    await waitFor(t, find.byKey(const ValueKey('screen-talk')));
    final s = c.read(appSettingsControllerProvider);
    expect(
      (s.vibrate, s.subtitles, s.themeMode),
      (true, false, ThemeMode.dark),
    );
    expect(c.read(signSpeedProvider), .5);
    expect(find.byKey(const ValueKey('talk-caption-off')), findsOneWidget);
    // the real avatar page is up before the person speaks
    final ready = DateTime.now().add(const Duration(seconds: 60));
    while (c.read(avatarRuntimeProvider).value?.controller.status.value !=
        AvatarStatus.ready) {
      if (DateTime.now().isAfter(ready)) throw TimeoutException('no avatar');
      await t.pump(const Duration(milliseconds: 200));
    }
    mark('avatar ready');
    await waitFor(t, find.byKey(const ValueKey('talk-mic')));
    // hold to talk: press, speak, let go
    final mic = find.byKey(const ValueKey('talk-mic'));
    await waitFor(t, mic);
    final hold = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(seconds: 1));
    await hold.up();
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (plays.isEmpty) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('no play');
      await t.pump(const Duration(milliseconds: 200));
    }
    mark('after restart: Talk plays ${plays.first}');
    expect(plays.first, ('hello', .5));
    await t.pumpWidget(const SizedBox());
    running?.dispose();
  });
}
