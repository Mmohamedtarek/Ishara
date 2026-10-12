import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';
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

  /// Listens once (see [SpeechEvent]). Only one listen at a time.
  /// [phrases] bias the recognizer toward the app's words (S7-27; Android
  /// 13+, ignored elsewhere). Matching stays exact (sign rule 7).
  Stream<SpeechEvent> listen(
    SpokenLanguage language, {
    List<String> phrases = const [],
  });

  /// Ends the listen early: what was heard so far comes as [SpeechFinal].
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
/// the on-device one can't do the language, the listen is retried once
/// without it.
class PlatformSpeechToText implements SpeechToText {
  new({
    stt.SpeechToText? plugin,
    Duration? watchdog,
    this.prepareTimeout = const Duration(seconds: 4),
  }) : _stt = plugin ?? stt.SpeechToText(),
       watchdog = watchdog ?? listenFor + watchdogSlack;

  /// How long getting the recognizer ready may take. On Android 13+ the
  /// plugin's locale list never answers when the phone's support check
  /// fails, which left the mic stuck in "preparing" (phone test 3).
  final Duration prepareTimeout;

  /// The locale picked for each language, so the phone is asked once, not
  /// on every tap. Dropped when the phone says the language is missing.
  final Map<SpokenLanguage, String> _picked = {};

  /// Q-T3 / Q10: stop after 3 s of silence or 30 s in all.
  static const pauseFor = Duration(seconds: 3);
  static const listenFor = Duration(seconds: 30);

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
  /// keeps listening through the pause). If the session then ends with no
  /// final result, they are the sentence (before any partial).
  final List<String> _phrases = [];

  /// The recognizer's last partial result. When the session ends with no
  /// final result and no finished phrase, it is the sentence: the last
  /// thing the recognizer showed before it stopped (user rule, 2026-10-12).
  /// Earlier partials are replaced as they come, so they never are.
  String _lastPartial = '';
  Timer? _watchdog;

  @override
  Future<SpeechSupport> prepare(SpokenLanguage language) async {
    _debug('prepare', {'language': language.name, 'init': _initialized});
    if (!_initialized) {
      try {
        _initialized = await _stt
            .initialize(onError: _onError, onStatus: _onStatus)
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
    final out = _out = StreamController<SpeechEvent>();
    unawaited(_start(language, out, onDevice: !kDebugMode || _onDeviceDefine));
    return out.stream;
  }

  Future<void> _start(
    SpokenLanguage language,
    StreamController<SpeechEvent> out, {
    required bool onDevice,
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
    }
    _onDevice = onDevice;
    _gotFinal = false;
    _phrases.clear();
    _lastPartial = '';
    _debug('listen', {'locale': _localeId, 'onDevice': onDevice});
    _watchdog?.cancel();
    _watchdog = Timer(watchdog, () {
      _log.warn('listen_watchdog');
      unawaited(_stt.cancel());
      _finish(out, const SpeechFailed(SpeechError.other));
    });
    try {
      await _stt.listen(
        onResult: _onResult,
        listenOptions: stt.SpeechListenOptions(
          // Android wants a BCP-47 tag (`ar-EG`); the plugin lists `ar_EG`,
          // and an unknown tag silently falls back to the phone's language.
          localeId: _localeId?.replaceAll('_', '-'),
          onDevice: onDevice,
          listenMode: stt.ListenMode.dictation,
          pauseFor: pauseFor,
          listenFor: listenFor,
          contextualPhrases: _bias.isEmpty ? null : _bias,
        ),
      );
    } on Object catch (e) {
      _log.warn('listen_failed', {'error': e.toString()});
      if (onDevice) {
        await _start(language, out, onDevice: false);
      } else {
        _finish(out, const SpeechFailed(SpeechError.other));
      }
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    final out = _out;
    if (out == null || out.isClosed) return;
    final text = r.recognizedWords.trim();
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
      final text = r.recognizedWords.trim();
      _finish(
        out,
        text.isEmpty
            ? const SpeechFailed(SpeechError.noSpeech)
            : SpeechFinal(text),
      );
    } else {
      out.add(SpeechPartial(r.recognizedWords));
    }
  }

  void _onError(SpeechRecognitionError e) {
    final out = _out;
    if (out == null || out.isClosed) return;
    final error = classifySpeechError(e.errorMsg);
    _log.info('listen_error', {'code': e.errorMsg, 'onDevice': _onDevice});
    if (error == SpeechError.noSpeech &&
        (_phrases.isNotEmpty || _lastPartial.isNotEmpty)) {
      // The session ended badly after finished phrases: they were heard.
      _finishHeard(out);
      return;
    }
    if (error == SpeechError.languageMissing &&
        _onDevice &&
        _language != null) {
      // Q-T3: the phone's own recognizer can't do this language; try the
      // normal one once.
      _ignoreDone = true;
      unawaited(_start(_language!, out, onDevice: false));
      return;
    }
    if (error == SpeechError.languageMissing) _picked.remove(_language);
    _finish(out, SpeechFailed(error));
  }

  void _onStatus(String status) {
    final out = _out;
    if (out == null || out.isClosed) return;
    _debug('status', {'status': status, 'onDevice': _onDevice});
    if (status == stt.SpeechToText.listeningStatus) _ignoreDone = false;
    // `done` without a final result: the finished phrases, or nothing.
    if (status == stt.SpeechToText.doneStatus && !_gotFinal && !_ignoreDone) {
      _finishHeard(out);
    }
  }

  void _addPhrase(String text) {
    if (text.isEmpty) return;
    final sofar = _phrases.join(' ');
    // Some recognizers resend the whole text so far, others each phrase.
    if (sofar.isNotEmpty && text.startsWith(sofar)) {
      _phrases
        ..clear()
        ..add(text);
    } else if (!_phrases.contains(text)) {
      _phrases.add(text);
    }
  }

  void _finishHeard(StreamController<SpeechEvent> out) {
    final phrases = _phrases.join(' ').trim();
    final heard = phrases.isEmpty ? _lastPartial : phrases;
    _finish(
      out,
      heard.isEmpty
          ? const SpeechFailed(SpeechError.noSpeech)
          : SpeechFinal(heard),
    );
  }

  /// Debug builds only: what the recognizer does (never the words).
  void _debug(String event, Map<String, Object?> data) {
    if (kDebugMode) _log.info('stt_$event', data);
  }

  void _finish(StreamController<SpeechEvent> out, SpeechEvent last) {
    _watchdog?.cancel();
    if (out.isClosed) return;
    out.add(last);
    unawaited(out.close());
  }

  @override
  Future<void> stop() async {
    if (_stt.isListening) await _stt.stop();
  }

  @override
  Future<void> cancel() async {
    final out = _out;
    _out = null;
    _watchdog?.cancel();
    if (_stt.isListening) await _stt.cancel();
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
