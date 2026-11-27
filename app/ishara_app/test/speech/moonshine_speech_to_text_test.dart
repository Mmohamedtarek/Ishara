import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/speech/moonshine_speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';

import '../support/fake_speech.dart';

final _channel = MethodChannel(OnDeviceModel.moonshine.methodChannel);

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
    'copy': 'copied',
    'copyMs': 400,
    'verifyMs': 600,
    'loadMs': 900,
    'pssBeforeKb': 100,
    'pssAfterKb': 300,
    'nativeHeapKb': 200,
  };

  /// Holds the native prepare until completed (the model loading).
  Completer<void>? prepareGate;
  bool startFails = false;
  int lastSession = -1;

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    if (call.arguments case {'session': final int id}) lastSession = id;
    switch (call.method) {
      case 'prepare':
        await prepareGate?.future;
        return prepareAnswer;
      case 'start':
        if (startFails) throw PlatformException(code: 'mic');
        return null;
      case 'memory':
        return {'pssKb': 310, 'nativeHeapKb': 210};
      case 'debugNotice':
        notices.add((call.arguments as Map)['text'] as String);
        return null;
      default:
        return null;
    }
  }

  void send(
    String type, [
    Map<String, Object?> fields = const {},
    int? session,
  ]) =>
      events.add({'type': type, 'session': session ?? lastSession, ...fields});

  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    unawaited(events.close());
  }
}

/// Google, still closing its session until [gate] completes.
class _SlowCancelSpeech extends FakeSpeechToText {
  new(this.gate) : super(untilStop: true);

  final Completer<void> gate;

