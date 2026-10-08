import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:logging/logging.dart';

void main() {
  group('Failure', () {
    test('kinds and toString', () {
      const a = AssetFailure('missing', path: 'assets/x');
      const pf = ParseFailure('bad json', source: 'decider.json', cause: 'x');
      const u = UnexpectedFailure('boom');
      expect([a.kind, pf.kind, u.kind], ['asset', 'parse', 'unexpected']);
      expect(a.path, 'assets/x');
      expect(pf.source, 'decider.json');
      expect(a.toString(), 'Failure(asset): missing');
      expect(pf.toString(), 'Failure(parse): bad json <- x');
    });
  });

  group('Result.guard', () {
    test('value -> Ok', () async {
      final r = await Result.guard(() async => 42);
      expect(r, isA<Ok<int>>());
      expect(r.valueOrThrow, 42);
    });

    test('a Failure is kept as is', () async {
      const f = ParseFailure('bad');
      final r = await Result.guard<int>(() async => throw f);
      expect((r as Err<int>).failure, same(f));
      expect(() => r.valueOrThrow, throwsA(same(f)));
    });

    test(
      'any other Exception becomes UnexpectedFailure with the cause',
      () async {
        final r = await Result.guard<int>(
          () async => throw const FormatException('f'),
        );
        final f = (r as Err<int>).failure;
        expect(f, isA<UnexpectedFailure>());
        expect(f.cause, isA<FormatException>());
        expect(f.stackTrace, isNotNull);
      },
    );

    test('Errors (bugs) are not swallowed', () async {
      await expectLater(
        Result.guard<int>(() async => throw StateError('bug')),
        throwsStateError,
      );
    });
  });

  group('logging', () {
    final lines = <String>[];
    setUpAll(() => setUpLogging(sink: lines.add));
    setUp(lines.clear);

    test('records are one JSON line with event and fields', () {
      Log('glove').info('connected', {'rssi': -60});
      final j = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(j['event'], 'connected');
      expect(j['rssi'], -60);
      expect(j['level'], 'INFO');
      expect(j['logger'], 'ishara.glove');
      expect(DateTime.tryParse(j['t'] as String), isNotNull);
    });

    test('debug and warn levels', () {
      Log('x')
        ..debug('d')
        ..warn('w', {'n': 1});
      expect(
        lines.map((l) => (jsonDecode(l) as Map<String, dynamic>)['level']),
        ['FINE', 'WARNING'],
      );
    });

    test('failures carry kind, message, cause and stack trace', () {
      Log('kit').failure(
        'load',
        ParseFailure(
          'bad',
          cause: const FormatException('f'),
          stackTrace: StackTrace.current,
        ),
        {'file': 'labels.txt'},
      );
      final j = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(j['failure'], 'parse');
      expect(j['message'], 'bad');
      expect(j['file'], 'labels.txt');
      expect(j['error'], contains('FormatException'));
      expect(lines, hasLength(2), reason: 'stack trace line');
    });

    test('plain package:logging records still format', () {
      Logger('other').info('hello');
      expect(
        (jsonDecode(lines.single) as Map<String, dynamic>)['event'],
        'hello',
      );
    });

    test('setting up again replaces the sink (no duplicates)', () {
      final second = <String>[];
      setUpLogging(sink: second.add);
      Log('x').info('once');
      expect(second, hasLength(1));
      expect(lines, isEmpty);
      setUpLogging(sink: lines.add);
    });

    test('release redaction drops free text, keeps kind and fields', () {
      final redacted = <String>[];
      setUpLogging(sink: redacted.add, redact: true);
      Log('kit').failure(
        'load',
        const ParseFailure('bad: hello thanks', cause: 'raw 1,2,3'),
        {'file': 'labels.txt'},
      );
      Logger('other').info('free text');
      setUpLogging(sink: lines.add);
      final j = jsonDecode(redacted.first) as Map<String, dynamic>;
      expect(j['failure'], 'parse');
      expect(j['file'], 'labels.txt');
      expect(j.containsKey('message'), isFalse);
      expect(j['error'], 'redacted');
      expect(redacted.join(), isNot(contains('hello')));
      expect(redacted.join(), isNot(contains('1,2,3')));
      expect(redacted.join(), isNot(contains('free text')));
    });

    test('LogEvent toString is JSON', () {
      expect(jsonDecode(const LogEvent('e', {'a': 1}).toString()), {
        'event': 'e',
        'a': 1,
      });
    });
  });
}
