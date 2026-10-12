import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
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
        return locales;
      case 'listen':
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

    test('prepare: ready, language missing, unavailable', () async {
      expect(await s.prepare(SpokenLanguage.ar), SpeechSupport.ready);
      phone.locales = ['fr_FR:French'];
      expect(await s.prepare(SpokenLanguage.ar), SpeechSupport.languageMissing);
    });

    test('prepare: no recognizer', () async {
      phone.initOk = false;
      expect(await s.prepare(SpokenLanguage.en), SpeechSupport.unavailable);
    });

    test('prepare: the plugin is missing (throws)', () async {
      phone.dispose();
      expect(await s.prepare(SpokenLanguage.en), SpeechSupport.unavailable);
    });

    test('listen: on the phone first, in the picked locale; partial then '
        'final', () async {
      final got = <SpeechEvent>[];
      final done = Completer<void>();
      s.listen(SpokenLanguage.ar).listen(got.add, onDone: done.complete);
      await _flush();
      await _flush();
      expect(phone.listens.single['onDevice'], isTrue);
      // BCP-47 for Android (the plugin lists `ar_EG`)
      expect(phone.listens.single['localeId'], 'ar-EG');
      expect(phone.listens.single['pauseFor'], 3000);
      expect(phone.listens.single['listenFor'], 30000);
      await phone.words('شكرا', last: false);
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

    test('no match, permission, other errors', () async {
      for (final (code, want) in [
        ('error_no_match', SpeechError.noSpeech),
        ('error_permission', SpeechError.permission),
        ('error_network', SpeechError.other),
      ]) {
        final got = <SpeechEvent>[];
        s.listen(SpokenLanguage.en).listen(got.add);
        await _flush();
        await _flush();
        await phone.error(code);
        await _flush();
        expect((got.single as SpeechFailed).error, want, reason: code);
      }
    });

    test('done with no result → nothing heard', () async {
      final got = <SpeechEvent>[];
      s.listen(SpokenLanguage.en).listen(got.add);
      await _flush();
      await _flush();
      await phone.status('doneNoResult');
      await _flush();
      expect((got.single as SpeechFailed).error, SpeechError.noSpeech);
    });

    group('finished phrases, then the session ends with no final result '
        '(Samsung, Google on-device recognizer, 2026-10-12)', () {
      Future<List<SpeechEvent>> session(Future<void> Function() phone_) async {
        final got = <SpeechEvent>[];
        s.listen(SpokenLanguage.en).listen(got.add);
        await _flush();
        await _flush();
        await phone_();
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
          const Duration(seconds: 35),
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
}
