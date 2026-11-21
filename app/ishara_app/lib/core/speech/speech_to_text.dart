import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/speech/speech_trace.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Whether the phone can turn speech of a language into text.
enum SpeechSupport {
  ready,

  /// The phone has no speech recognizer.
  unavailable,

  /// The recognizer can't do this language.
  languageMissing,

  /// The phone didn't answer in time (its recognizer may still be busy
  /// with the last session): try again.
  busy,
}

/// Why a listen produced no text.
enum SpeechError {
  /// Nothing (or nothing understandable) was said.
  noSpeech,

  /// The recognizer can't do this language.
  languageMissing,

  /// The microphone permission was refused.
  permission,

  /// Anything else (network, busy, recognizer error).
  other,
}

/// What one listen reports, in order: partial texts, then exactly one
/// [SpeechFinal] or [SpeechFailed]; then the stream closes.
@immutable
sealed class SpeechEvent {
  const new();
}

/// The words so far (shown while the person speaks).
final class SpeechPartial extends SpeechEvent {
  const new(this.text);
  final String text;
}

/// The sentence heard.
final class SpeechFinal extends SpeechEvent {
  const new(this.text);
  final String text;
}

/// The microphone's loudness now, 0 (quiet) to 1 (loud), for the live
/// level indicator. Comes between the other events, any number of times.
final class SpeechLevel extends SpeechEvent {
  const new(this.level);
  final double level;
}

final class SpeechFailed extends SpeechEvent {
  const new(this.error);
  final SpeechError error;
}

/// Speech → text for the other person's voice (Q-T3: the phone's own
/// recognizer, on the phone when it can).
abstract interface class SpeechToText {
  /// Gets the recognizer ready for [language] (no prompt: the microphone
  /// permission is asked for separately).
  Future<SpeechSupport> prepare(SpokenLanguage language);

  /// Listens once (see [SpeechEvent]) until [stop] or [cancel]: hold to
  /// talk, the user decides when speech ends (2026-10-26), so a pause
  /// doesn't end it, and neither does the phone ending its own session
  /// (listening goes on, what was heard is kept, 2026-11-20). Only one
  /// listen at a time.
  /// [phrases] bias the recognizer toward the app's words (S7-27; Android
  /// 13+, ignored elsewhere). Matching stays exact (sign rule 7).
  Stream<SpeechEvent> listen(
    SpokenLanguage language, {
    List<String> phrases = const [],
  });

  /// Ends the listen: what was heard comes as [SpeechFinal] (or "nothing
  /// heard"), also when the phone never answers
  /// ([PlatformSpeechToText.stopGrace]).
  Future<void> stop();

  /// Ends the listen without a result (the stream just closes).
  Future<void> cancel();
}

/// The recognizer locale for [language] among the phone's [localeIds]
/// (`ar-EG`, `ar_EG`, `en-US`…), or null. Arabic prefers Egyptian (Q-T5:
/// Egyptian Arabic), then any Arabic; English prefers the phone's own
/// English ([systemId]), then US English, then any English.
String? pickSpeechLocale(
  List<String> localeIds,
  SpokenLanguage language, {
  String? systemId,
}) {
  String norm(String id) => id.replaceAll('_', '-').toLowerCase();
  final lang = language.name;
  final matching = [
    for (final id in localeIds)
      if (norm(id) == lang || norm(id).startsWith('$lang-')) id,
  ];
  if (matching.isEmpty) return null;
  final preferred = switch (language) {
    SpokenLanguage.ar => ['ar-eg'],
    SpokenLanguage.en => [if (systemId != null) norm(systemId), 'en-us'],
  };
  for (final want in preferred) {
    for (final id in matching) {
      if (norm(id) == want) return id;
    }
  }
  return matching.first;
}

