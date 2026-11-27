import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_trace.dart';

/// Which recognizer English uses (DECISIONS TV-21).
enum EnglishEngine {
  /// Moonshine on the phone; Google when it can't run.
  moonshine,

  /// Debug builds with `--dart-define=STT_ENGINE=moonshine`: Moonshine
  /// only, so a missing model shows as "unavailable".
  moonshineOnly,

  /// iOS, or debug builds with `--dart-define=STT_ENGINE=google`.
  google,
}

/// TV-21: English uses Moonshine on Android. Debug builds can force an
/// engine with `--dart-define=STT_ENGINE=google|moonshine`; release builds
/// ignore it.
EnglishEngine englishEngine({
  bool debug = kDebugMode,
  String define = const String.fromEnvironment('STT_ENGINE'),
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return EnglishEngine.google;
  }
  if (debug && define == 'google') return EnglishEngine.google;
  if (debug && define == 'moonshine') return EnglishEngine.moonshineOnly;
  return EnglishEngine.moonshine;
}

/// Which recognizer Arabic uses (DECISIONS TV-24).
enum ArabicEngine {
  /// EgypTalk on the phone; Google when it can't run.
  egyptalk,

  /// Debug builds with `--dart-define=STT_ENGINE_AR=egyptalk`: EgypTalk
  /// only, so a missing model shows as "unavailable".
  egyptalkOnly,

  /// iOS, or debug builds with `--dart-define=STT_ENGINE_AR=google`.
  google,
}

/// TV-24: Arabic uses EgypTalk on Android. Debug builds can force an engine
/// with `--dart-define=STT_ENGINE_AR=google|egyptalk`; release builds
/// ignore it.
ArabicEngine arabicEngine({
  bool debug = kDebugMode,
  String define = const String.fromEnvironment('STT_ENGINE_AR'),
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return ArabicEngine.google;
  }
  if (debug && define == 'google') return ArabicEngine.google;
  if (debug && define == 'egyptalk') return ArabicEngine.egyptalkOnly;
  return ArabicEngine.egyptalk;
}

/// The speech engine the app uses: for each language what [englishEngine]
/// and [arabicEngine] pick, [google] for the rest and as the fallback.
SpeechToText speechEngine(
  PlatformSpeechToText google,
  SpeechTrace trace, {
  EnglishEngine? english,
  ArabicEngine? arabic,
}) {
  final en = switch (english ?? englishEngine()) {
    EnglishEngine.google => null,
    EnglishEngine.moonshine => OnDeviceSpeechToText(
      trace: trace,
      fallback: google,
    ),
    EnglishEngine.moonshineOnly => OnDeviceSpeechToText(trace: trace),
  };
  final ar = switch (arabic ?? arabicEngine()) {
    ArabicEngine.google => null,
    ArabicEngine.egyptalk => OnDeviceSpeechToText(
      model: OnDeviceModel.egyptalk,
      trace: trace,
      fallback: google,
    ),
    ArabicEngine.egyptalkOnly => OnDeviceSpeechToText(
      model: OnDeviceModel.egyptalk,
      trace: trace,
    ),
  };
  if (en == null && ar == null) return google;
  return OnDeviceRouter(en, google, arabic: ar);
}

/// Each language goes to its on-device engine ([english], [arabic]), or to
/// [google] when it has none.
class OnDeviceRouter implements SpeechToText {
  new(
    this.english,
    this.google, {
    this.arabic,
    this.switchWait = const Duration(seconds: 2),
  });

  /// How long the other engine has to close the mic.
  final Duration switchWait;

  final OnDeviceSpeechToText? english;
  final OnDeviceSpeechToText? arabic;
  final SpeechToText google;
  SpeechToText? _active;

  /// Changes on every cancel and listen: a switch still waiting is dropped.
  int _ticket = 0;

  /// Waiting for the other engine to let go of the mic.
  bool _switching = false;
  bool _stopWhileSwitching = false;
  bool _stopBySilence = false;

