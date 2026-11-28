import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/speech/moonshine_speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:logging/logging.dart';

import '../support/fake_speech.dart';

/// Arabic on the phone with EgypTalk (DECISIONS TV-24): the same engine
/// class as Moonshine (moonshine_speech_to_text_test.dart covers it in
/// full), on its own channel and language.
final _channel = MethodChannel(OnDeviceModel.egyptalk.methodChannel);

/// The native side: answers calls and sends events.
class _FakeNative {
  new() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  final calls = <String>[];
  final notices = <String>[];
  final events = StreamController<Object?>.broadcast();
  Map<String, Object?> prepareAnswer = {
    'status': 'ready',
    'cached': false,
    'copy': 'none',
    'verifyMs': 300,
    'loadMs': 900,
    'pssBeforeKb': 100,
    'pssAfterKb': 300,
    'nativeHeapKb': 200,
  };
  int lastSession = -1;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    if (call.arguments case {'session': final int id}) lastSession = id;
    switch (call.method) {
      case 'prepare':
        return prepareAnswer;
      case 'memory':
        return {'pssKb': 310, 'nativeHeapKb': 210};
      case 'debugNotice':
        notices.add((call.arguments as Map)['text'] as String);
        return null;
      default:
        return null;
    }
  }

  void send(String type, [Map<String, Object?> fields = const {}]) =>
      events.add({'type': type, 'session': lastSession, ...fields});

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    unawaited(events.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNative native;
  late OnDeviceSpeechToText stt;

  OnDeviceSpeechToText make({SpeechToText? fallback}) => OnDeviceSpeechToText(
    model: OnDeviceModel.egyptalk,
    methods: _channel,
    events: native.events.stream,
    fallback: fallback,
    stopTail: const Duration(milliseconds: 30),
    finalTimeout: const Duration(seconds: 5),
  );

  Future<(List<SpeechEvent>, Future<void>)> listen() async {
    await stt.prepare(SpokenLanguage.ar);
    final got = <SpeechEvent>[];
    final done = Completer<void>();
    stt.listen(SpokenLanguage.ar).listen(got.add, onDone: done.complete);
    await pumpEventQueue();
    return (got, done.future);
  }

  setUp(() {
    native = _FakeNative();
    stt = make();
  });

  tearDown(() async {
    await stt.dispose();
    native.dispose();
  });

  group('engine choice (TV-24)', () {
    test('Android: EgypTalk with the Google fallback, also in release', () {
      expect(arabicEngine(debug: false), ArabicEngine.egyptalk);
      expect(arabicEngine(), ArabicEngine.egyptalk);
      expect(
        arabicEngine(debug: false, define: 'google'),
        ArabicEngine.egyptalk,
        reason: 'release builds ignore STT_ENGINE_AR',
      );
    });

    test('debug builds can force an engine', () {
      expect(arabicEngine(define: 'google'), ArabicEngine.google);
      expect(arabicEngine(define: 'egyptalk'), ArabicEngine.egyptalkOnly);
    });

    test('other platforms keep Google', () {
      expect(
        arabicEngine(debug: false, platform: TargetPlatform.iOS),
        ArabicEngine.google,
      );
    });

    test('Arabic on EgypTalk falls back to Google; English is separate', () {
      final google = PlatformSpeechToText();
      final routed = speechEngine(
        google,
        google.trace,
        english: EnglishEngine.google,
        arabic: ArabicEngine.egyptalk,
      );
      expect(routed, isA<OnDeviceRouter>());
      final router = routed as OnDeviceRouter;
      expect(router.english, isNull);
      expect(router.arabic!.model, same(OnDeviceModel.egyptalk));
      expect(router.arabic!.fallback, same(google));

      final only = speechEngine(
        google,
        google.trace,
        english: EnglishEngine.moonshine,
        arabic: ArabicEngine.egyptalkOnly,
      ) as OnDeviceRouter;
      expect(only.arabic!.fallback, isNull);
      expect(only.english!.model, same(OnDeviceModel.moonshine));
    });
  });

  group('router', () {
    test('Arabic goes to EgypTalk; English with no engine to Google', () async {
      final google = FakeSpeechToText(untilStop: true);
      final router = OnDeviceRouter(null, google, arabic: stt);

      await router.prepare(SpokenLanguage.en);
      router.listen(SpokenLanguage.en).listen((_) {});
      await pumpEventQueue();
      expect(native.calls, isEmpty);
      expect(google.calls, contains('listen en'));

      await router.prepare(SpokenLanguage.ar);
      router.listen(SpokenLanguage.ar).listen((_) {});
      await pumpEventQueue();
      expect(native.calls, containsAll(['prepare', 'start']));
      expect(google.calls, isNot(contains('listen ar')));
      await router.cancel();
      expect(native.calls, contains('cancel'));
    });
  });

  group('preload and prepare', () {
    test('Talk in Arabic loads the model in the background, no mic', () async {
      await stt.preload(SpokenLanguage.ar);
      expect(native.calls, ['prepare']);
    });

    test('English never loads EgypTalk', () async {
      await stt.preload(SpokenLanguage.en);
      expect(native.calls, isEmpty);
      expect(
        await stt.prepare(SpokenLanguage.en),
        SpeechSupport.languageMissing,
      );
      expect(native.calls, isEmpty);
    });
  });

  group('fallback to Google (TV-24)', () {
    late FakeSpeechToText google;

    setUp(() {
      google = FakeSpeechToText(untilStop: true, heard: ['شكراً']);
      stt = make(fallback: google);
    });

    // crashed: a load that ended the app before (sherpa-onnx exits)
    for (final status in ['missing', 'corrupt', 'failed', 'crashed']) {
      test('model $status: the listen goes to Google', () async {
        native.prepareAnswer = {'status': status};
        expect(await stt.prepare(SpokenLanguage.ar), SpeechSupport.ready);
        expect(google.calls, ['prepare ar']);
        final got = <SpeechEvent>[];
        stt.listen(SpokenLanguage.ar).listen(got.add);
        await pumpEventQueue();
        await stt.stop();
        await pumpEventQueue();
        expect(native.calls, isNot(contains('start')));
        expect(google.calls, ['prepare ar', 'listen ar', 'stop']);
        expect((got.last as SpeechFinal).text, 'شكراً');
      });
    }

    test('debug notice once per reason, saying Arabic is on Google', () async {
      native.prepareAnswer = {'status': 'missing'};
      await stt.prepare(SpokenLanguage.ar);
      await stt.prepare(SpokenLanguage.ar);
      await pumpEventQueue();
      expect(native.notices, [
        'EgypTalk not used (missing): Arabic is on Google.',
      ]);
    });

    test('a start that fails before the mic records goes to Google', () async {
      final got = <SpeechEvent>[];
      await stt.prepare(SpokenLanguage.ar);
      stt.listen(SpokenLanguage.ar).listen(got.add);
      await pumpEventQueue();
      native.send('error', {'code': 'model_not_loaded'});
      await pumpEventQueue();
      expect(google.calls, ['prepare ar', 'listen ar']);
      await stt.stop();
      await pumpEventQueue();
      expect((got.last as SpeechFinal).text, 'شكراً');
    });

    test('a failure after the mic recorded never switches', () async {
      final got = <SpeechEvent>[];
      await stt.prepare(SpokenLanguage.ar);
      stt.listen(SpokenLanguage.ar).listen(got.add);
      await pumpEventQueue();
      native
        ..send('level', {'level': 0.4})
        ..send('error', {'code': 'decode'});
      await pumpEventQueue();
      expect(google.calls, isNot(contains('listen ar')));
      expect((got.last as SpeechFailed).error, SpeechError.other);
    });
  });

  group('listen (TV-17: windowed partials, never the sentence)', () {
    test('window partials pass for the silence limit; the sentence is the '
        'final of the whole recording', () async {
      final (got, done) = await listen();
      native
        ..send('level', {'level': 0.4})
        ..send('partial', {'text': 'اتصل'});
      await pumpEventQueue();
      await stt.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      native.send('final', {
        'text': 'اتصل بالدكتور',
        'decodeMs': 180,
        'windows': 4,
        'windowsSkipped': 1,
        'windowMsMedian': 210,
        'windowMsMax': 340,
      });
      await done;
      expect((got[1] as SpeechPartial).text, 'اتصل');
      expect((got.last as SpeechFinal).text, 'اتصل بالدكتور');
      expect(got.whereType<SpeechFinal>(), hasLength(1));
    });

    test('no final text is noSpeech, even after a window partial', () async {
      final (got, done) = await listen();
      native
        ..send('level', {'level': 0.4})
        ..send('partial', {'text': 'أهلاً'});
      await pumpEventQueue();
      await stt.stop();
      native.send('final', {'text': ''});
      await done;
      expect((got.last as SpeechFailed).error, SpeechError.noSpeech);
    });

    test('TV-16: the mic stays open for the tail after a release', () async {
      final (_, done) = await listen();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await stt.stop();
      await pumpEventQueue();
      expect(native.calls, isNot(contains('stop')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(native.calls, contains('stop'));
      native.send('final', {'text': 'مية'});
      await done;
    });

    test('the text is passed on unchanged (no aliases, sign rule 7)', () async {
      final (got, done) = await listen();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await stt.stop();
      native.send('final', {'text': 'دعانه'});
      await done;
      expect((got.last as SpeechFinal).text, 'دعانه');
    });
  });

  group('TV-17 on the phone: word_to_stop_ms (phone run 2026-11-27)', () {
    late List<Map<String, Object?>> finals;
    late StreamSubscription<LogRecord> sub;

    setUp(() {
      finals = [];
      sub = Logger.root.onRecord.listen((r) {
        final e = r.object;
        if (e is LogEvent && e.event == 'egyptalk_final') {
          finals.add(e.toJson());
        }
      });
    });

    tearDown(() => sub.cancel());

    Future<void> listenAndStop({required bool bySilence}) async {
      final (_, done) = await listen();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await stt.stop(bySilence: bySilence);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // noise decoded as the same text went on to 6000 ms; the word was
      // heard (the last partial) at 1000 ms
      native.send('final', {
        'text': 'مية',
        'decodeMs': 300,
        'windows': 6,
        'windowsSkipped': 0,
        'windowMsMedian': 90,
        'windowMsMax': 170,
        'audioMs': 6900,
        'lastWordAudioMs': 6000,
        'lastHeardAudioMs': 1000,
      });
      await done;
      await pumpEventQueue();
    }

    test('after a silence stop: from the last word heard, not the last '
        'non-empty window', () async {
      await listenAndStop(bySilence: true);
      expect(finals.single['stop'], 'silence');
      // 6900 - the 30 ms tail of this test's engine - 1000
      expect(finals.single['word_to_stop_ms'], 5870);
      expect(finals.single['last_word_audio_ms'], 6000);
    });

    test('after a release: not logged (it means nothing there)', () async {
      await listenAndStop(bySilence: false);
      expect(finals.single['stop'], 'release');
      expect(finals.single.containsKey('word_to_stop_ms'), isFalse);
    });

    test('the router passes a silence stop on', () async {
      await stt.dispose();
      stt = make();
      final router = OnDeviceRouter(null, FakeSpeechToText(), arabic: stt);
      await router.prepare(SpokenLanguage.ar);
      final done = Completer<void>();
      router.listen(SpokenLanguage.ar).listen(null, onDone: done.complete);
      await pumpEventQueue();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await router.stop(bySilence: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      native.send('final', {
        'text': 'مية',
        'windows': 1,
        'audioMs': 7000,
        'lastHeardAudioMs': 1000,
      });
      await done.future;
      await pumpEventQueue();
      expect(finals.single['word_to_stop_ms'], 5970);
    });
  });

  group('final time limit: 10 s + 0.5 x the recording (user 2026-11-27)', () {
    test('only EgypTalk grows it (one decode of the whole recording)', () {
      expect(OnDeviceModel.egyptalk.finalTimeoutPerRecorded, 0.5);
      expect(OnDeviceModel.moonshine.finalTimeoutPerRecorded, 0);
      expect(
        OnDeviceSpeechToText(model: OnDeviceModel.egyptalk).finalTimeout,
        const Duration(seconds: 10),
      );
    });

    OnDeviceSpeechToText short() => OnDeviceSpeechToText(
      model: OnDeviceModel.egyptalk,
      methods: _channel,
      events: native.events.stream,
      stopTail: Duration.zero,
      finalTimeout: const Duration(milliseconds: 30),
    );

    test('a final later than the base limit still counts after a long '
        'recording', () async {
      await stt.dispose();
      stt = short();
      final (got, done) = await listen();
      native.send('level', {'level': 0.4});
      // 400 ms recorded: the limit is 30 + 200 ms
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await stt.stop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(got.whereType<SpeechFailed>(), isEmpty);
      native.send('final', {'text': 'مية'});
      await done;
      expect((got.last as SpeechFinal).text, 'مية');
    });

    test(
      'a final that never comes still fails, after the grown limit',
      () async {
        await stt.dispose();
        stt = short();
        final (got, done) = await listen();
        native.send('level', {'level': 0.4});
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await stt.stop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(got.whereType<SpeechFailed>(), isEmpty, reason: 'not at 30 ms');
        await done;
        expect((got.last as SpeechFailed).error, SpeechError.other);
        expect(native.calls, contains('cancel'));
      },
    );
  });
}