/// The phone's recognizer through `speech_to_text` 7.5.0 (BSD-3; no network
/// code of its own, but the phone's recognizer may send the audio to Google
/// or Apple: C14, Q-T3 privacy line).
///
/// Q-T3: each listen first asks for recognition on the phone. Android falls
/// back to the normal recognizer when the phone has no on-device one; if
/// the on-device one can't do the language (or refuses at the start, iOS),
/// the listen goes on without it. Any other error keeps the recognizer
/// (user decision 2026-11-20).
///
/// Hold to talk (2026-11-20): while the mic is held, a session the phone
/// ends by itself (a pause, nothing understood, a busy recognizer) is
/// started again after [restartDelay], keeping what was heard; only [stop]
/// or [cancel] end the listen.
class PlatformSpeechToText implements SpeechToText {
  new({
    stt.SpeechToText? plugin,
    Duration? watchdog,
    this.prepareTimeout = const Duration(seconds: 4),
    this.trace = SpeechTrace.off,
    this.stopGrace = const Duration(milliseconds: 2500),
    this.restartDelay = const Duration(milliseconds: 300),
    this.maxRestarts = 20,
  }) : _stt = plugin ?? stt.SpeechToText(),
       watchdog = watchdog ?? listenFor + watchdogSlack;

  /// How long getting the recognizer ready may take. On Android 13+ the
  /// plugin's locale list never answers when the phone's support check
  /// fails, which left the mic stuck in "preparing" (phone test 3).
  final Duration prepareTimeout;

  /// The word-for-word log (debug builds with developer mode on only).
  final SpeechTrace trace;

  /// Time since the listen started, for [trace].
  final _clock = Stopwatch();

  /// The quietest and loudest sound level of the listen (plugin units:
  /// Android dB), for [trace].
  double? _minLevel;
  double? _maxLevel;

  /// The locale picked for each language, so the phone is asked once, not
  /// on every tap. Dropped when the phone says the language is missing.
  final Map<SpokenLanguage, String> _picked = {};

  /// Hold to talk (2026-10-26): no pause limit, the user ends the listen.
  /// Talk stops at 60 s (its maximum recording); this is the backstop
  /// just past it.
  static const listenFor = Duration(seconds: 65);

  /// After [stop], how long the phone has to send the last result; then
  /// what was heard so far is the sentence (never stuck after a release).
  final Duration stopGrace;

  /// Debug builds only, for the phone test (2026-10-26):
  /// `--dart-define=STT_LISTEN_MODE=search` asks the recognizer for its
  /// short-query model instead of dictation.
  static const _listenModeDefine = String.fromEnvironment('STT_LISTEN_MODE');

  static stt.ListenMode get _listenMode =>
      kDebugMode && _listenModeDefine == 'search'
      ? stt.ListenMode.search
      : stt.ListenMode.dictation;

  /// Debug builds only, for the phone test: `--dart-define=STT_ON_DEVICE=false`
  /// skips the phone's on-device recognizer (Q-T3 prefers it).
  static const _onDeviceDefine = bool.fromEnvironment(
    'STT_ON_DEVICE',
    defaultValue: true,
  );

  /// A listen the platform didn't start reports nothing at all; past
  /// [listenFor] plus this, it ends as a failure (never stuck listening).
  static const watchdogSlack = Duration(seconds: 5);

  /// How long a listen may stay open at most ([listenFor] + slack).
  final Duration watchdog;

  final stt.SpeechToText _stt;
  final _log = Log('speech');
  bool _initialized = false;
  StreamController<SpeechEvent>? _out;
  bool _onDevice = true;
  SpokenLanguage? _language;
  String? _localeId;
  bool _gotFinal = false;

  /// The words to bias this listen toward (S7-27).
  List<String> _bias = const [];

  /// After an error-triggered retry, the failed session may still report
  /// `done`; it is ignored until the retry is listening.
  bool _ignoreDone = false;

  /// Phrases the recognizer marked as finished (`intermediate` results:
  /// Google's on-device recognizer sends each one with `final_result` and
  /// keeps listening through the pause), and what each earlier session of
  /// the hold heard. If a session ends with no final result, its phrases
  /// are what it heard (before any partial).
  final List<String> _phrases = [];

  /// The recognizer's last partial result. When the session ends with no
  /// final result and no finished phrase, it is the sentence: the last
  /// thing the recognizer showed before it stopped (user rule, 2026-10-12).
  /// Earlier partials are replaced as they come, so they never are.
  String _lastPartial = '';
  Timer? _watchdog;
  Timer? _stopTimer;

  /// [stop] was asked for this listen (maybe before the plugin started).
  bool _stopAsked = false;

  /// Hold to talk (2026-11-20): how long after the phone ended its session
  /// the next one starts, while the mic is held (Android refuses a new
  /// session right away).
  final Duration restartDelay;