  SpeechToText _for(SpokenLanguage language) => switch (language) {
    SpokenLanguage.en => english ?? google,
    SpokenLanguage.ar => arabic ?? google,
  };

  @override
  Future<void> preload(SpokenLanguage language) =>
      _for(language).preload(language);

  @override
  Future<SpeechSupport> prepare(SpokenLanguage language) =>
      _for(language).prepare(language);

  @override
  Stream<SpeechEvent> listen(
    SpokenLanguage language, {
    List<String> phrases = const [],
  }) {
    final engine = _for(language);
    final previous = _active;
    final ticket = ++_ticket;
    _active = engine;
    _switching = false;
    _stopWhileSwitching = false;
    if (previous == null || identical(previous, engine)) {
      return engine.listen(language, phrases: phrases);
    }
    _switching = true;
    return _afterSwitch(previous.cancel(), engine, language, phrases, ticket);
  }

  /// Starts [engine] once the other one has closed the mic.
  Stream<SpeechEvent> _afterSwitch(
    Future<void> closing,
    SpeechToText engine,
    SpokenLanguage language,
    List<String> phrases,
    int ticket,
  ) async* {
    try {
      await closing.timeout(switchWait);
    } on Object {
      // it had its time: the new engine reports any mic problem itself
    }
    if (ticket != _ticket) return;
    _switching = false;
    final events = engine.listen(language, phrases: phrases);
    if (_stopWhileSwitching) {
      unawaited(engine.stop(bySilence: _stopBySilence));
    }
    yield* events;
  }

  @override
  Future<void> stop({bool bySilence = false}) {
    if (_switching) {
      _stopWhileSwitching = true;
      _stopBySilence = bySilence;
      return Future<void>.value();
    }
    return _active?.stop(bySilence: bySilence) ?? Future<void>.value();
  }

  @override
  Future<void> cancel() {
    _ticket++;
    _switching = false;
    return _active?.cancel() ?? Future<void>.value();
  }

  Future<void> dispose() async {
    await english?.dispose();
    await arabic?.dispose();
  }
}

/// One on-device model: its language, its channels to
/// `OnDeviceSpeechPlugin.kt` and the name in its logs.
@immutable
class OnDeviceModel {
  const new({
    required this.name,
    required this.label,
    required this.language,
    required this.languageName,
    required this.methodChannel,
    required this.eventChannel,
    this.finalTimeoutPerRecorded = 0,
  });

  /// English: Moonshine Small streaming (TV-21).
  static const moonshine = OnDeviceModel(
    name: 'moonshine',
    label: 'Moonshine',
    language: SpokenLanguage.en,
    languageName: 'English',
    methodChannel: 'ishara/moonshine',
    eventChannel: 'ishara/moonshine/events',
  );

  /// Arabic: EgypTalk-ASR-v2 through sherpa-onnx (TV-24).
  static const egyptalk = OnDeviceModel(
    name: 'egyptalk',
    label: 'EgypTalk',
    language: SpokenLanguage.ar,
    languageName: 'Arabic',
    methodChannel: 'ishara/egyptalk',
    eventChannel: 'ishara/egyptalk/events',
    // one decode of the whole recording after the release (user 2026-11-27)
    finalTimeoutPerRecorded: 0.5,
  );

  /// Prefix of the log events (`moonshine_final`, `egyptalk_fallback`…).
  final String name;

  /// For the debug notice.
  final String label;
  final SpokenLanguage language;
  final String languageName;
  final String methodChannel;
  final String eventChannel;

  /// The final text's time limit grows by this much per second recorded:
  /// 0 for a streaming model, whose final is ready at the release.
  final double finalTimeoutPerRecorded;
}

