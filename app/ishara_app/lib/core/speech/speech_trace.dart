import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/logging/log.dart';

/// Word-for-word log of speech → sign, for finding why a word is lost on a
/// phone (user request, 2026-10-26).
///
/// Only in debug builds with developer mode on: release builds compile it
/// out ([kDebugMode]). It is the one place that logs heard words, an
/// exception to [Log]'s privacy rule that the user asked for: the lines
/// stay in the phone's own log, on a debug build a developer runs.
class SpeechTrace {
  const new(this._on);

  /// Never logs (tests, and providers built without developer mode).
  static const off = SpeechTrace(_never);

  static bool _never() => false;
  static final _log = Log('stt_trace');

  final bool Function() _on;

  /// Whether a line would be written now.
  bool get enabled => kDebugMode && _on();

  void call(String event, Map<String, Object?> fields) {
    if (enabled) _log.info('trace_$event', fields);
  }
}