  /// At most this many new sessions per listen (a recognizer that ends
  /// every session at once); then what was heard is the sentence.
  final int maxRestarts;

  int _restarts = 0;

  /// The next session of the hold, while waiting for it to start.
  Timer? _restartTimer;

  /// Where this session's phrases start in [_phrases] (earlier sessions of
  /// the same hold come before).
  int _sessionFrom = 0;

  /// Errors that only mean the phone ended its session (nothing, or
  /// nothing more, was understood; the recognizer was busy): while the mic
  /// is held, listening goes on. Any other error ends the listen.
  static const _sessionEndErrors = {
    'error_no_match',
    'error_speech_timeout',
    'error_busy',
    'error_client',
  };

  bool get _heardSomething => _phrases.isNotEmpty || _lastPartial.isNotEmpty;

  @override
  Future<SpeechSupport> prepare(SpokenLanguage language) async {
    _debug('prepare', {'language': language.name, 'init': _initialized});
    if (!_initialized) {
      try {
        _initialized = await _stt
            .initialize(
              onError: _onError,
              onStatus: _onStatus,
              // the plugin's own Android log (tag SpeechToTextPlugin):
              // which recognizer, biasing, errors; only with [trace] on
              debugLogging: trace.enabled,
            )
            .timeout(prepareTimeout);
      } on TimeoutException {
        _log.warn('init_timeout');
        return SpeechSupport.busy;
      } on Object catch (e) {
        _log.warn('init_failed', {'error': e.toString()});
        _initialized = false;
      }
    }
    if (!_initialized) return SpeechSupport.unavailable;
    if (_picked[language] case final id?) {
      _localeId = id;
      _language = language;
      return SpeechSupport.ready;
    }
    final List<String> ids;
    final String? systemId;
    try {
      ids = [
        for (final l in await _stt.locales().timeout(prepareTimeout))
          l.localeId,
      ];
      systemId = (await _stt.systemLocale().timeout(prepareTimeout))?.localeId;
    } on TimeoutException {
      _log.warn('locales_timeout', {'language': language.name});
      return SpeechSupport.busy;
    }
    final id = pickSpeechLocale(ids, language, systemId: systemId);
    _debug('locales', {'count': ids.length, 'system': systemId, 'picked': id});
    _localeId = id;
    _language = language;
    if (id == null) return SpeechSupport.languageMissing;
    _picked[language] = id;
    return SpeechSupport.ready;
  }

  @override
  Stream<SpeechEvent> listen(
    SpokenLanguage language, {
    List<String> phrases = const [],
  }) {
    _bias = phrases;
    unawaited(_out?.close());
    _ignoreDone = false;
    _stopAsked = false;
    _restarts = 0;
    _restartTimer?.cancel();
    _restartTimer = null;
    final out = _out = StreamController<SpeechEvent>();
    unawaited(_start(language, out, onDevice: !kDebugMode || _onDeviceDefine));
    return out.stream;
  }