  @override
  Future<void> cancel() async {
    await gate.future;
    await super.cancel();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeNative native;
  late OnDeviceSpeechToText stt;

  OnDeviceSpeechToText make({
    SpeechToText? fallback,
    Duration tail = const Duration(milliseconds: 30),
    Duration finalTimeout = const Duration(seconds: 5),
    Duration prepareTimeout = const Duration(seconds: 30),
    Duration watchdog = const Duration(seconds: 70),
  }) => OnDeviceSpeechToText(
    methods: _channel,
    events: native.events.stream,
    fallback: fallback,
    stopTail: tail,
    finalTimeout: finalTimeout,
    prepareTimeout: prepareTimeout,
    watchdog: watchdog,
  );

  /// Starts a listen and collects what it reports.
  Future<(List<SpeechEvent>, Future<void>)> listen() async {
    await stt.prepare(SpokenLanguage.en);
    final got = <SpeechEvent>[];
    final done = Completer<void>();
    stt.listen(SpokenLanguage.en).listen(got.add, onDone: done.complete);
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

  group('engine choice (TV-21)', () {
    test('Android: Moonshine with the Google fallback, also in release', () {
      expect(englishEngine(debug: false), EnglishEngine.moonshine);
      expect(englishEngine(), EnglishEngine.moonshine);
      expect(
        englishEngine(debug: false, define: 'google'),
        EnglishEngine.moonshine,
        reason: 'release builds ignore STT_ENGINE',
      );
    });

    test('debug builds can force an engine', () {
      expect(englishEngine(define: 'google'), EnglishEngine.google);
      expect(englishEngine(define: 'moonshine'), EnglishEngine.moonshineOnly);
    });

    test('other platforms keep Google', () {
      expect(
        englishEngine(debug: false, platform: TargetPlatform.iOS),
        EnglishEngine.google,
      );
    });

    test('Google alone is the same object; Moonshine routes', () {
      final google = PlatformSpeechToText();
      expect(
        speechEngine(
          google,
          google.trace,
          english: EnglishEngine.google,
          arabic: ArabicEngine.google,
        ),
        same(google),
      );
      final routed = speechEngine(
        google,
        google.trace,
        english: EnglishEngine.moonshine,
      );
      expect(routed, isA<OnDeviceRouter>());
      expect((routed as OnDeviceRouter).english!.fallback, same(google));
      final only = speechEngine(
        google,
        google.trace,
        english: EnglishEngine.moonshineOnly,
      );
      expect((only as OnDeviceRouter).english!.fallback, isNull);
    });
  });

  group('router', () {
    test('English goes to Moonshine, Arabic to Google', () async {
      final google = FakeSpeechToText(untilStop: true);
      final router = OnDeviceRouter(stt, google);

      await router.preload(SpokenLanguage.ar);
      await router.prepare(SpokenLanguage.ar);
      expect(native.calls, isEmpty);
      router.listen(SpokenLanguage.ar).listen((_) {});
      await pumpEventQueue();
      expect(native.calls, isEmpty);
      await router.cancel();
      expect(google.calls, contains('cancel'));

      await router.prepare(SpokenLanguage.en);
      expect(native.calls, ['prepare']);
      router.listen(SpokenLanguage.en).listen((_) {});
      await pumpEventQueue();
      expect(native.calls, contains('start'));
      await router.cancel();
      expect(native.calls, contains('cancel'));
    });

    test('a switch starts the new engine after the old one let go', () async {
      final gate = Completer<void>();
      final google = _SlowCancelSpeech(gate);
      final router = OnDeviceRouter(stt, google);
      await stt.prepare(SpokenLanguage.en);
      router.listen(SpokenLanguage.ar).listen((_) {});
      await pumpEventQueue();

      router.listen(SpokenLanguage.en).listen((_) {});
      await pumpEventQueue();
      expect(native.calls, isNot(contains('start')));

      gate.complete();
      await pumpEventQueue();
      expect(native.calls, contains('start'));
      await router.cancel();
    });

    test('a cancel during a switch never opens the new mic', () async {
      final gate = Completer<void>();
      final google = _SlowCancelSpeech(gate);
      final router = OnDeviceRouter(stt, google);
      await stt.prepare(SpokenLanguage.en);
      router.listen(SpokenLanguage.ar).listen((_) {});
      await pumpEventQueue();

      router.listen(SpokenLanguage.en).listen((_) {});
      await pumpEventQueue();
      await router.cancel();
      gate.complete();
      await pumpEventQueue();
      expect(native.calls, isNot(contains('start')));
    });
  });

  group('preload', () {
    test('loads the model in the background, no mic', () async {
      await stt.preload(SpokenLanguage.en);
      expect(native.calls, ['prepare']);
    });

    test('a press during the load waits for it: one load', () async {
      native.prepareGate = Completer<void>();
      unawaited(stt.preload(SpokenLanguage.en));
      await pumpEventQueue();
      var answered = false;
      final press = stt.prepare(SpokenLanguage.en).then((s) {
        answered = true;
        return s;
      });
      await pumpEventQueue();
      expect(answered, isFalse, reason: 'never "ready" before the model');
      native.prepareGate!.complete();
      expect(await press, SpeechSupport.ready);
      expect(native.calls, ['prepare']);
    });

    test('Arabic never loads Moonshine', () async {
      await stt.preload(SpokenLanguage.ar);
      expect(native.calls, isEmpty);
    });

    test('never during a listen (Talk resumed while recording)', () async {
      await stt.prepare(SpokenLanguage.en);
      stt.listen(SpokenLanguage.en).listen((_) {});
      await pumpEventQueue();
      native.calls.clear();
      await stt.preload(SpokenLanguage.en);
      expect(native.calls, isNot(contains('prepare')));
      await stt.cancel();
    });
  });

  group('prepare', () {
    test('ready when the model loads', () async {
      expect(await stt.prepare(SpokenLanguage.en), SpeechSupport.ready);
    });

    test('without a fallback, a missing model is unavailable', () async {
      native.prepareAnswer = {
        'status': 'missing',
        'files': ['encoder.ort'],
      };
      expect(await stt.prepare(SpokenLanguage.en), SpeechSupport.unavailable);
      expect(native.calls, isNot(contains('start')));
    });

    test('Moonshine never takes Arabic', () async {
      expect(
        await stt.prepare(SpokenLanguage.ar),
        SpeechSupport.languageMissing,
      );
      expect(native.calls, isEmpty);
    });
  });

  group('fallback to Google (TV-21)', () {
    late FakeSpeechToText google;

    setUp(() {
      google = FakeSpeechToText(untilStop: true, heard: ['Bye.']);
      stt = make(fallback: google);
    });

    for (final status in ['missing', 'unsupported', 'corrupt', 'failed']) {
      test('model $status: the listen goes to Google', () async {
        native.prepareAnswer = {'status': status};
        expect(await stt.prepare(SpokenLanguage.en), SpeechSupport.ready);
        expect(google.calls, ['prepare en']);
        final got = <SpeechEvent>[];
        stt.listen(SpokenLanguage.en).listen(got.add);
        await pumpEventQueue();
        await stt.stop();
        await pumpEventQueue();
        expect(native.calls, isNot(contains('start')));
        expect(google.calls, ['prepare en', 'listen en', 'stop']);
        expect((got.last as SpeechFinal).text, 'Bye.');
      });
    }

    test('Google as it answers: its own problem shows', () async {
      native.prepareAnswer = {'status': 'missing'};
      google.support = SpeechSupport.languageMissing;
      expect(
        await stt.prepare(SpokenLanguage.en),
        SpeechSupport.languageMissing,
      );
    });

    test('debug notice once per reason, saying English is on Google', () async {
      native.prepareAnswer = {'status': 'missing'};
      await stt.prepare(SpokenLanguage.en);
      await stt.prepare(SpokenLanguage.en);
      await pumpEventQueue();
      expect(native.notices, [
        'Moonshine not used (missing): English is on Google.',
      ]);
    });

    test('no debug notice outside debug builds', () async {
      stt = OnDeviceSpeechToText(
        methods: _channel,
        events: native.events.stream,
        fallback: google,
        debugNotices: false,
      );
      native.prepareAnswer = {'status': 'missing'};
      await stt.prepare(SpokenLanguage.en);
      await pumpEventQueue();
      expect(native.notices, isEmpty);
    });

    test('a load slower than the limit falls back for this press', () async {
      stt = make(
        fallback: google,
        prepareTimeout: const Duration(milliseconds: 20),
      );
      native.prepareGate = Completer<void>();
      expect(await stt.prepare(SpokenLanguage.en), SpeechSupport.ready);
      expect(google.calls, ['prepare en']);
      native.prepareGate!.complete();
      await pumpEventQueue();
    });

    test('Moonshine is tried again on the next press', () async {
      native.prepareAnswer = {'status': 'no_space'};
      await stt.prepare(SpokenLanguage.en);
      native.prepareAnswer = {'status': 'ready', 'cached': false};
      await stt.prepare(SpokenLanguage.en);
      stt.listen(SpokenLanguage.en).listen((_) {});
      await pumpEventQueue();
      expect(native.calls, contains('start'));
      expect(google.calls, ['prepare en']);
    });

    test('a start that fails before the mic records goes to Google', () async {
      final (got, _) = await listen();
      native.send('error', {'code': 'mic_init'});
      await pumpEventQueue();
      expect(native.calls, contains('cancel'));
      expect(google.calls, ['prepare en', 'listen en']);
      expect(got.single, isA<SpeechLevel>(), reason: "Google's mic");
      await stt.stop();
      await pumpEventQueue();
      expect(google.calls.last, 'stop');
      expect((got.last as SpeechFinal).text, 'Bye.');
      expect(native.notices.single, contains('start_mic_init'));
    });

    test('a start call that throws goes to Google', () async {
      native.startFails = true;
      await listen();
      expect(google.calls, ['prepare en', 'listen en']);
    });

    test('released while switching: Google gets the stop', () async {
      google.prepareGate = Completer<void>();
      await listen();
      native.send('error', {'code': 'stream_start'});
      await pumpEventQueue();
      await stt.stop();
      google.prepareGate!.complete();
      await pumpEventQueue();
      expect(google.calls, ['prepare en', 'listen en', 'stop']);
    });

    test('cancelled while switching: Google never listens', () async {
      google.prepareGate = Completer<void>();
      final (_, done) = await listen();
      native.send('error', {'code': 'mic_init'});
      await pumpEventQueue();
      await stt.cancel();
      google.prepareGate!.complete();
      await pumpEventQueue();
      await done;
      expect(google.calls, isNot(contains('listen en')));
    });

    test('a failure after the mic recorded never switches', () async {
      final (got, done) = await listen();
      native
        ..send('level', {'level': 0.4})
        ..send('error', {'code': 'mic_read'});
      await done;
      expect((got.last as SpeechFailed).error, SpeechError.other);
      expect(google.calls, isNot(contains('listen en')));
    });

    test('a refused mic is reported, not switched', () async {
      final (got, done) = await listen();
      native.send('error', {'code': 'permission'});
      await done;
      expect((got.last as SpeechFailed).error, SpeechError.permission);
      expect(google.calls, isNot(contains('listen en')));
    });

    test('late Moonshine events are ignored on Google', () async {
      final (got, _) = await listen();
      native.send('error', {'code': 'mic_init'});
      await pumpEventQueue();
      native.send('final', {'text': 'Boy.'});
      await pumpEventQueue();
      expect(got.whereType<SpeechFinal>(), isEmpty);
      await stt.cancel();
    });
  });

  group('listen', () {
    test('levels and partials pass; the sentence is the final only', () async {
      final (got, done) = await listen();
      native
        ..send('level', {'level': 0.4})
        ..send('partial', {'text': 'please'})
        ..send('partial', {'text': 'please come'});
      await pumpEventQueue();
      await stt.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      native.send('final', {'text': 'Please come home.', 'decodeMs': 120});
      await done;

      expect(got[0], isA<SpeechLevel>());
      expect((got[1] as SpeechPartial).text, 'please');
      expect((got[2] as SpeechPartial).text, 'please come');
      expect((got.last as SpeechFinal).text, 'Please come home.');
      await pumpEventQueue();
      expect(native.calls, contains('memory'));
    });

    test('the text is passed on unchanged: boy stays boy', () async {
      final (got, done) = await listen();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await stt.stop();
      native.send('final', {'text': 'Boy.'});
      await done;
      expect((got.last as SpeechFinal).text, 'Boy.');
    });

    test('no final text is noSpeech, even after a partial', () async {
      final (got, done) = await listen();
      native
        ..send('level', {'level': 0.4})
        ..send('partial', {'text': 'hello'});
      await pumpEventQueue();
      await stt.stop();
      native.send('final', {'text': '  '});
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
      native.send('final', {'text': 'hi'});
      await done;
    });

    test('TV-19 backstop: a release before any level keeps the tail', () async {
      final (_, done) = await listen();
      await stt.stop();
      await pumpEventQueue();
      expect(native.calls, isNot(contains('stop')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(native.calls, contains('stop'));
      native.send('final', {'text': ''});
      await done;
    });

    test('the watchdog never cuts the wait for the final', () async {
      stt = make(
        tail: Duration.zero,
        watchdog: const Duration(milliseconds: 30),
      );
      final (got, done) = await listen();
      await stt.stop();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      native.send('final', {'text': 'long sentence'});
      await done;
      expect((got.last as SpeechFinal).text, 'long sentence');
      expect(native.calls, isNot(contains('cancel')));
    });

    test('an event channel error also closes the native mic', () async {
      final (got, done) = await listen();
      native.events.addError(PlatformException(code: 'x'));
      await done;
      await pumpEventQueue();
      expect((got.last as SpeechFailed).error, SpeechError.other);
      expect(native.calls, contains('cancel'));
    });

    test('a final that never comes fails; a partial is not used', () async {
      stt = make(
        tail: Duration.zero,
        finalTimeout: const Duration(milliseconds: 30),
      );
      final (got, done) = await listen();
      native
        ..send('level', {'level': 0.4})
        ..send('partial', {'text': 'hello'});
      await pumpEventQueue();
      await stt.stop();
      await done;
      expect((got.last as SpeechFailed).error, SpeechError.other);
      expect(got.whereType<SpeechFinal>(), isEmpty);
      expect(native.calls, contains('cancel'));
    });

    test('cancel closes with no result and tells the native side', () async {
      final (got, done) = await listen();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await stt.cancel();
      await done;
      expect(native.calls, contains('cancel'));
      expect(got.whereType<SpeechFinal>(), isEmpty);
      expect(got.whereType<SpeechFailed>(), isEmpty);
    });

    test('cancel during the tail never stops or sends a result', () async {
      final (got, done) = await listen();
      native.send('level', {'level': 0.4});
      await pumpEventQueue();
      await stt.stop();
      await stt.cancel();
      await done;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(native.calls, isNot(contains('stop')));
      expect(got.whereType<SpeechFinal>(), isEmpty);
    });

    test("an old session's late events are dropped", () async {
      final (got, _) = await listen();
      final old = native.lastSession;
      await stt.cancel();
      final second = <SpeechEvent>[];
      stt.listen(SpokenLanguage.en).listen(second.add);
      await pumpEventQueue();
      native.send('final', {'text': 'old words'}, old);
      await pumpEventQueue();
      expect(got.whereType<SpeechFinal>(), isEmpty);
      expect(second, isEmpty);
    });

    test('without a fallback, a failed start ends the listen', () async {
      native.startFails = true;
      final (got, done) = await listen();
      await done;
      expect((got.last as SpeechFailed).error, SpeechError.other);
    });

    test('without a fallback, a mic error ends the listen', () async {
      final (got, done) = await listen();
      native.send('error', {'code': 'mic_init'});
      await done;
      expect((got.last as SpeechFailed).error, SpeechError.other);
    });
  });
}
