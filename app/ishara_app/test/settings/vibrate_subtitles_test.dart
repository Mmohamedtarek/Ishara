import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/device/haptics.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/talk/presentation/talk_screen.dart';

import '../support/fake_sos.dart';
import '../support/fake_speech.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

class _Haptics implements Haptics {
  final pulses = <String>[];
  @override
  Future<void> short() async => pulses.add('short');
  @override
  Future<void> long() async => pulses.add('long');
}

Finder _key(String k) => find.byKey(ValueKey(k));

Future<(TalkFakes, _Haptics)> _talk(
  WidgetTester t, {
  required Map<String, Object> store,
  List<String> heard = const [],
}) async {
  addTearDown(rootBundle.clear);
  final talk = TalkFakes();
  addTearDown(talk.feed.dispose);
  final haptics = _Haptics();
  await pumpScreen(
    t,
    const TalkScreen(),
    harness: Harness(
      store: MemoryKeyValueStore({'setup.spoken': 'en', ...store}),
    ),
    overrides: [
      ...talk.overrides,
      ...SosFakes().overrides,
      hapticsProvider.overrideWithValue(haptics),
      speechToTextProvider.overrideWithValue(FakeSpeechToText(heard: heard)),
      micPermissionsProvider.overrideWithValue(
        FakeMicPermissions(current: MicPermission.granted),
      ),
    ],
  );
  return (talk, haptics);
}

void main() {
  group('Vibrate (S9-1)', () {
    testWidgets('on: a short pulse for a spoken glove word, a long one for '
        'SOS', (t) async {
      final (talk, h) = await _talk(t, store: {'settings.vibrate': true});
      talk.feed.word('hello');
      await settle(t);
      talk.feed.tentative('yes'); // not spoken: no pulse
      await settle(t);
      expect(h.pulses, ['short']);
      await tapIt(t, _key('talk-quick-sos'));
      expect(h.pulses, ['short', 'long']);
      await t.pump(const Duration(seconds: 12));
    });

    testWidgets('on: a short pulse when a heard sentence starts signing', (
      t,
    ) async {
      final (_, h) = await _talk(
        t,
        store: {'settings.vibrate': true},
        heard: ['hello'],
      );
      await tapIt(t, _key('talk-mic'));
      await settle(t, n: 10);
      expect(h.pulses, contains('short'));
      await t.pump(const Duration(seconds: 10));
    });

    testWidgets('off (default): nothing', (t) async {
      final (talk, h) = await _talk(t, store: const {});
      talk.feed.word('hello');
      await settle(t);
      await tapIt(t, _key('talk-quick-sos'));
      expect(h.pulses, isEmpty);
      await t.pump(const Duration(seconds: 12));
    });
  });

  group('Subtitles (S9-2)', () {
    testWidgets("on (default): Talk's caption shows; off: none", (t) async {
      await _talk(t, store: const {});
      expect(_key('talk-caption'), findsOneWidget);
    });

    testWidgets('off: no caption under the avatar', (t) async {
      await _talk(t, store: {'settings.subtitles': false});
      expect(_key('talk-caption'), findsNothing);
      expect(_key('talk-caption-off'), findsOneWidget);
    });
  });
}