/// Speech to text on the phone for one language, through
/// `OnDeviceSpeechPlugin.kt`: English with Moonshine Small (TV-21), Arabic
/// with EgypTalk (TV-24). The sentence is the model's final text only;
/// partials are for the silence limit only (TV-17), never shown.
///
/// With a [fallback] (Google), the language goes to it for one listen when
/// the model can't run: not supported (Moonshine: Android below 8), model
/// missing, failed to load, or the listen failed to start. Each reason is
/// logged; debug builds also show it on the phone.
class OnDeviceSpeechToText implements SpeechToText {
  new({
    this.model = OnDeviceModel.moonshine,
    MethodChannel? methods,
    Stream<Object?>? events,
    this.fallback,
    this.trace = SpeechTrace.off,
    this.debugNotices = kDebugMode,
    this.stopTail = const Duration(milliseconds: 800),
    this.finalTimeout = const Duration(seconds: 10),
    this.prepareTimeout = const Duration(seconds: 30),
    this.watchdog = const Duration(seconds: 70),
  }) : _methods = methods ?? MethodChannel(model.methodChannel),
       _events =
           events ?? EventChannel(model.eventChannel).receiveBroadcastStream();

  /// Which model, and so which language.
  final OnDeviceModel model;

  /// Where the language goes when the model can't run (null: nowhere).
  final SpeechToText? fallback;

  /// Shows on the phone why the language is not on the model (debug builds).
  final bool debugNotices;

  /// The mic keeps recording this long after the release (TV-16).
  final Duration stopTail;

  /// After the native stop, how long the model has to send its final text,
  /// plus [OnDeviceModel.finalTimeoutPerRecorded] × the recording (EgypTalk:
  /// 10 s + 0.5 × the recording). Past it the listen fails: a partial is
  /// never used as the sentence.
  final Duration finalTimeout;

  /// The first use copies and loads the model.
  final Duration prepareTimeout;

  /// Past Talk's 60 s limit: never stuck listening.
  final Duration watchdog;

  /// The word-for-word log (debug builds with developer mode on only).
  final SpeechTrace trace;

  final MethodChannel _methods;
  final Stream<Object?> _events;
  final _log = Log('speech');
  final _clock = Stopwatch();
  final _release = Stopwatch();
  final _noticesShown = <String>{};

  /// The final text's time limit of the current listen (logged).
  int? _finalLimitMs;

  StreamSubscription<Object?>? _subscription;
  StreamController<SpeechEvent>? _out;
  int _session = 0;
  bool _micOnNow = false;
  bool _stopAsked = false;

  /// The current listen was ended by Talk's silence limit (TV-17, logs only).
  bool _stopBySilence = false;
  Timer? _tailTimer;
  Timer? _finalTimer;
  Timer? _watchdog;

  /// The native prepare in progress (a preload, or a press joining it).
  Future<(SpeechSupport, String)>? _preparing;

  /// The last prepare chose [fallback] for the next listen.
  bool _fallbackNext = false;

  /// This listen runs on [fallback]: stop and cancel go there.
  SpeechToText? _onFallback;
  StreamSubscription<SpeechEvent>? _fallbackEvents;
  List<String> _phrases = const [];

  void _subscribe() {
    _subscription ??= _events.listen(
      _onEvent,
      onError: (Object e) {
        _log.warn('${model.name}_event_error', {'error': '$e'});
        final out = _out;
        if (out == null || out.isClosed || _onFallback != null) return;
        unawaited(_invoke('cancel', _session));
        _finish(out, const SpeechFailed(SpeechError.other));
      },
    );
  }

  /// Talk opened in this model's language: copies (first use) and loads
  /// the model in the background, so a press doesn't wait for it. No mic,
  /// no prompt.
  @override
  Future<void> preload(SpokenLanguage language) async {
    // never during a listen: it has its model already
    if (language != model.language || _out != null) return;
    final (support, reason) = await _prepareNative();
    _log.info('${model.name}_preload', {
      'ready': support == SpeechSupport.ready,
      if (support != SpeechSupport.ready) 'reason': reason,
    });
  }

