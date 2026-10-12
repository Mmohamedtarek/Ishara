import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/sign_sequencer.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/packs/sign_language.dart';

import '../support/fake_avatar_page.dart';
import '../support/kit.dart';

void main() {
  late AvatarLibrary library;
  late FakePage page;
  late AvatarController avatar;
  late SignSequencer seq;

  setUpAll(() {
    library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
  });

  /// Made inside each test body, so their streams run on the test's fake
  /// clock.
  void make() {
    page = FakePage();
    avatar = AvatarController(
      page: page,
      library: library,
      libraryUrl: 'l',
      castUrl: 'c',
    );
    seq = SignSequencer(avatar);
    addTearDown(() async {
      await seq.dispose();
      await avatar.dispose();
    });
  }

  /// Plays [segments]; the outcome lands in the returned holder (awaiting
  /// an unfinished future would hang a widget test).
  List<SequenceOutcome> start(List<SignSegment> segments, {double speed = 1}) {
    final out = <SequenceOutcome>[];
    unawaited(seq.play(segments, speed: speed).then(out.add));
    return out;
  }

  Future<void> ready(WidgetTester t) async {
    make();
    page.post('loaded');
    await t.pump();
    page.post('ready', {'character': 'nour', 'signs': library.labels.toList()});
    await t.pump();
  }

  /// The play / noSign commands sent so far: label, or null for noSign.
  List<String?> played() => [
    for (final c in page.sent)
      if (c['cmd'] == 'play' || c['cmd'] == 'noSign') c['label'] as String?,
  ];

  int lastId() =>
      page.sent.lastWhere(
            (c) => c['cmd'] == 'play' || c['cmd'] == 'noSign',
          )['id']!
          as int;

  void end(int id, {bool interrupted = false}) =>
      page.post('signEnded', {'id': id, 'interrupted': interrupted});

  const hiThere = [
    SignSegment(['Hello'], 'hello'),
    SignSegment(['there'], null),
    SignSegment(['thank', 'you'], 'thanks'),
  ];

  testWidgets('plays segments in order, each after the last one ended', (
    t,
  ) async {
    await ready(t);
    final indexes = <int?>[];
    seq.current.addListener(() => indexes.add(seq.current.value));
    final done = start(hiThere, speed: 1.5);
    await t.pump();
    expect(played(), ['hello']);
    expect(page.sent.last['speed'], 1.5);
    end(lastId());
    await t.pump();
    expect(played(), ['hello', null], reason: 'no sign: ready pose');
    end(lastId());
    await t.pump();
    expect(played(), ['hello', null, 'thanks']);
    end(lastId());
    await t.pump();
    expect(done, [SequenceOutcome.completed]);
    expect(indexes, [0, 1, 2, null]);
  });

  testWidgets('an interrupted sign stops the sentence', (t) async {
    await ready(t);
    final done = start(hiThere);
    await t.pump();
    end(lastId(), interrupted: true);
    await t.pump();
    expect(done, [SequenceOutcome.interrupted]);
    expect(played(), ['hello'], reason: 'nothing more is sent');
    expect(seq.current.value, isNull);
  });

  testWidgets('a page reload ends the open sign as interrupted', (t) async {
    await ready(t);
    final done = start(hiThere);
    await t.pump();
    page.post('pageStarted');
    await t.pump();
    expect(done, [SequenceOutcome.interrupted]);
  });

  testWidgets('a lost signEnded: moves on after the length + margin, and '
      'stops the avatar', (t) async {
    await ready(t);
    final done = start(const [
      SignSegment(['yes'], 'yes'),
      SignSegment(['no'], 'no'),
    ]);
    await t.pump();
    final wait = library.duration('yes') + seq.margin;
    await t.pump(wait - const Duration(milliseconds: 10));
    expect(played(), ['yes'], reason: 'still waiting');
    await t.pump(const Duration(milliseconds: 20));
    expect(page.sent.map((c) => c['cmd']), contains('stop'));
    expect(played(), ['yes', 'no']);
    end(lastId());
    await t.pump();
    expect(done, [SequenceOutcome.completed]);
  });

  testWidgets('cancel ends the sentence and the sign', (t) async {
    await ready(t);
    final done = start(hiThere);
    await t.pump();
    seq.cancel();
    await t.pump();
    expect(done, [SequenceOutcome.cancelled]);
    expect(page.sent.last['cmd'], 'stop');
    expect(seq.current.value, isNull);
  });

  testWidgets('a newer sentence cancels the one playing', (t) async {
    await ready(t);
    final first = start(hiThere);
    await t.pump();
    final second = start(const [
      SignSegment(['yes'], 'yes'),
    ]);
    await t.pump();
    expect(first, [SequenceOutcome.cancelled]);
    expect(played(), ['hello', 'yes']);
    end(lastId());
    await t.pump();
    expect(second, [SequenceOutcome.completed]);
  });

  testWidgets('avatar not ready: nothing is sent (no late signs); each '
      'caption word lasts the sign length', (t) async {
    make();
    final indexes = <int?>[];
    seq.current.addListener(() => indexes.add(seq.current.value));
    final done = start(const [
      SignSegment(['hello'], 'hello'),
      SignSegment(['there'], null),
    ]);
    await t.pump();
    await t.pump(library.duration('hello') - const Duration(milliseconds: 5));
    expect(indexes, [0]);
    await t.pump(const Duration(milliseconds: 10));
    expect(indexes, [0, 1]);
    await t.pump(SignSequencer.noSignDuration(1));
    expect(done, [SequenceOutcome.completed]);
    page.post('loaded');
    await t.pump();
    expect(played(), isEmpty);
  });

  test('no-sign slot = the engine: max(360, 520 / speed) ms', () {
    expect(SignSequencer.noSignDuration(1).inMilliseconds, 520);
    expect(SignSequencer.noSignDuration(.5).inMilliseconds, 1040);
    expect(SignSequencer.noSignDuration(2).inMilliseconds, 360);
    expect(SignSequencer.noSignDuration(10).inMilliseconds, 360);
  });

  testWidgets('an empty sentence completes at once', (t) async {
    make();
    final done = start(const []);
    await t.pump();
    expect(done, [SequenceOutcome.completed]);
  });
}
