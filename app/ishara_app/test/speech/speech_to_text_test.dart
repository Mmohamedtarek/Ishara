import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_trace.dart';
import 'package:logging/logging.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// The plugin's method channel, answered here as the phone would.
class _Phone {
  new() {
    _messenger.setMockMethodCallHandler(channel, _handle);
  }

  static const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  static final TestDefaultBinaryMessenger _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  bool initOk = true;

  /// Holds `locales` / `listen` until completed (a slow phone).
  Completer<void>? localesGate;
  Completer<void>? listenGate;

  /// The phone never answers `locales` (Android 13+: its support check
  /// failed, phone test 3).
  bool localesHang = false;
  List<String> locales = ['en_US:English (US)', 'ar_EG:Arabic (Egypt)'];

  /// Answers to successive `listen` calls: true / false, or a
  /// [PlatformException] to throw.
  final List<Object> listenAnswers = [];
  final calls = <MethodCall>[];

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'initialize':
        return initOk;
      case 'locales':
        if (localesHang) await Completer<void>().future;
        await localesGate?.future;
        return locales;
      case 'listen':
        await listenGate?.future;
        final a = listenAnswers.isEmpty ? true : listenAnswers.removeAt(0);
        if (a is PlatformException) throw a;
        return a;
      default:
        return null;
    }
  }

  List<Map<Object?, Object?>> get listens => [
    for (final c in calls)
      if (c.method == 'listen') c.arguments as Map<Object?, Object?>,
  ];

  Future<void> _send(String method, String arg) async {
    await _messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arg)),
      (_) {},
    );
  }

  Future<void> status(String s) => _send('notifyStatus', s);

  Future<void> words(String w, {required bool last}) =>
      result(w, type: last ? 2 : 0);

  /// A result of [type]: 0 partial, 1 intermediate (a finished phrase in a
  /// session that keeps listening: Android `final_result`), 2 final.
  Future<void> result(String w, {required int type}) => _send(
    'textRecognition',
    jsonEncode({
      'alternates': [
        {'recognizedWords': w, 'confidence': .9},
      ],
      'resultType': type,
    }),
  );

  /// A result with several alternates (words, confidence), best first.
  Future<void> alternates(List<(String, double)> alts, {required int type}) =>
      _send(
        'textRecognition',
        jsonEncode({
          'alternates': [
            for (final (w, c) in alts) {'recognizedWords': w, 'confidence': c},
          ],
          'resultType': type,
        }),
      );

  /// The microphone's sound level (Android RMS dB).
  Future<void> level(double db) async {
    await _messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('soundLevelChange', db),
      ),
      (_) {},
    );
  }

  Future<void> error(String code) =>
      _send('notifyError', jsonEncode({'errorMsg': code, 'permanent': true}));

  void dispose() => _messenger.setMockMethodCallHandler(channel, null);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pickSpeechLocale', () {
    test('Arabic prefers Egyptian, then any Arabic', () {
      expect(
        pickSpeechLocale(['ar_SA', 'ar_EG', 'en_US'], SpokenLanguage.ar),
        'ar_EG',
      );
      expect(pickSpeechLocale(['ar-eg', 'en-US'], SpokenLanguage.ar), 'ar-eg');
      expect(pickSpeechLocale(['ar_SA', 'fr_FR'], SpokenLanguage.ar), 'ar_SA');
      expect(pickSpeechLocale(['ar'], SpokenLanguage.ar), 'ar');
    });

    test("English prefers the phone's English, then US, then any", () {
      final ids = ['en_GB', 'en_US', 'en_IN'];
      expect(
        pickSpeechLocale(ids, SpokenLanguage.en, systemId: 'en_IN'),
        'en_IN',
      );
      expect(
        pickSpeechLocale(ids, SpokenLanguage.en, systemId: 'ar_EG'),
        'en_US',
      );
      expect(pickSpeechLocale(['en_GB'], SpokenLanguage.en), 'en_GB');
    });

    test('no match: null (never another language)', () {
      expect(pickSpeechLocale(['fr_FR', 'arn_CL'], SpokenLanguage.ar), isNull);
      expect(pickSpeechLocale([], SpokenLanguage.en), isNull);
      expect(pickSpeechLocale(['eng_XX'], SpokenLanguage.en), isNull);
    });
  });

  test('error codes', () {
    expect(classifySpeechError('error_no_match'), SpeechError.noSpeech);
    expect(classifySpeechError('error_speech_timeout'), SpeechError.noSpeech);
    expect(
      classifySpeechError('error_language_unavailable'),
      SpeechError.languageMissing,
    );
    expect(
      classifySpeechError('error_language_not_supported'),
      SpeechError.languageMissing,
    );
    expect(
      classifySpeechError('error_assets_not_installed'),
      SpeechError.languageMissing,
    );
    expect(classifySpeechError('error_permission'), SpeechError.permission);
    expect(
      classifySpeechError('error_speech_recognizer_request_not_authorized'),
      SpeechError.permission,
    );
    expect(classifySpeechError('error_network'), SpeechError.other);
  });

  group('PlatformSpeechToText', () {
    late _Phone phone;
    late PlatformSpeechToText s;

    setUp(() {
      phone = _Phone();
      s = PlatformSpeechToText(plugin: stt.SpeechToText.withMethodChannel());
    });

    tearDown(() async {
      await s.cancel();
      phone.dispose();
    });

    test('prepare: ready, language missing', () async {
      expect(await s.prepare(SpokenLanguage.ar), SpeechSupport.ready);
      phone.locales = ['fr_FR:French'];
      final fresh = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
      );
      expect(
        await fresh.prepare(SpokenLanguage.ar),
        SpeechSupport.languageMissing,
      );
    });

    test('phone test 3: the phone never answers the locale list → busy '
        'within the time limit, never stuck preparing', () async {
      await s.cancel();
      s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        prepareTimeout: const Duration(milliseconds: 50),
      );
      phone.localesHang = true;
      final t0 = DateTime.now();
      expect(await s.prepare(SpokenLanguage.en), SpeechSupport.busy);
      expect(
        DateTime.now().difference(t0),
        lessThan(const Duration(seconds: 2)),
      );
      // the phone answers again: the next tap works
      phone.localesHang = false;
      expect(await s.prepare(SpokenLanguage.en), SpeechSupport.ready);
    });

    test(
      'the locale list is asked once per language, not on every tap',
      () async {
        int asked() => phone.calls.where((c) => c.method == 'locales').length;
        expect(await s.prepare(SpokenLanguage.ar), SpeechSupport.ready);
        final once = asked();
        expect(await s.prepare(SpokenLanguage.ar), SpeechSupport.ready);
        expect(await s.prepare(SpokenLanguage.ar), SpeechSupport.ready);
        expect(asked(), once);
        expect(await s.prepare(SpokenLanguage.en), SpeechSupport.ready);
        expect(asked(), greaterThan(once), reason: 'another language');
      },
    );

    test(
      '"language missing" from a listen asks the phone again next time',
      () async {
        int asked() => phone.calls.where((c) => c.method == 'locales').length;
        final got = <SpeechEvent>[];
        s.listen(SpokenLanguage.ar).listen(got.add);
        await _flush();
        await _flush();
        await phone.error('error_language_unavailable');
        await _flush();
        await _flush();
        await phone.error('error_language_unavailable');
        await _flush();
        expect((got.last as SpeechFailed).error, SpeechError.languageMissing);
        final before = asked();
        await s.prepare(SpokenLanguage.ar);
        expect(asked(), greaterThan(before));
      },
    );

    test('prepare: no recognizer', () async {
      phone.initOk = false;
      expect(await s.prepare(SpokenLanguage.en), SpeechSupport.unavailable);
    });

    test('prepare: the plugin is missing (throws)', () async {
      phone.dispose();
      expect(await s.prepare(SpokenLanguage.en), SpeechSupport.unavailable);
    });

    test('listen: on the phone first, in the picked locale; partial, the '
        'release, then the final', () async {
      final got = <SpeechEvent>[];
      final done = Completer<void>();
      s.listen(SpokenLanguage.ar).listen(got.add, onDone: done.complete);
      await _flush();
      await _flush();
      expect(phone.listens.single['onDevice'], isTrue);
      // BCP-47 for Android (the plugin lists `ar_EG`)
      expect(phone.listens.single['localeId'], 'ar-EG');
      // hold to talk: no pause limit (the user ends the listen), a 65 s
      // backstop past Talk's 60 s; dictation (search only with the debug
      // STT_LISTEN_MODE define)
      // ask the recognizer not to end on a pause (it may ignore it)
      expect(phone.listens.single['pauseFor'], 65000);
      expect(phone.listens.single['listenFor'], 65000);
      expect(
        phone.listens.single['listenMode'],
        stt.ListenMode.dictation.index,
      );
      await phone.words('شكرا', last: false);
      // hold to talk: let go, then the recognizer's last words
      await s.stop();
      await phone.words('شكرا جدا', last: true);
      await done.future;
      expect(got[0], isA<SpeechPartial>());
      expect((got.last as SpeechFinal).text, 'شكرا جدا');
    });

    test('an empty final result is "nothing heard"', () async {
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await s.stop();
      await phone.words('  ', last: true);
      await _flush();
      expect((got.single as SpeechFailed).error, SpeechError.noSpeech);
    });

    test('Q-T3: the on-device recognizer lacks the language → once more '
        'with the normal one', () async {
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.ar).listen(got.add);
      await _flush();
      await _flush();
      await phone.error('error_language_unavailable');
      await _flush();
      await _flush();
      expect([for (final l in phone.listens) l['onDevice']], [true, false]);
      await s.stop();
      await phone.words('مية', last: true);
      await _flush();
      expect((got.last as SpeechFinal).text, 'مية');
    });

    test("the failed on-device session's late done doesn't end the "
        'retry', () async {
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.ar).listen(got.add);
      await _flush();
      await _flush();
      await phone.error('error_language_not_supported');
      await _flush();
      await _flush();
      await phone.status('doneNoResult');
      await _flush();
      expect(got, isEmpty, reason: 'the retry is still listening');
      await phone.status('listening');
      await s.stop();
      await phone.words('مية', last: true);
      await _flush();
      expect((got.single as SpeechFinal).text, 'مية');
    });

    test('the normal recognizer lacks it too → language missing', () async {
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.ar).listen(got.add);
      await _flush();
      await _flush();
      await phone.error('error_language_unavailable');
      await _flush();
      await _flush();
      await phone.error('error_language_not_supported');
      await _flush();
      expect((got.single as SpeechFailed).error, SpeechError.languageMissing);
    });

    test('iOS refuses on-device at listen → retried without it', () async {
      phone.listenAnswers.add(PlatformException(code: 'onDeviceError'));
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      for (var i = 0; i < 4; i++) {
        await _flush();
      }
      expect([for (final l in phone.listens) l['onDevice']], [true, false]);
      await s.stop();
      await phone.words('hello', last: true);
      await _flush();
      expect((got.single as SpeechFinal).text, 'hello');
    });

    test('both listens throw → failed', () async {
      phone.listenAnswers.addAll([
        PlatformException(code: 'onDeviceError'),
        PlatformException(code: 'busy'),
      ]);
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      for (var i = 0; i < 6; i++) {
        await _flush();
      }
      expect((got.single as SpeechFailed).error, SpeechError.other);
    });

    test('while the mic is held: permission and other errors (not a session '
        'the phone ended) end the listen', () async {
      for (final (code, want) in [
        ('error_permission', SpeechError.permission),
        ('error_network', SpeechError.other),
        ('error_server', SpeechError.other),
        ('error_audio_error', SpeechError.other),
      ]) {
        final got = <SpeechEvent>[];
        s.listen(SpokenLanguage.en).listen(got.add);
        await _flush();
        await _flush();
        await phone.error(code);
        await _flush();
        expect((got.single as SpeechFailed).error, want, reason: code);
      }
      expect(phone.listens, hasLength(4), reason: 'never listened again');
    });

    test('done with no result while the mic is held: listening goes on; let '
        'go with nothing heard → nothing heard', () async {
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('doneNoResult');
      await _flush();
      expect(got, isEmpty, reason: 'still listening');
      await s.stop();
      await _flush();
      expect((got.single as SpeechFailed).error, SpeechError.noSpeech);
    });

    group('finished phrases, then the phone ends the session with no final '
        'result while the mic is held (Samsung, Google on-device recognizer, '
        '2026-10-12); the release gives the sentence (2026-11-20)', () {
      Future<List<SpeechEvent>> session(Future<void> Function() phone_) async {
        final got = <SpeechEvent>[];
        s.listen(SpokenLanguage.en).listen(got.add);
        await _flush();
        await _flush();
        await phone_();
        await _flush();
        // the mic is still held: listening goes on, nothing ends yet
        expect(got.where((e) => e is! SpeechPartial), isEmpty);
        // let go between two sessions: what was heard is the sentence
        await s.stop();
        await _flush();
        return got;
      }

      test('the phone log: phrase, listening again, the same phrase, '
          'done → the phrase, once', () async {
        final got = await session(() async {
          await phone.status('listening');
          await phone.result('hello', type: 0);
          await phone.result('hello', type: 1);
          await phone.result('hello', type: 1);
          await phone.status('notListening');
          await phone.status('done');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'hello');
        expect(got.whereType<SpeechFailed>(), isEmpty);
      });

      test('phrases one by one are joined', () async {
        final got = await session(() async {
          await phone.result('hello', type: 1);
          await phone.result('thank you', type: 1);
          await phone.status('done');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'hello thank you');
      });

      test('the whole text so far replaces the phrases', () async {
        final got = await session(() async {
          await phone.result('hello', type: 1);
          await phone.result('hello thank you', type: 1);
          await phone.status('done');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'hello thank you');
      });

      test('a no-match error after a phrase still gives the phrase', () async {
        final got = await session(() async {
          await phone.result('شكرا', type: 1);
          await phone.error('error_no_match');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'شكرا');
      });

      test('no phrase: the last partial before the end is the sentence '
          '(user rule)', () async {
        final got = await session(() async {
          await phone.result('ye', type: 0);
          await phone.result('yes', type: 0);
          await phone.error('error_no_match');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'yes');
      });

      test('an empty finished phrase after a partial: the partial', () async {
        final got = await session(() async {
          await phone.result('yes', type: 0);
          await phone.result('', type: 1);
          await phone.status('notListening');
          await phone.status('done');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'yes');
      });

      test('finished phrases win over a later partial', () async {
        final got = await session(() async {
          await phone.result('hello', type: 1);
          await phone.result('hello th', type: 0);
          await phone.error('error_no_match');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'hello');
      });

      test('the phone log of "yes" (2026-10-12, 19:59:35): one empty '
          'finished phrase, no partial, done → nothing heard (the '
          'recognizer returned no text)', () async {
        final got = await session(() async {
          await phone.status('listening');
          await phone.result('', type: 1);
          await phone.status('notListening');
          await phone.status('done');
        });
        expect((got.last as SpeechFailed).error, SpeechError.noSpeech);
        expect(got.whereType<SpeechFinal>(), isEmpty);
      });

      test('a real final result still wins over the phrases', () async {
        final got = await session(() async {
          await phone.result('hello', type: 1);
          await phone.result('hello there', type: 2);
          await phone.status('done');
        });
        expect(got.whereType<SpeechFinal>().single.text, 'hello there');
      });

      test('a new listen starts with no phrases', () async {
        await session(() async {
          await phone.result('hello', type: 1);
          await phone.status('done');
        });
        // nothing heard: Android reports doneNoResult
        final got = await session(() async {
          await phone.status('doneNoResult');
        });
        expect((got.single as SpeechFailed).error, SpeechError.noSpeech);
      });
    });

    test('S7-27: the bias words reach the plugin as contextualPhrases; '
        'none: no key', () async {
      s
          .listen(SpokenLanguage.en, phrases: ['hello', 'thank you'])
          .listen((_) {});
      await _flush();
      await _flush();
      expect(phone.listens.last['contextualPhrases'], ['hello', 'thank you']);
      await s.cancel();
      s.listen(SpokenLanguage.en).listen((_) {});
      await _flush();
      await _flush();
      expect(phone.listens.last.containsKey('contextualPhrases'), isFalse);
    });

    test('the language changes: prepared again', () async {
      s.listen(SpokenLanguage.en).listen((_) {});
      await _flush();
      await _flush();
      await phone.words('hi', last: true);
      await _flush();
      s.listen(SpokenLanguage.ar).listen((_) {});
      await _flush();
      await _flush();
      expect(phone.listens.last['localeId'], 'ar-EG');
    });

    test('a listen with no recognizer fails at once', () async {
      phone.initOk = false;
      final got = <SpeechEvent>[];
      await s.listen(SpokenLanguage.en).forEach(got.add);
      expect((got.single as SpeechFailed).error, SpeechError.other);
    });

    test('a language the phone lacks fails as language missing', () async {
      phone.locales = ['fr_FR:French'];
      final got = <SpeechEvent>[];
      await s.listen(SpokenLanguage.ar).forEach(got.add);
      expect((got.single as SpeechFailed).error, SpeechError.languageMissing);
    });

    test('stop and cancel reach the plugin while listening', () async {
      await s.cancel();
      s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopTail: Duration.zero,
      );
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen((_) {}, onDone: done.complete);
      await _flush();
      await _flush();
      await phone.status('listening');
      await s.stop();
      expect(phone.calls.map((c) => c.method), contains('stop'));
      await phone.status('listening');
      await s.cancel();
      expect(phone.calls.map((c) => c.method), contains('cancel'));
      await done.future;
    });

    test(
      'a listen the platform never starts ends after the watchdog',
      () async {
        expect(
          PlatformSpeechToText(plugin: stt.SpeechToText.withMethodChannel())
              .watchdog,
          const Duration(seconds: 70),
        );
        await s.cancel();
        s = PlatformSpeechToText(
          plugin: stt.SpeechToText.withMethodChannel(),
          watchdog: const Duration(milliseconds: 100),
        );
        phone.listenAnswers.add(false);
        final got = <SpeechEvent>[];
        await s.listen(SpokenLanguage.en).forEach(got.add);
        expect((got.single as SpeechFailed).error, SpeechError.other);
      },
    );
  });

  group('debug word trace (2026-10-26)', () {
    late _Phone phone;
    late List<LogRecord> lines;
    late StreamSubscription<LogRecord> sub;

    setUp(() {
      phone = _Phone();
      lines = [];
      sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'ishara.stt_trace')
          .listen(lines.add);
    });

    tearDown(() async {
      await sub.cancel();
      phone.dispose();
    });

    Map<String, Object?> line(String event) => lines
        .map((r) => (r.object! as LogEvent).toJson())
        .firstWhere((m) => m['event'] == 'trace_$event');

    test('on: locale, on-device, bias, every result with its alternates and '
        'confidences, the end with its source; the plugin log is on', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        trace: SpeechTrace(() => true),
      );
      addTearDown(s.cancel);
      final done = Completer<void>();
      s
          .listen(SpokenLanguage.en, phrases: ['bye', 'i'])
          .listen(null, onDone: done.complete);
      await _flush();
      await _flush();
      expect(
        (phone.calls.firstWhere((c) => c.method == 'initialize').arguments
            as Map)['debugLogging'],
        isTrue,
      );
      await phone.alternates([('boy', .8), ('bye', .4)], type: 0);
      // Android's order: the error, then "notListening" (plugin onError)
      await phone.error('error_no_match');
      await phone.status('notListening');
      await _flush();
      // the mic is still held: a new session, the partial kept
      expect(line('restart'), containsPair('reason', 'error_no_match'));
      await s.stop();
      await done.future;
      final listen = line('listen');
      expect(listen['locale'], 'en_US');
      expect(listen['onDevice'], isTrue);
      expect(listen['bias'], ['bye', 'i']);
      expect(line('result')['alternates'], [
        {'words': 'boy', 'confidence': .8},
        {'words': 'bye', 'confidence': .4},
      ]);
      expect(line('status')['status'], 'notListening');
      expect(line('error')['code'], 'error_no_match');
      final end = line('end');
      // the ended session's last partial was kept as what it heard
      expect(end['source'], 'phrases');
      // the phone's first guess, never a lower one that has a sign
      // (user decision 2026-11-20)
      expect(end['heard'], 'boy');
      expect(end['error'], isNull);
    });

    test('nothing heard: the end says so', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        trace: SpeechTrace(() => true),
      );
      addTearDown(s.cancel);
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(null, onDone: done.complete);
      await _flush();
      await _flush();
      await phone.error('error_no_match');
      await _flush();
      // still held: listening goes on until the release
      await s.stop();
      await done.future;
      expect(line('error')['code'], 'error_no_match');
      expect(line('end'), containsPair('source', 'none'));
      expect(line('end'), containsPair('error', 'noSpeech'));
    });

    test('off (developer mode off): no trace line, no plugin log', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
      );
      addTearDown(s.cancel);
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(null, onDone: done.complete);
      await _flush();
      await _flush();
      await s.stop();
      await phone.words('hello', last: true);
      await done.future;
      expect(lines, isEmpty);
      expect(
        (phone.calls.firstWhere((c) => c.method == 'initialize').arguments
            as Map)['debugLogging'],
        isFalse,
      );
    });
  });

  group('hold to talk: stop and level (2026-10-26)', () {
    late _Phone phone;

    setUp(() => phone = _Phone());
    tearDown(() => phone.dispose());

    test('stop asks the plugin even before it reports "listening"', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopTail: Duration.zero,
      );
      addTearDown(s.cancel);
      s.listen(SpokenLanguage.en).listen(null);
      await _flush();
      await _flush();
      await s.stop();
      expect(phone.calls.map((c) => c.method), contains('stop'));
    });

    test('the phone never answers a stop: after the grace, the last words '
        'heard are the sentence', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopGrace: const Duration(milliseconds: 50),
        stopTail: Duration.zero,
      );
      addTearDown(s.cancel);
      final got = <SpeechEvent>[];
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(got.add, onDone: done.complete);
      await _flush();
      await _flush();
      await phone.result('bye', type: 0);
      await s.stop();
      await done.future;
      expect((got.last as SpeechFinal).text, 'bye');
      // ...and the phone's mic is closed
      expect(phone.calls.map((c) => c.method), contains('cancel'));
    });

    test('...and with nothing heard: "nothing heard"', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopGrace: const Duration(milliseconds: 50),
        stopTail: Duration.zero,
      );
      addTearDown(s.cancel);
      final got = <SpeechEvent>[];
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(got.add, onDone: done.complete);
      await _flush();
      await _flush();
      await s.stop();
      await done.future;
      expect((got.single as SpeechFailed).error, SpeechError.noSpeech);
    });

    test('a final result after the stop wins; the grace timer then does '
        'nothing', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopGrace: const Duration(milliseconds: 50),
      );
      addTearDown(s.cancel);
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.result('by', type: 0);
      await s.stop();
      await phone.words('bye', last: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(got.whereType<SpeechFinal>().single.text, 'bye');
    });

    test('sound levels come as 0..1 while listening', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
      );
      addTearDown(s.cancel);
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.level(4);
      await _flush();
      expect(got.whereType<SpeechLevel>().single.level, .5);
    });

    test('levelFromDb: about -2 (silence) to 10 (loud), clamped', () {
      expect(levelFromDb(-2), 0);
      expect(levelFromDb(-10), 0);
      expect(levelFromDb(10), 1);
      expect(levelFromDb(22), 1);
      expect(levelFromDb(4), .5);
    });

    test('cancelled while getting ready: the mic is never opened', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
      );
      phone.localesGate = Completer<void>();
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(null, onDone: done.complete);
      await _flush();
      await s.cancel();
      phone.localesGate!.complete();
      await done.future;
      for (var i = 0; i < 5; i++) {
        await _flush();
      }
      expect(phone.listens, isEmpty);
    });

    test('cancelled while the plugin is starting: the plugin is told to '
        'cancel once it has started', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
      );
      await s.prepare(SpokenLanguage.en);
      phone.listenGate = Completer<void>();
      s.listen(SpokenLanguage.en).listen(null);
      await _flush();
      await s.cancel();
      final before = phone.calls.where((c) => c.method == 'cancel').length;
      phone.listenGate!.complete();
      for (var i = 0; i < 5; i++) {
        await _flush();
      }
      expect(
        phone.calls.where((c) => c.method == 'cancel').length,
        greaterThan(before),
      );
    });

    test('let go while the plugin is starting: the plugin is told to stop '
        'once it has started', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
      );
      addTearDown(s.cancel);
      await s.prepare(SpokenLanguage.en);
      phone.listenGate = Completer<void>();
      s.listen(SpokenLanguage.en).listen(null);
      await _flush();
      await s.stop();
      final before = phone.calls.where((c) => c.method == 'stop').length;
      phone.listenGate!.complete();
      for (var i = 0; i < 5; i++) {
        await _flush();
      }
      expect(
        phone.calls.where((c) => c.method == 'stop').length,
        greaterThan(before),
      );
    });

    test('phone run 2 (2026-10-27): after the stop the plugin reports '
        '"notListening" and "done" at once, and the recognizer\'s words '
        'come ~0.4 s later: they are the sentence', () async {
      // the plugin's answer to the stop itself, so no moment after the
      // release here (stopTail: see the 2026-11-21 group)
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopTail: Duration.zero,
      );
      addTearDown(s.cancel);
      final got = <SpeechEvent>[];
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(got.add, onDone: done.complete);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.result('', type: 1);
      await s.stop();
      await phone.status('notListening');
      await phone.status('doneNoResult');
      await _flush();
      expect(got.whereType<SpeechFailed>(), isEmpty, reason: 'still waiting');
      await phone.words('look at me', last: true);
      await done.future;
      expect((got.last as SpeechFinal).text, 'look at me');
    });

    test('...a plain "done" after the stop is ignored too', () async {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopTail: Duration.zero,
      );
      addTearDown(s.cancel);
      final got = <SpeechEvent>[];
      final done = Completer<void>();
      s.listen(SpokenLanguage.en).listen(got.add, onDone: done.complete);
      await _flush();
      await _flush();
      await phone.status('listening');
      await s.stop();
      await phone.status('done');
      await _flush();
      expect(got.whereType<SpeechFailed>(), isEmpty);
      await phone.words('bye', last: true);
      await done.future;
      expect((got.last as SpeechFinal).text, 'bye');
    });
  });

  group('hold to talk: the phone ends its session while the mic is held '
      '(2026-11-20)', () {
    late _Phone phone;

    setUp(() => phone = _Phone());
    tearDown(() => phone.dispose());

    PlatformSpeechToText make({
      Duration restartDelay = Duration.zero,
      int maxRestarts = 20,
    }) {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        restartDelay: restartDelay,
        maxRestarts: maxRestarts,
        stopGrace: const Duration(seconds: 5),
      );
      addTearDown(s.cancel);
      return s;
    }

    /// Lets the short timers and the plugin's answers run.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    List<String> methods() => [for (final c in phone.calls) c.method];
    int count(String method) => methods().where((m) => m == method).length;
    Iterable<SpeechEvent> ends(List<SpeechEvent> got) =>
        got.where((e) => e is SpeechFinal || e is SpeechFailed);

    test('no match: a new session with the same recognizer and bias, the '
        'words kept; the release gives all of them', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s
          .listen(SpokenLanguage.en, phrases: ['hello', 'thank you'])
          .listen(got.add);
      await _flush();
      await _flush();
      await phone.result('hello', type: 1);
      await phone.error('error_no_match');
      await settle();
      expect(ends(got), isEmpty, reason: 'still listening');
      expect(phone.listens, hasLength(2));
      expect(phone.listens.last['onDevice'], isTrue);
      expect(phone.listens.last['contextualPhrases'], ['hello', 'thank you']);
      await phone.status('listening');
      await phone.result('thank you', type: 1);
      await s.stop();
      await phone.words('thank you', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello thank you');
    });

    test("Q-T3 (user decision 2026-11-20): the phone's own recognizer ending "
        'a session before any word (silence, busy, a client error) stays in '
        'use', () async {
      for (final code in [
        'error_no_match',
        'error_speech_timeout',
        'error_busy',
        'error_client',
      ]) {
        final s = make();
        final got = <SpeechEvent>[];
        final before = phone.listens.length;
        s.listen(SpokenLanguage.en).listen(got.add);
        await _flush();
        await _flush();
        await phone.error(code);
        await settle();
        expect(phone.listens.length, before + 2, reason: code);
        expect(phone.listens.last['onDevice'], isTrue, reason: code);
        expect(ends(got), isEmpty, reason: code);
        await s.cancel();
      }
    });

    test('a final result while held: the ended session is cancelled before '
        'the next listen (Android keeps it "listening" after its final '
        'result and would refuse a new one)', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.words('hello', last: true);
      await settle();
      expect(ends(got), isEmpty, reason: 'still listening');
      final m = methods();
      expect(count('listen'), 2);
      expect(m.indexOf('cancel'), isNonNegative);
      expect(m.indexOf('cancel'), lessThan(m.lastIndexOf('listen')));
      await phone.status('listening');
      await phone.words('thank you', last: false);
      await s.stop();
      await phone.words('thank you', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello thank you');
    });

    test('a final result replaces the phrases of its own session (no word '
        'twice); the earlier sessions stay', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.result('come', type: 1);
      await phone.error('error_no_match');
      await settle();
      await phone.status('listening');
      await phone.result('hello', type: 1);
      await s.stop();
      await phone.words('Hello there', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'come Hello there');
    });

    test("only the phone's first guess is heard, never a lower guess that "
        'has a sign (user decision 2026-11-20)', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en, phrases: ['bye']).listen(got.add);
      await _flush();
      await _flush();
      await phone.alternates([('boy', .8), ('bye', .4)], type: 1);
      await s.stop();
      await phone.alternates([('boy', .8), ('bye', .4)], type: 2);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'boy');
    });

    test('let go between two sessions: the sentence at once, no new session '
        'and no grace to wait for', () async {
      final s = make(restartDelay: const Duration(seconds: 5));
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.result('hello', type: 1);
      await phone.status('done');
      await _flush();
      expect(ends(got), isEmpty, reason: 'waiting for the next session');
      await s.stop();
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello');
      expect(phone.listens, hasLength(1));
      expect(count('stop'), 0, reason: 'no session to stop');
    });

    test('let go while the next session is starting: it is cancelled and '
        'the words before it are the sentence at once', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.result('hello', type: 1);
      phone.listenGate = Completer<void>();
      await phone.error('error_no_match');
      await settle();
      expect(phone.listens, hasLength(2), reason: 'the next one is starting');
      await s.stop();
      final cancels = count('cancel');
      phone.listenGate!.complete();
      await settle();
      expect(got.whereType<SpeechFinal>().single.text, 'hello');
      expect(count('cancel'), greaterThan(cancels));
    });

    test('a next session that cannot start is tried again on the same '
        'recognizer', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.result('hello', type: 1);
      phone.listenAnswers.add(PlatformException(code: 'busy'));
      await phone.error('error_no_match');
      await settle();
      await settle();
      expect(phone.listens, hasLength(3), reason: 'failed once, then started');
      expect(phone.listens.last['onDevice'], isTrue);
      expect(ends(got), isEmpty);
      await phone.status('listening');
      await s.stop();
      await phone.words('please', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello please');
    });

    test(
      'another error while held ends the listen with what was heard',
      () async {
        final s = make();
        final got = <SpeechEvent>[];
        s.listen(SpokenLanguage.en).listen(got.add);
        await _flush();
        await _flush();
        await phone.result('hello', type: 1);
        await phone.error('error_network');
        await _flush();
        expect(got.whereType<SpeechFinal>().single.text, 'hello');
        expect(phone.listens, hasLength(1));
      },
    );

    test('at most maxRestarts new sessions, then what was heard is the '
        'sentence', () async {
      final s = make(maxRestarts: 2);
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.result('hello', type: 1);
      for (var i = 0; i < 3; i++) {
        if (i > 0) await phone.status('listening');
        await phone.error('error_no_match');
        await settle();
      }
      expect(phone.listens, hasLength(3), reason: 'the first and 2 more');
      expect(got.whereType<SpeechFinal>().single.text, 'hello');
    });

    test('the phone ends its session after a partial (an empty final: the '
        'plugin sends only "notListening" and holds "done" back): a new '
        'session at once, the partial kept (ISHARA.md item 4)', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.result('hello', type: 0);
      await phone.status('notListening');
      await phone.status('done');
      await settle();
      expect(ends(got), isEmpty, reason: 'still listening');
      expect(phone.listens, hasLength(2));
      await phone.status('listening');
      await s.stop();
      await phone.words('thank you', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello thank you');
    });

    test('our own cancel before a new session ("notListening", "done") does '
        'not start another one', () async {
      final s = make(restartDelay: const Duration(milliseconds: 30));
      s.listen(SpokenLanguage.en).listen(null);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.error('error_no_match');
      // what the plugin says for the cancel of the ended session
      await phone.status('notListening');
      await phone.status('doneNoResult');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(phone.listens, hasLength(2), reason: 'one new session only');
    });

    test('a late error of the cancelled session (before the new one says '
        '"listening") does not end the new session', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.words('hello', last: true);
      await settle();
      expect(phone.listens, hasLength(2));
      await phone.error('error_client');
      await settle();
      expect(phone.listens, hasLength(2), reason: 'no restart for it');
      await phone.status('listening');
      await s.stop();
      await phone.words('thank you', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello thank you');
    });

    test(
      'cancelled while waiting for the next session: it never starts',
      () async {
        final s = make(restartDelay: const Duration(milliseconds: 30));
        s.listen(SpokenLanguage.en).listen(null);
        await _flush();
        await _flush();
        await phone.error('error_no_match');
        await s.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(phone.listens, hasLength(1));
      },
    );

    test('a new listen while waiting for the next session: the old one never '
        'starts', () async {
      final s = make(restartDelay: const Duration(milliseconds: 30));
      s.listen(SpokenLanguage.en).listen(null);
      await _flush();
      await _flush();
      await phone.error('error_no_match');
      s.listen(SpokenLanguage.en).listen(null);
      await _flush();
      await _flush();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(phone.listens, hasLength(2));
    });
  });

  group('hold to talk: a moment more after the release (user decision '
      '2026-11-21, TV-16)', () {
    late _Phone phone;

    setUp(() => phone = _Phone());
    tearDown(() => phone.dispose());

    PlatformSpeechToText make({
      Duration stopTail = const Duration(milliseconds: 60),
    }) {
      final s = PlatformSpeechToText(
        plugin: stt.SpeechToText.withMethodChannel(),
        stopTail: stopTail,
        stopGrace: const Duration(seconds: 5),
      );
      addTearDown(s.cancel);
      return s;
    }

    int stops() => phone.calls.where((c) => c.method == 'stop').length;

    test('800 ms by default', () {
      expect(
        PlatformSpeechToText(plugin: stt.SpeechToText.withMethodChannel())
            .stopTail,
        const Duration(milliseconds: 800),
      );
    });

    test('the recognizer keeps listening after the release, the words of '
        'that moment count, then the plugin is told to stop', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.result('hello', type: 0);
      await s.stop();
      expect(stops(), 0, reason: 'still listening for the last word');
      await phone.result('hello there', type: 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stops(), 1);
      await phone.words('hello there', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'hello there');
    });

    test('a final result in that moment is the sentence at once', () async {
      final s = make(stopTail: const Duration(seconds: 5));
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('listening');
      await s.stop();
      await phone.words('thank you', last: true);
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'thank you');
      expect(stops(), 0, reason: 'nothing left to stop');
    });

    test('the session ends by itself in that moment with no final result: '
        'what was heard, at once', () async {
      final s = make(stopTail: const Duration(seconds: 5));
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.result('please', type: 0);
      await s.stop();
      await phone.status('notListening');
      await _flush();
      expect(got.whereType<SpeechFinal>().single.text, 'please');
    });

    test('cancelled in that moment: nothing heard is sent, and the plugin '
        'is never told to stop', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('listening');
      await phone.result('hello', type: 0);
      await s.stop();
      await s.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(got.whereType<SpeechFinal>(), isEmpty);
      expect(stops(), 0);
    });

    test('a final result while the mic is held also counts as words heard '
        '(Talk\'s silence limit)', () async {
      final s = make();
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.words('hello', last: true);
      await _flush();
      expect(
        got.whereType<SpeechPartial>().map((p) => p.text),
        contains('hello'),
      );
      expect(got.whereType<SpeechFinal>(), isEmpty, reason: 'still held');
    });
  });
}