  @override
  Future<SpeechSupport> prepare(SpokenLanguage language) async {
    if (language != model.language) return SpeechSupport.languageMissing;
    _subscribe();
    var (support, reason) = (SpeechSupport.busy, 'prepare_timeout');
    try {
      (support, reason) = await _prepareNative().timeout(prepareTimeout);
    } on TimeoutException {
      _log.warn('${model.name}_prepare_timeout');
    }
    if (support == SpeechSupport.ready) {
      _fallbackNext = false;
      return support;
    }
    final google = fallback;
    if (google == null) return support;
    _fallbackNext = true;
    _noteFallback(reason);
    return await google.prepare(language);
  }

  /// The native prepare, shared by a preload and the presses during it.
  Future<(SpeechSupport, String)> _prepareNative() =>
      _preparing ??= _askNative().whenComplete(() => _preparing = null);

  Future<(SpeechSupport, String)> _askNative() async {
    final Map<String, Object?>? answer;
    try {
      answer = await _methods.invokeMapMethod<String, Object?>('prepare');
    } on Object catch (e) {
      _log.warn('${model.name}_prepare_failed', {'error': '$e'});
      return (SpeechSupport.unavailable, 'no_plugin');
    }
    final status = answer?['status'];
    if (status == 'ready') {
      if (answer?['cached'] == false) {
        _log.info('${model.name}_model_loaded', {
          'copy': answer?['copy'],
          'copy_ms': answer?['copyMs'],
          'verify_ms': answer?['verifyMs'],
          'load_ms': answer?['loadMs'],
          'pss_before_kb': answer?['pssBeforeKb'],
          'pss_after_kb': answer?['pssAfterKb'],
          'native_heap_kb': answer?['nativeHeapKb'],
        });
      }
      return (SpeechSupport.ready, 'ready');
    }
    _log.warn('${model.name}_model_unusable', {
      'status': status,
      'files': answer?['files'],
      'message': answer?['message'],
      'needed_mb': answer?['neededMb'],
      'free_mb': answer?['freeMb'],
    });
    return (SpeechSupport.unavailable, status is String ? status : 'failed');
  }

  /// Logs why the language goes to Google; debug builds also show it, once
  /// per reason, so nobody thinks they are testing the model.
  void _noteFallback(String reason) {
    _log.warn('${model.name}_fallback', {'reason': reason});
    if (!debugNotices || !_noticesShown.add(reason)) return;
    _methods.invokeMethod<void>('debugNotice', {
      'text':
          '${model.label} not used ($reason): '
          '${model.languageName} is on Google.',
    }).ignore();
  }

  @override
  Stream<SpeechEvent> listen(
    SpokenLanguage language, {
    List<String> phrases = const [],
  }) {
    final previous = _out;
    if (previous != null && !previous.isClosed) {
      unawaited(_invoke('cancel', _session));
      _clearTimers();
      unawaited(previous.close());
    }
    _out = null;
    unawaited(_fallbackEvents?.cancel());
    _fallbackEvents = null;
    _onFallback = null;
    final google = fallback;
    if (language == model.language && _fallbackNext && google != null) {
      // the prepare already found the model unusable
      _onFallback = google;
      return google.listen(language, phrases: phrases);
    }
    final out = _out = StreamController<SpeechEvent>();
    if (language != model.language) {
      _finish(out, const SpeechFailed(SpeechError.languageMissing));
      return out.stream;
    }
    _subscribe();
    final session = ++_session;
    _phrases = phrases;
    _micOnNow = false;
    _stopAsked = false;
    _stopBySilence = false;
    _clock
      ..reset()
      ..start();
    _release
      ..stop()
      ..reset();
    _watchdog = Timer(watchdog, () {
      _log.warn('${model.name}_watchdog');
      unawaited(_invoke('cancel', session));
      _finish(out, const SpeechFailed(SpeechError.other));
    });
    trace('listen', {'engine': model.name, 'session': session});
    unawaited(_start(session, out));
    return out.stream;
  }

