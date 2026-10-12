import 'dart:async';

import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:meta/meta.dart';
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
  Stream<SpeechEvent> listen(SpokenLanguage language);

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
  new({stt.SpeechToText? plugin, Duration? watchdog})
    : _stt = plugin ?? stt.SpeechToText(),
      watchdog = watchdog ?? listenFor + watchdogSlack;

  /// Q-T3 / Q10: stop after 3 s of silence or 30 s in all.
  static const pauseFor = Duration(seconds: 3);
  static const listenFor = Duration(seconds: 30);

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

  /// After an error-triggered retry, the failed session may still report
  /// `done`; it is ignored until the retry is listening.
  bool _ignoreDone = false;
  Timer? _watchdog;

  @override
  Future<SpeechSupport> prepare(SpokenLanguage language) async {
    if (!_initialized) {
      try {
        _initialized = await _stt.initialize(
          onError: _onError,
          onStatus: _onStatus,
        );
      } on Object catch (e) {
        _log.warn('init_failed', {'error': e.toString()});
        _initialized = false;
      }
    }
    if (!_initialized) return SpeechSupport.unavailable;
    final locales = await _stt.locales();
    final system = await _stt.systemLocale();
    _localeId = pickSpeechLocale(
      [for (final l in locales) l.localeId],
      language,
      systemId: system?.localeId,
    );
    _language = language;
    return _localeId == null
        ? SpeechSupport.languageMissing
        : SpeechSupport.ready;
  }

  @override
  Stream<SpeechEvent> listen(SpokenLanguage language) {
    unawaited(_out?.close());
    _ignoreDone = false;
    final out = _out = StreamController<SpeechEvent>();
    unawaited(_start(language, out, onDevice: true));
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
          localeId: _localeId,
          onDevice: onDevice,
          listenMode: stt.ListenMode.dictation,
          pauseFor: pauseFor,
          listenFor: listenFor,
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
    if (error == SpeechError.languageMissing &&
        _onDevice &&
        _language != null) {
      // Q-T3: the phone's own recognizer can't do this language; try the
      // normal one once.
      _ignoreDone = true;
      unawaited(_start(_language!, out, onDevice: false));
      return;
    }
    _finish(out, SpeechFailed(error));
  }

  void _onStatus(String status) {
    final out = _out;
    if (out == null || out.isClosed) return;
    // `done` without a final result or an error: nothing was heard.
    if (status == stt.SpeechToText.listeningStatus) _ignoreDone = false;
    if (status == stt.SpeechToText.doneStatus && !_gotFinal && !_ignoreDone) {
      _finish(out, const SpeechFailed(SpeechError.noSpeech));
    }
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