  /// Starts a recognizer session for [out]: the listen's first one, or with
  /// [resume] a new one of the same hold (what was heard is kept; the clock
  /// and the watchdog go on).
  Future<void> _start(
    SpokenLanguage language,
    StreamController<SpeechEvent> out, {
    required bool onDevice,
    bool resume = false,
  }) async {
    if (language != _language || _localeId == null) {
      final support = await prepare(language);
      if (support != SpeechSupport.ready) {
        _finish(
          out,
          SpeechFailed(
            support == SpeechSupport.languageMissing
                ? SpeechError.languageMissing
                : SpeechError.other,
          ),
        );
        return;
      }
      // cancelled (or ended) while getting ready: never open the mic
      if (!identical(_out, out) || out.isClosed) return;
    }
    _onDevice = onDevice;
    _gotFinal = false;
    _lastPartial = '';
    if (resume) {
      // same hold: keep what earlier sessions heard
      _sessionFrom = _phrases.length;
    } else {
      _phrases.clear();
      _sessionFrom = 0;
      _clock
        ..reset()
        ..start();
      _minLevel = _maxLevel = null;
      _watchdog?.cancel();
      _watchdog = Timer(watchdog, () {
        _log.warn('listen_watchdog');
        unawaited(_stt.cancel());
        if (_heardSomething) {
          _finishHeard(out);
        } else {
          _finish(
            out,
            const SpeechFailed(SpeechError.other),
            source: 'watchdog',
          );
        }
      });
    }
    _debug('listen', {
      'locale': _localeId,
      'onDevice': onDevice,
      'resume': resume,
    });
    trace('listen', {
      'language': language.name,
      'locale': _localeId,
      'onDevice': onDevice,
      'mode': _listenMode.name,
      'resume': resume,
      'restarts': _restarts,
      'bias': _bias,
    });
    try {
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: stt.SpeechListenOptions(
          // Android wants a BCP-47 tag (`ar-EG`); the plugin lists `ar_EG`,
          // and an unknown tag silently falls back to the phone's language.
          localeId: _localeId?.replaceAll('_', '-'),
          onDevice: onDevice,
          listenMode: _listenMode,
          listenFor: listenFor,
          // hold to talk: ask the recognizer not to end on a pause (Android
          // EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS); the user ends
          // the listen. Recognizers may ignore it (phone check).
          pauseFor: listenFor,
          contextualPhrases: _bias.isEmpty ? null : _bias,
        ),
      );
      if (!identical(_out, out) || out.isClosed) {
        // cancelled or ended while the plugin was starting: close the mic
        // (unless a newer listen already owns it)
        if (_out == null || identical(_out, out)) await _stt.cancel();
        return;
      }
      if (_stopAsked) {
        if (resume) {
          // let go while a new session of the hold was starting: it has
          // heard nothing yet, so what came before is the sentence
          unawaited(_cancelPlugin());
          _finishHeard(out);
        } else {
          // let go while the plugin was starting: end it now
          unawaited(_stt.stop());
        }
      }
    } on Object catch (e) {
      _log.warn('listen_failed', {'error': e.toString()});
      if (resume) {
        // a new session of the hold couldn't start (the recognizer may
        // still be busy): try again, or end with what was heard
        if (_stopAsked) {
          _finishHeard(out);
        } else {
          _restart(out, reason: 'start_failed');
        }
      } else if (onDevice) {
        // Q-T3: the phone's own recognizer refused to start (iOS): the
        // normal one
        await _start(language, out, onDevice: false);
      } else {
        _finish(out, const SpeechFailed(SpeechError.other));
      }
    }
  }

  /// The phone ended its session while the mic is still held: a new one
  /// after [restartDelay], keeping what was heard.
  void _restart(StreamController<SpeechEvent> out, {required String reason}) {
    if (_stopAsked || !identical(_out, out) || out.isClosed) return;
    if (_restartTimer != null) return; // one at a time
    // the ended session's last words count before the next one starts
    _keepSessionPartial();
    // the ended session's late `done` is not the end of the listen
    _ignoreDone = true;
    // Android keeps a session that sent its final result "listening" until
    // its pause timer (65 s here) and refuses a new one meanwhile: end it
    unawaited(_cancelPlugin());
    if (_restarts >= maxRestarts) {
      _finishHeard(out);
      return;
    }
    _restarts++;
    trace('restart', {
      'ms': _clock.elapsedMilliseconds,
      'reason': reason,
      'n': _restarts,
    });
    _debug('restart', {'reason': reason, 'n': _restarts});
    _restartTimer = Timer(restartDelay, () {
      _restartTimer = null;
      final language = _language;
      if (_stopAsked || !identical(_out, out) || out.isClosed) return;
      if (language == null) {
        _finishHeard(out);
        return;
      }
      unawaited(_start(language, out, onDevice: _onDevice, resume: true));
    });
  }

  /// A session that ends with no finished phrase: its last partial is what
  /// it heard (user rule, 2026-10-12), kept for the sentence.
  void _keepSessionPartial() {
    if (_phrases.length == _sessionFrom && _lastPartial.isNotEmpty) {
      _phrases.add(_lastPartial);
    }
    _lastPartial = '';
  }

  /// Ends the plugin's session (also one the phone already ended).
  Future<void> _cancelPlugin() async {
    try {
      await _stt.cancel();
    } on Object catch (e) {
      _log.warn('cancel_failed', {'error': '$e'});
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    final out = _out;
    if (out == null || out.isClosed) return;
    final text = r.recognizedWords.trim();
    trace('result', {
      'ms': _clock.elapsedMilliseconds,
      'type': r.resultTypeValue.name,
      'alternates': [
        for (final a in r.alternates)
          {'words': a.recognizedWords, 'confidence': a.confidence},
      ],
    });
    _debug('result', {
      'type': r.resultTypeValue.name,
      'words': text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length,
    });
    switch (r.resultTypeValue) {
      case ResultType.intermediate:
        _addPhrase(text);
      case ResultType.partial:
        if (text.isNotEmpty) _lastPartial = text;
      case ResultType.finalResult:
        break;
    }
    if (r.finalResult) {
      _gotFinal = true;
      if (text.isNotEmpty) {
        // the final result wins over its own session's phrases and partial
        // (2026-10-12); the earlier sessions of the hold stay
        _phrases
          ..removeRange(_sessionFrom, _phrases.length)
          ..add(text);
        _lastPartial = '';
      }
      if (_stopAsked) {
        // let go: everything heard during the hold is the sentence
        _finishHeard(out, source: 'final');
      } else {
        // the phone ended the session on a pause; the mic is still held
        _restart(out, reason: 'final');
      }
    } else {
      out.add(SpeechPartial(r.recognizedWords));
    }
  }

  void _onError(SpeechRecognitionError e) {
    final out = _out;
    if (out == null || out.isClosed) return;
    final error = classifySpeechError(e.errorMsg);
    trace('error', {'ms': _clock.elapsedMilliseconds, 'code': e.errorMsg});
    _log.info('listen_error', {'code': e.errorMsg, 'onDevice': _onDevice});
    if (error == SpeechError.permission) {
      _finish(out, const SpeechFailed(SpeechError.permission));
      return;
    }
    if (error == SpeechError.languageMissing) {
      final language = _language;
      if (_onDevice && language != null) {
        if (_stopAsked) {
          // let go meanwhile: what was heard is the sentence
          _finishHeard(out);
          return;
        }
        // Q-T3: the phone's own recognizer can't do this language: the
        // normal one for the rest of the hold, keeping what was heard
        _restartTimer?.cancel();
        _restartTimer = null;
        _keepSessionPartial();
        _ignoreDone = true;
        unawaited(_start(language, out, onDevice: false, resume: true));
        return;
      }
      _picked.remove(language);
      _finish(out, const SpeechFailed(SpeechError.languageMissing));
      return;
    }
    if (!_stopAsked && _sessionEndErrors.contains(e.errorMsg)) {
      // between a restart and the new session's "listening": a late error
      // of the session just cancelled, not the end of the new one
      if (_ignoreDone) return;
      // the phone ended its session (nothing more understood, busy) while
      // the mic is held: listen again, keeping what was heard
      _restart(out, reason: e.errorMsg);
      return;
    }
    if (_heardSomething) {
      // the session ended badly after words: they were heard
      _finishHeard(out);
      return;
    }
    _finish(out, SpeechFailed(error));
  }

  void _onStatus(String status) {
    final out = _out;
    if (out == null || out.isClosed) return;
    _debug('status', {'status': status, 'onDevice': _onDevice});
    trace('status', {'ms': _clock.elapsedMilliseconds, 'status': status});
    if (status == stt.SpeechToText.listeningStatus) _ignoreDone = false;
    // The session is over while the mic is held, with no final result: the
    // phone ended it by itself; listen again, keeping what was heard
    // (2026-11-20). The plugin says so with `notListening` (also after an
    // empty result: ISHARA.md item 4), then `done`, which it holds back
    // after a partial result, so `notListening` is the signal to trust.
    // After a stop (the mic was let go) the plugin says both at once, before
    // the recognizer's words, which come when the audio ends (phone run 2,
    // 2026-10-27: ~0.4 s later): wait for them ([stopGrace]).
    final ended =
        status == stt.SpeechToText.notListeningStatus ||
        status == stt.SpeechToText.doneStatus;
    if (ended && !_gotFinal && !_ignoreDone && !_stopAsked) {
      _restart(out, reason: status);
    }
  }

  void _addPhrase(String text) {
    if (text.isEmpty) return;
    final from = _sessionFrom.clamp(0, _phrases.length);
    final mine = _phrases.sublist(from);
    final sofar = mine.join(' ');
    // Some recognizers resend the whole text so far, others each phrase
    // (within this session; earlier sessions of the hold stay).
    if (sofar.isNotEmpty && text.startsWith(sofar)) {
      _phrases
        ..removeRange(from, _phrases.length)
        ..add(text);
    } else if (!mine.contains(text)) {
      _phrases.add(text);
    }
  }

  void _finishHeard(StreamController<SpeechEvent> out, {String? source}) {
    final sessionHasPhrase = _phrases.length > _sessionFrom;
    final parts = [
      ..._phrases,
      if (!sessionHasPhrase && _lastPartial.isNotEmpty) _lastPartial,
    ];
    final heard = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    _finish(
      out,
      heard.isEmpty
          ? const SpeechFailed(SpeechError.noSpeech)
          : SpeechFinal(heard),
      source:
          source ??
          (_phrases.isNotEmpty
              ? 'phrases'
              : heard.isEmpty
              ? 'none'
              : 'lastPartial'),
    );
  }

  /// Debug builds only: what the recognizer does (never the words).
  void _debug(String event, Map<String, Object?> data) {
    if (kDebugMode) _log.info('stt_$event', data);
  }

  void _onLevel(double level) {
    if (_minLevel == null || level < _minLevel!) _minLevel = level;
    if (_maxLevel == null || level > _maxLevel!) _maxLevel = level;
    final out = _out;
    if (out == null || out.isClosed) return;
    out.add(SpeechLevel(levelFromDb(level)));
  }

  void _finish(
    StreamController<SpeechEvent> out,
    SpeechEvent last, {
    String source = 'error',
  }) {
    // a listen already over (or replaced) leaves the current one's timers
    if (out.isClosed) return;
    _watchdog?.cancel();
    _stopTimer?.cancel();
    _restartTimer?.cancel();
    _restartTimer = null;
    trace('end', {
      'ms': _clock.elapsedMilliseconds,
      'source': source,
      'heard': last is SpeechFinal ? last.text : null,
      'error': last is SpeechFailed ? last.error.name : null,
      'level': {'min': _minLevel, 'max': _maxLevel},
    });
    out.add(last);
    unawaited(out.close());
  }

  @override
  Future<void> stop() async {
    final out = _out;
    if (out == null || out.isClosed) return;
    trace('stop', {'ms': _clock.elapsedMilliseconds});
    _stopTimer?.cancel();
    _stopAsked = true;
    if (_restartTimer != null) {
      // let go between two sessions of the hold: none is running, so what
      // was heard is the sentence now (no grace to wait for)
      _finishHeard(out);
      return;
    }
    _stopTimer = Timer(stopGrace, () {
      if (!identical(out, _out) || out.isClosed) return;
      _finishHeard(out);
      // the phone never answered: make sure its mic is closed
      unawaited(_stt.cancel());
    });
    // Always asked, also before the plugin reports "listening": a release
    // right after the press must still end the listen.
    try {
      await _stt.stop();
    } on Object catch (e) {
      _log.warn('stop_failed', {'error': '$e'});
    }
  }

  @override
  Future<void> cancel() async {
    final out = _out;
    _out = null;
    _watchdog?.cancel();
    _stopTimer?.cancel();
    _restartTimer?.cancel();
    _restartTimer = null;
    if (out != null && !out.isClosed) {
      trace('cancel', {'ms': _clock.elapsedMilliseconds});
      // always, also before the plugin reports "listening": a cancel right
      // after the press must close the mic (_start checks [_out] too)
      await _cancelPlugin();
    } else if (_stt.isListening) {
      await _stt.cancel();
    }
    await out?.close();
  }
}

/// The plugin's error codes (Android `SpeechRecognizer.ERROR_*` and iOS
/// `SFSpeechRecognizer` errors, as `speech_to_text` 7.5.0 names them) as a
/// [SpeechError].
SpeechError classifySpeechError(String code) => switch (code) {
  'error_no_match' || 'error_speech_timeout' => SpeechError.noSpeech,
  'error_language_not_supported' ||
  'error_language_unavailable' ||
  'error_assets_not_installed' => SpeechError.languageMissing,
  'error_permission' ||
  'error_speech_recognizer_request_not_authorized' => SpeechError.permission,
  _ => SpeechError.other,
};

/// The plugin's sound level (Android: the recognizer's RMS in dB, about -2
/// in silence to 10 when speaking loudly) as 0..1 for the level indicator.
double levelFromDb(double db) => ((db + 2) / 12).clamp(0, 1).toDouble();