  Future<void> _start(int session, StreamController<SpeechEvent> out) async {
    try {
      await _methods.invokeMethod<void>('start', {'session': session});
    } on Object catch (e) {
      _log.warn('${model.name}_start_failed', {'error': '$e'});
      if (identical(_out, out)) await _startFailed(out, 'start_call');
    }
  }

  /// The listen failed before the mic recorded anything: [fallback] takes
  /// it, or it fails.
  Future<void> _startFailed(
    StreamController<SpeechEvent> out,
    String code,
  ) async {
    final google = fallback;
    if (google == null) {
      _finish(out, const SpeechFailed(SpeechError.other));
      return;
    }
    _clearTimers();
    unawaited(_invoke('cancel', _session));
    _onFallback = google;
    _noteFallback('start_$code');
    final support = await google.prepare(model.language);
    if (!identical(_out, out) || out.isClosed) return; // cancelled meanwhile
    if (support != SpeechSupport.ready) {
      _finish(out, const SpeechFailed(SpeechError.other));
      return;
    }
    _fallbackEvents = google
        .listen(model.language, phrases: _phrases)
        .listen(
          out.add,
          onError: (Object e) =>
              _finish(out, const SpeechFailed(SpeechError.other)),
          onDone: () {
            if (!out.isClosed) unawaited(out.close());
          },
        );
    if (_stopAsked) unawaited(google.stop(bySilence: _stopBySilence));
  }

  void _onEvent(Object? raw) {
    if (raw is! Map || raw['session'] != _session) return;
    final out = _out;
    if (out == null || out.isClosed || _onFallback != null) return;
    switch (raw['type']) {
      case 'level':
        if (!_micOnNow) {
          _micOnNow = true;
          final on = {'ms': _clock.elapsedMilliseconds};
          _log.info('${model.name}_mic_on', on);
          trace('mic_on', on);
        }
        final level = raw['level'];
        if (level is num) out.add(SpeechLevel(level.toDouble()));
      case 'partial':
        final text = raw['text'];
        if (text is! String) return;
        trace('partial', {'ms': _clock.elapsedMilliseconds, 'text': text});
        if (text.trim().isNotEmpty) out.add(SpeechPartial(text));
      case 'final':
        final text = raw['text'];
        final heard = text is String ? text.trim() : '';
        final fields = {
          'release_to_final_ms': _release.isRunning
              ? _release.elapsedMilliseconds
              : null,
          'decode_ms': raw['decodeMs'],
          'final_limit_ms': _finalLimitMs,
          'empty': heard.isEmpty,
          // EgypTalk: the windows decoded while held (TV-17), on the phone
          if (raw['windows'] != null) ...{
            'windows': raw['windows'],
            'windows_skipped': raw['windowsSkipped'],
            'window_ms_median': raw['windowMsMedian'],
            'window_ms_max': raw['windowMsMax'],
            'audio_ms': raw['audioMs'],
            'last_word_audio_ms': raw['lastWordAudioMs'],
            'last_heard_audio_ms': raw['lastHeardAudioMs'],
            'stop': _stopBySilence ? 'silence' : 'release',
            // TV-17, after a silence stop only: from the end of the last
            // window with a word heard (the last partial) to the stop
            if (_stopBySilence) 'word_to_stop_ms': _wordToStopMs(raw),
          },
        };
        _log.info('${model.name}_final', fields);
        trace('final', {...fields, 'text': heard});
        _finish(
          out,
          heard.isEmpty
              ? const SpeechFailed(SpeechError.noSpeech)
              : SpeechFinal(heard),
        );
        unawaited(_logMemory());
      case 'error':
        final code = raw['code'];
        _log.warn('${model.name}_error', {'code': code, 'mic_on': _micOnNow});
        if (code == 'permission') {
          _finish(out, const SpeechFailed(SpeechError.permission));
        } else if (!_micOnNow) {
          // nothing recorded yet: nothing is lost by switching
          unawaited(_startFailed(out, code is String ? code : 'error'));
        } else {
          // words already said would be lost: never switch mid-listen
          _finish(out, const SpeechFailed(SpeechError.other));
        }
    }
  }

