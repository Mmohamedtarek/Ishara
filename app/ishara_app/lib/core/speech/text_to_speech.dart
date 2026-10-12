import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/logging/log.dart';

/// Speaks the user's words (AI-SPEC §5: `word` and `confirm`; Q-T2: typed
/// words, Speak, quick phrases).
abstract interface class TextToSpeech {
  /// Picks the voice for [language] (S7-23). false: the phone has no voice
  /// for it (S7-11: words are shown, not spoken).
  Future<bool> setLanguage(SpokenLanguage language);

  /// Speaks [text] after anything already queued; completes when it has
  /// been spoken (or dropped by [stop]).
  Future<void> speak(String text);

  /// Stops speaking and drops the queue.
  Future<void> stop();
}

/// The voice tags to try for [language], best first (S7-23): Egyptian
/// Arabic, then Arabic; the phone's English ([phoneLocales], `en-GB`…),
/// then US English, then English.
List<String> ttsLocaleCandidates(
  SpokenLanguage language,
  List<String> phoneLocales,
) {
  String tag(String l) => l.replaceAll('_', '-');
  return switch (language) {
    SpokenLanguage.ar => const ['ar-EG', 'ar'],
    SpokenLanguage.en => [
      for (final l in phoneLocales)
        if (tag(l).toLowerCase().startsWith('en-')) tag(l),
      'en-US',
      'en',
    ],
  }.fold<List<String>>([], (out, t) => out.contains(t) ? out : [...out, t]);
}

/// The phone's TTS through `flutter_tts` 4.2.5 (MIT; no network code; the
/// phone's own engine speaks).
class PlatformTextToSpeech implements TextToSpeech {
  new({FlutterTts? tts, List<String> Function()? phoneLocales})
    : _tts = tts ?? FlutterTts(),
      _phoneLocales = phoneLocales ?? (() => const []);

  final FlutterTts _tts;
  final List<String> Function() _phoneLocales;
  final _log = Log('tts');
  bool _ready = false;
  Future<void> _queue = Future.value();
  int _generation = 0;

  @override
  Future<bool> setLanguage(SpokenLanguage language) async {
    try {
      if (!_ready) {
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      for (final tag in ttsLocaleCandidates(language, _phoneLocales())) {
        if (await _tts.isLanguageAvailable(tag) == true) {
          await _tts.setLanguage(tag);
          _log.info('voice', {'language': language.name, 'tag': tag});
          return true;
        }
      }
    } on Object catch (e) {
      _log.warn('voice_failed', {'error': e.toString()});
    }
    _log.info('no_voice', {'language': language.name});
    return false;
  }

  @override
  Future<void> speak(String text) {
    final gen = _generation;
    return _queue = _queue.then((_) async {
      if (gen != _generation || text.trim().isEmpty) return;
      try {
        await _tts.speak(text);
      } on Object catch (e) {
        _log.warn('speak_failed', {'error': e.toString()});
      }
    });
  }

  @override
  Future<void> stop() async {
    _generation++;
    try {
      await _tts.stop();
    } on Object catch (e) {
      _log.warn('stop_failed', {'error': e.toString()});
    }
  }
}
