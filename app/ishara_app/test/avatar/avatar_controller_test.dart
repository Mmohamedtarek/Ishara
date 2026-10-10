import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_events.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/packs/sign_language.dart';

import '../support/kit.dart';

/// A page that records commands and lets the test post messages.
class FakePage implements AvatarPage {
  final sent = <Map<String, Object?>>[];
  final _out = StreamController<String>.broadcast();
  Exception? failWith;

  void post(String type, [Map<String, Object?> data = const {}]) =>
      _out.add(jsonEncode({'type': type, ...data}));

  @override
  Stream<String> get messages => _out.stream;

  @override
  Future<void> send(Map<String, Object?> command) async {
    final e = failWith;
    if (e != null) throw e;
    sent.add(command);
  }

  List<String?> get cmds => [for (final c in sent) c['cmd'] as String?];
}

void main() {
  late AvatarLibrary library;
  late FakePage page;
  late AvatarController c;
  late List<AvatarEvent> events;

  setUpAll(() {
    library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
  });

  setUp(() {
    page = FakePage();
    c = AvatarController(
      page: page,
      library: library,
      libraryUrl: '../packs/asl/avatar/library.json',
      castUrl: '../avatar/cast.json',
      character: 'sara',
    );
    events = [];
    c.events.listen(events.add);
  });

  tearDown(() => c.dispose());

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  Future<void> ready() async {
    page.post('loaded');
    await pump();
    page.post('ready', {'character': 'sara', 'signs': library.labels.toList()});
    await pump();
  }

  test('commands wait for the page; init goes first, then in order', () async {
    final a = c.play('hello');
    final b = c.play('yes', speed: 1.5, loop: true);
    c.stop();
    await pump();
    expect(page.sent, isEmpty);
    page.post('loaded');
    await pump();
    expect(page.cmds, ['init', 'play', 'play', 'stop']);
    expect(page.sent.first, {
      'cmd': 'init',
      'cast': '../avatar/cast.json',
      'library': '../packs/asl/avatar/library.json',
      'character': 'sara',
      'reduceMotion': false,
    });
    expect(page.sent[1], {
      'cmd': 'play',
      'id': a,
      'label': 'hello',
      'speed': 1.0,
      'loop': false,
    });
    expect(page.sent[2]['speed'], 1.5);
    expect(page.sent[2]['loop'], true);
    expect(b, a + 1);
    expect(c.status.value, AvatarStatus.loading);
  });

  test('ready: status, events; later commands go straight out', () async {
    await ready();
    expect(c.status.value, AvatarStatus.ready);
    expect(events.whereType<AvatarReady>().single.character, 'sara');
    page.sent.clear();
    final id = c.noSign(speed: 9);
    c
      ..customize(skin: 1)
      ..reframe(captionHeight: 80)
      ..pause()
      ..resume()
      ..setStats(on: true)
      ..preview(label: 'water', t: .2, view: -90);
    await pump();
    expect(page.sent, [
      {'cmd': 'noSign', 'id': id, 'speed': 2.0},
      {'cmd': 'customize', 'skin': 1, 'outfit': null},
      {'cmd': 'reframe', 'captionPx': 80.0},
      {'cmd': 'pause'},
      {'cmd': 'resume'},
      {'cmd': 'stats', 'on': true},
      {
        'cmd': 'preview',
        'label': 'water',
        't': .2,
        'view': -90.0,
        'frozen': true,
      },
    ]);
  });

  test('sign events reach listeners with ids and durations', () async {
    await ready();
    final id = c.play('hello');
    page
      ..post('signStarted', {'id': id, 'label': 'hello', 'ms': 1420.5})
      ..post('signEnded', {'id': id, 'label': 'hello', 'interrupted': false});
    await pump();
    final s = events.whereType<SignStarted>().single;
    expect(s.id, id);
    expect(s.label, 'hello');
    expect(s.duration, const Duration(microseconds: 1420500));
    expect(
      s.duration,
      library.duration('hello') + const Duration(microseconds: 500),
    );
    final e = events.whereType<SignEnded>().single;
    expect((e.id, e.label, e.interrupted), (id, 'hello', false));
  });

  test('an unknown label is a bug, never sent', () {
    expect(() => c.play('love'), throwsArgumentError);
    expect(() => c.play('rest'), throwsArgumentError);
    expect(() => c.preview(label: 'bananas'), throwsArgumentError);
    c.preview(view: 30); // camera only
  });

  test('with the cast, a hidden character (RB-1: Sara) becomes Nour', () async {
    final page2 = FakePage();
    final c2 = AvatarController(
      page: page2,
      library: library,
      libraryUrl: '../packs/asl/avatar/library.json',
      castUrl: '../avatar/cast.json',
      character: 'sara', // e.g. a stored or synced profile
      cast: AvatarCast.parse(readText('assets/avatar/cast.json')),
    );
    addTearDown(c2.dispose);
    expect(c2.character, 'nour');
    page2.post('loaded');
    await pump();
    expect(page2.sent.first['character'], 'nour');
    c2.setCharacter('sara', greet: false);
    await pump();
    expect(c2.character, 'nour');
    expect(page2.sent.last, {
      'cmd': 'setCharacter',
      'character': 'nour',
      'greet': false,
    });
  });

  test('setCharacter, reduce motion (sent only on change)', () async {
    await ready();
    page.sent.clear();
    c
      ..setCharacter('nour', greet: false)
      ..setReduceMotion(on: false)
      ..setReduceMotion(on: true)
      ..setReduceMotion(on: true);
    await pump();
    expect(page.sent, [
      {'cmd': 'setCharacter', 'character': 'nour', 'greet': false},
      {'cmd': 'setReduceMotion', 'on': true},
    ]);
    expect(c.character, 'nour');
  });

  test('a reloaded page gets init again (same character)', () async {
    await ready();
    c.setCharacter('nour');
    page.sent.clear();
    page.post('loaded');
    await pump();
    expect(page.sent.single['cmd'], 'init');
    expect(page.sent.single['character'], 'nour');
    expect(c.status.value, AvatarStatus.loading);
  });

  test('a reload: open signs end (interrupted), commands wait, state is '
      'replayed after init', () async {
    await ready();
    c
      ..pause()
      ..setStats(on: true)
      ..reframe(captionHeight: 72)
      ..customize(outfit: 2);
    final a = c.play('hello');
    final b = c.noSign();
    await pump();
    page
      ..post('signStarted', {'id': a, 'label': 'hello', 'ms': 1000})
      ..post('signEnded', {'id': a, 'label': 'hello', 'interrupted': true});
    await pump();
    events.clear();
    page.sent.clear();
    page.post('pageStarted');
    await pump();
    expect(c.status.value, AvatarStatus.loading);
    // only b was still open: it ends once, interrupted
    expect(
      [
        for (final e in events.whereType<SignEnded>())
          (e.id, e.label, e.interrupted),
      ],
      [(b, null, true)],
    );
    final d = c.play('yes');
    await pump();
    expect(page.sent, isEmpty, reason: 'waits for the new page');
    page.post('loaded');
    await pump();
    expect(page.cmds, [
      'init',
      'pause',
      'stats',
      'reframe',
      'customize',
      'play',
    ]);
    expect(page.sent.last['id'], d);
    expect(page.sent[3], {'cmd': 'reframe', 'captionPx': 72.0});
    expect(page.sent[4], {'cmd': 'customize', 'skin': null, 'outfit': 2});
    c
      ..resume()
      ..setStats(on: false);
    page
      ..post('pageStarted')
      ..post('loaded');
    await pump();
    expect(events.whereType<SignEnded>().map((e) => e.id), contains(d));
  });

  test('a page load failure fails the avatar (no endless loading)', () async {
    page
      ..post('pageStarted')
      ..post('error', {'code': 'page', 'message': '-6 net::ERR_CONNECTION'});
    await pump();
    expect(c.status.value, AvatarStatus.failed);
  });

  test(
    'fatal errors before ready fail the avatar; later ones do not',
    () async {
      page
        ..post('loaded')
        ..post('error', {'code': 'webgl', 'message': 'no context'});
      await pump();
      expect(c.status.value, AvatarStatus.failed);
      final err = events.whereType<AvatarError>().single;
      expect((err.code, err.message), ('webgl', 'no context'));

      final c2 = AvatarController(
        page: page,
        library: library,
        libraryUrl: '',
        castUrl: '',
      );
      addTearDown(c2.dispose);
      page
        ..post('loaded')
        ..post('ready', {'character': 'nour', 'signs': library.labels.toList()})
        ..post('error', {'code': 'character', 'message': 'sara failed'})
        ..post('error', {'code': 'unknown_sign'});
      await pump();
      expect(c2.status.value, AvatarStatus.ready);
    },
  );

  test('the page library must be the app library', () async {
    page
      ..post('loaded')
      ..post('ready', {
        'character': 'nour',
        'signs': ['hello'],
      });
    await pump();
    expect(c.status.value, AvatarStatus.failed);
    expect(events.whereType<AvatarReady>(), isEmpty);
    expect(events.whereType<AvatarError>().single.code, 'data');
  });

  test('a failing page call becomes an error event', () async {
    await ready();
    page.failWith = Exception('webview gone');
    c.stop();
    await pump();
    expect(events.whereType<AvatarError>().last.code, 'page');
  });

  test('dispose: no more commands, events or listeners', () async {
    await c.dispose();
    await c.dispose(); // twice is fine
    c.play('hello');
    page.post('loaded');
    await pump();
    expect(page.sent, isEmpty);
  });

  test('the unavailable surface makes the avatar fail cleanly', () async {
    final s = UnavailableAvatarSurface();
    final c3 = AvatarController(
      page: s,
      library: library,
      libraryUrl: '',
      castUrl: '',
    );
    await pump();
    expect(c3.status.value, AvatarStatus.failed);
    await s.send({'cmd': 'stop'});
    expect(s.buildView(), isNotNull);
    await c3.dispose();
    await s.dispose();
  });

  test('commands become safe JavaScript', () {
    expect(
      avatarCommandScript({'cmd': 'play', 'label': "x');alert('1"}),
      '''window.__ishara && window.__ishara.receive({"cmd":"play","label":"x');alert('1"});''',
    );
  });

  group('messages', () {
    test('every event type parses', () {
      expect(AvatarEvent.parse('{"type":"loaded"}'), isA<AvatarLoaded>());
      expect(
        AvatarEvent.parse('{"type":"character","character":"sara"}'),
        isA<AvatarCharacterShown>().having((e) => e.character, 'c', 'sara'),
      );
      expect(
        AvatarEvent.parse('{"type":"stats","fps":59.5}'),
        isA<AvatarStats>().having((e) => e.fps, 'fps', 59.5),
      );
      expect(
        AvatarEvent.parse('{"type":"contextRestored"}'),
        isA<AvatarContextRestored>(),
      );
      final jpeg = base64Encode([0xff, 0xd8, 1, 2]);
      expect(
        AvatarEvent.parse(
          jsonEncode({
            'type': 'thumbnail',
            'character': 'nour',
            'dataUrl': 'data:image/jpeg;base64,$jpeg',
          }),
        ),
        isA<AvatarThumbnail>().having((e) => e.jpeg, 'jpeg', [
          0xff,
          0xd8,
          1,
          2,
        ]),
      );
      final noWord = AvatarEvent.parse(
        '{"type":"signStarted","id":4,"label":null,"ms":520,"loop":false}',
      ) as SignStarted;
      expect(noWord.label, isNull);
      expect(noWord.duration, const Duration(milliseconds: 520));
      final greet = AvatarEvent.parse(
        '{"type":"signStarted","id":null,"label":"hello"}',
      ) as SignStarted;
      expect((greet.id, greet.duration), (null, Duration.zero));
      expect(
        AvatarEvent.parse('{"type":"error"}'),
        isA<AvatarError>().having((e) => e.code, 'code', 'unknown'),
      );
    });

    test('malformed messages become bad_message errors', () {
      for (final m in [
        'not json',
        '[1]',
        '{"type":"nope"}',
        '{}',
        '{"type":"ready"}',
        '{"type":"ready","character":"x"}',
        '{"type":"thumbnail","character":"x","dataUrl":"data:image/png;base64,AA=="}',
        '{"type":"thumbnail","character":"x","dataUrl":"data:image/jpeg;base64,***"}',
        '{"type":"thumbnail"}',
        '{"type":"stats"}',
        '{"type":"character"}',
      ]) {
        expect(
          AvatarEvent.parse(m),
          isA<AvatarError>().having((e) => e.code, 'code', 'bad_message'),
          reason: m,
        );
      }
      final neg = AvatarEvent.parse('{"type":"signStarted","ms":-5}');
      expect((neg as SignStarted).duration, Duration.zero);
    });
  });
}