  Future<void> _logMemory() async {
    try {
      final memory = await _methods.invokeMapMethod<String, Object?>('memory');
      _log.info('${model.name}_memory', {
        'pss_kb': memory?['pssKb'],
        'native_heap_kb': memory?['nativeHeapKb'],
      });
    } on Object catch (e) {
      _log.warn('${model.name}_memory_failed', {'error': '$e'});
    }
  }

  @override
  Future<void> stop({bool bySilence = false}) async {
    final google = _onFallback;
    if (google != null) {
      _stopAsked = true;
      _stopBySilence = bySilence;
      // before its listen started, [_startFailed] sends the stop
      if (_out == null || _fallbackEvents != null) {
        await google.stop(bySilence: bySilence);
      }
      return;
    }
    final out = _out;
    if (out == null || out.isClosed || _stopAsked) return;
    _stopAsked = true;
    _stopBySilence = bySilence;
    _release.start();
    trace('stop', {'ms': _clock.elapsedMilliseconds});
    final session = _session;
    // TV-16. Talk throws away a release before recording started (it cancels
    // instead), so a stop here always gets the tail, also after TV-19's 2 s
    // backstop, when "Listening…" shows before the first level.
    if (stopTail <= Duration.zero) {
      await _stopNative(session, out);
      return;
    }
    _tailTimer = Timer(stopTail, () {
      _tailTimer = null;
      unawaited(_stopNative(session, out));
    });
  }

  Future<void> _stopNative(
    int session,
    StreamController<SpeechEvent> out,
  ) async {
    if (!identical(_out, out) || out.isClosed || _onFallback != null) return;
    // from here [finalTimeout] is the one limit
    _watchdog?.cancel();
    _watchdog = null;
    _finalTimer?.cancel();
    final recorded = _clock.elapsed;
    final limit = finalTimeout + recorded * model.finalTimeoutPerRecorded;
    _finalLimitMs = limit.inMilliseconds;
    _finalTimer = Timer(limit, () {
      _log.warn('${model.name}_final_timeout', {
        'recorded_ms': recorded.inMilliseconds,
        'limit_ms': limit.inMilliseconds,
      });
      unawaited(_invoke('cancel', session));
      _finish(out, const SpeechFailed(SpeechError.other));
    });
    await _invoke('stop', session);
  }

  @override
  Future<void> cancel() async {
    final out = _out;
    _out = null;
    _clearTimers();
    final google = _onFallback;
    _onFallback = null;
    final events = _fallbackEvents;
    _fallbackEvents = null;
    await events?.cancel();
    if (google != null) await google.cancel();
    if (out != null && !out.isClosed) {
      trace('cancel', {'ms': _clock.elapsedMilliseconds});
      await _invoke('cancel', _session);
      await out.close();
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _invoke(String method, int session) async {
    try {
      await _methods.invokeMethod<void>(method, {'session': session});
    } on Object catch (e) {
      _log.warn('${model.name}_${method}_failed', {'error': '$e'});
    }
  }

  void _clearTimers() {
    _tailTimer?.cancel();
    _tailTimer = null;
    _finalTimer?.cancel();
    _finalTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// The recording minus TV-16's tail minus where the last window with a
  /// word heard ends, in audio ms; null without one. (Not the last
  /// non-empty window: noise decoded as the same text again goes on long
  /// after the word, phone run 2026-11-27.)
  int? _wordToStopMs(Map<Object?, Object?> raw) {
    final audio = raw['audioMs'];
    final word = raw['lastHeardAudioMs'];
    if (audio is! int || word is! int || word < 0) return null;
    return audio - stopTail.inMilliseconds - word;
  }

  void _finish(StreamController<SpeechEvent> out, SpeechEvent last) {
    if (out.isClosed) return;
    if (identical(_out, out)) _clearTimers();
    out.add(last);
    unawaited(out.close());
  }
}
