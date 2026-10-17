import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/config/app_rules.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/settings/settings_store.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/settings/application/data_export.dart';
import 'package:ishara_app/features/settings/domain/tap_counter.dart';

import '../support/fake_avatar_page.dart';
import '../support/fake_talk.dart';

ProviderContainer _c(MemoryKeyValueStore kv) {
  final c = ProviderContainer(
    overrides: [
      keyValueStoreProvider.overrideWithValue(kv),
      appRulesProvider.overrideWithValue(AsyncData(testAppRules)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  _characterTests();

  test('every setting persists (S6-2 pattern, versioned) and comes back '
      'after a restart', () async {
    final kv = MemoryKeyValueStore();
    final c = _c(kv);
    expect(c.read(appSettingsControllerProvider), const AppSettings());
    c.read(appSettingsControllerProvider.notifier)
      ..setLanguage(AppLanguage.ar)
      ..setThemeMode(ThemeMode.dark)
      ..setBigText(on: true)
      ..setHighContrast(on: true)
      ..setVibrate(on: true)
      ..setSubtitles(on: false);
    c.read(developerModeProvider.notifier).set(on: true);
    await c.read(signSpeedProvider.notifier).save(.5);
    await c.read(savedCharacterProvider.notifier).save('nour');
    await Future<void>.delayed(Duration.zero);
    expect(kv.getInt(SettingsStore.kVersion), SettingsStore.schemaVersion);

    final again = _c(kv);
    expect(
      again.read(appSettingsControllerProvider),
      const AppSettings(
        language: AppLanguage.ar,
        themeMode: ThemeMode.dark,
        bigText: true,
        highContrast: true,
        vibrate: true,
        subtitles: false,
      ),
    );
    expect(again.read(developerModeProvider), isTrue);
    expect(again.read(signSpeedProvider), .5);
    expect(again.read(savedCharacterProvider), 'nour');
    expect(
      SettingsStore(kv).export().keys,
      containsAll([
        SettingsStore.kVersion,
        SettingsStore.kLanguage,
        SettingsStore.kSignSpeed,
        SettingsStore.kDeveloper,
      ]),
    );
    await SettingsStore(kv).clear();
    expect(kv.keys, isEmpty);
  });

  test('defaults: System theme (Q-D3), subtitles on, vibrate off, 1x', () {
    final c = _c(MemoryKeyValueStore());
    final s = c.read(appSettingsControllerProvider);
    expect(s.themeMode, ThemeMode.system);
    expect(s.subtitles, isTrue);
    expect(s.vibrate, isFalse);
    expect(c.read(signSpeedProvider), 1);
    expect(c.read(developerModeProvider), isFalse);
  });

  test("Talk's speed button changes this session only; the studio's Save "
      'keeps it (S7-3)', () async {
    final kv = MemoryKeyValueStore();
    final c = _c(kv);
    c.read(signSpeedProvider.notifier).cycle();
    expect(c.read(signSpeedProvider), .5);
    expect(_c(kv).read(signSpeedProvider), 1);
    await c.read(signSpeedProvider.notifier).save(1.5);
    expect(_c(kv).read(signSpeedProvider), 1.5);
    // a stored value outside the cycle falls back to 1x
    await kv.setInt(SettingsStore.kSignSpeed, 7);
    expect(_c(kv).read(signSpeedProvider), 1);
  });

  test('developer switch: every 7th tap in a row', () {
    final t = TapCounter();
    expect([for (var i = 0; i < 6; i++) t.tap()], everyElement(isFalse));
    expect(t.taps, 6);
    expect(t.tap(), isTrue);
    expect(t.taps, 0);
    expect([for (var i = 0; i < 7; i++) t.tap()].last, isTrue);
  });

  test('Export my data: the conversation, saved phrases and Learn log, as '
      'stored', () async {
    final kv = MemoryKeyValueStore();
    final c = _c(kv);
    await c
        .read(conversationRepositoryProvider)
        .add(
          TalkMessage(
            side: MessageSide.me,
            text: 'hello',
            at: DateTime(2026, 10, 14, 9),
          ),
        );
    await c.read(savedPhrasesRepositoryProvider).star('hello');
    final ref = c.read(_refProvider);
    final data = DataExport.build(ref);
    expect(data.keys.toSet(), {
      'app',
      'format',
      'exportedAt',
      'conversation',
      'savedPhrases',
      'learnActivity',
    });
    final conv = data['conversation']! as Map<String, Object>;
    expect(conv['talk.messages'], contains('hello'));
    expect((data['savedPhrases']! as Map).keys, contains('phrases.all'));
    expect(data['learnActivity'], isEmpty);
    final json = utf8.decode(DataExport.bytes(data));
    expect(jsonDecode(json), isA<Map<String, Object?>>());
  });

  test('Export my data adds the old values kept aside (step 10a), when '
      'there are any', () {
    final c = _c(
      MemoryKeyValueStore({
        'talk.messages':
            '[{"side":"me","text":"ok",'
            '"at":"2026-10-15T10:00:00.000"},7]',
        'phrases.all': '{damaged',
      }),
    );
    final data = DataExport.build(c.read(_refProvider));
    expect(data['keptAside'], [
      {'key': 'talk.messages[1]', 'reason': 'unreadable', 'value': '7'},
      {'key': 'phrases.all', 'reason': 'damaged', 'value': '{damaged'},
    ]);
    final conv = data['conversation']! as Map<String, Object>;
    expect(conv['talk.messages'], contains('"text":"ok"'));
  });

  test("app_rules.json: the 10-minute gap and Egypt's numbers are data", () {
    expect(testAppRules.conversationGap, const Duration(minutes: 10));
    expect(testAppRules.emergencyRegion, 'EG');
    expect(testAppRules.ambulance, '123');
    expect(testAppRules.emergencyNumbers['police'], '122');
    for (final bad in [
      'x',
      '[]',
      '{"conversationGapMinutes": 0, "emergency": {}}',
      _rules('EG', '{"EG": {"ambulance": "1-2-3"}}'),
      _rules('FR', '{"EG": {}}'),
    ]) {
      expect(() => AppRules.parse(bad), throwsA(anything), reason: bad);
    }
  });
}

String _rules(String region, String numbers) =>
    '{"conversationGapMinutes": 10, '
    '"emergency": {"region": "$region", "numbers": $numbers}}';

final _refProvider = Provider<Ref>((ref) => ref);

void _characterTests() {
  test('saving a character switches the avatar already running (the name '
      'and the model never disagree); the same one again: no second '
      'greeting', () async {
    final castJson = jsonDecode(
      File(avatarCastAsset).readAsStringSync(),
    ) as Map<String, Object?>;
    // two characters on offer (Sara is hidden in v1, RB-1)
    ((castJson['characters']! as Map<String, Object?>)['sara']!
            as Map<String, Object?>)
        .remove('hidden');
    final cast = AvatarCast.parse(jsonEncode(castJson));
    final page = FakePage();
    final avatar = AvatarController(
      page: page,
      library: AvatarLibrary.parse(
        File('assets/packs/asl/avatar/library.json').readAsStringSync(),
        language: SignLanguage.asl,
      ),
      libraryUrl: 'l',
      castUrl: 'c',
      cast: cast,
    );
    final c = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        avatarCastProvider.overrideWithValue(AsyncData(cast)),
        avatarRuntimeProvider.overrideWithValue(
          AsyncData(AvatarRuntime(avatar, UnavailableAvatarSurface())),
        ),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await avatar.dispose();
    });
    page.post('loaded');
    await Future<void>.delayed(Duration.zero);
    List<Object?> switches() => [
      for (final s in page.sent)
        if (s['cmd'] == 'setCharacter') s['character'],
    ];
    await c.read(savedCharacterProvider.notifier).save('sara');
    expect(switches(), ['sara']);
    await c.read(savedCharacterProvider.notifier).save('sara');
    expect(switches(), ['sara'], reason: 'already showing her');
  });
}
