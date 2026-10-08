import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:logging/logging.dart';

/// Structured logging on top of `package:logging`.
///
/// Every record carries an event name and a map of fields, so sinks (console
/// now, Crashlytics later) can format or filter them. **Privacy:** never put
/// sensor values, recognized words or sentences, or speech text in fields.
class Log {
  new(String area) : _logger = Logger('ishara.$area');

  final Logger _logger;

  void debug(String event, [Map<String, Object?> fields = const {}]) =>
      _logger.fine(LogEvent(event, fields));

  void info(String event, [Map<String, Object?> fields = const {}]) =>
      _logger.info(LogEvent(event, fields));

  void warn(String event, [Map<String, Object?> fields = const {}]) =>
      _logger.warning(LogEvent(event, fields));

  /// Logs a [Failure] with its kind, cause and stack trace.
  void failure(
    String event,
    Failure failure, [
    Map<String, Object?> fields = const {},
  ]) => _logger.severe(
    LogEvent(event, {
      ...fields,
      'failure': failure.kind,
      'message': failure.message,
    }),
    failure.cause,
    failure.stackTrace,
  );
}

/// The message object of every Ishara log record.
@immutable
class LogEvent {
  const new(this.event, this.fields);

  final String event;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {'event': event, ...fields};

  @override
  String toString() => jsonEncode(toJson(), toEncodable: (o) => o.toString());
}

/// Fields that hold free text from errors; dropped when redacting.
const _freeTextFields = {'message'};

/// Formats a record as one JSON line.
///
/// With [redact] (release builds), free text that could carry user data
/// (failure messages, error descriptions) is dropped: only the event, the
/// structured fields, the failure kind and the stack trace remain. This
/// enforces the privacy rule even if an error message ever contains a
/// sentence or sensor values.
String formatLogRecord(LogRecord r, {bool redact = false}) {
  final msg = r.object is LogEvent
      ? (r.object! as LogEvent).toJson()
      : {'event': redact ? 'log' : r.message};
  if (redact) msg.removeWhere((k, _) => _freeTextFields.contains(k));
  return jsonEncode({
    't': r.time.toUtc().toIso8601String(),
    'level': r.level.name,
    'logger': r.loggerName,
    ...msg,
    if (r.error != null) 'error': redact ? 'redacted' : r.error.toString(),
  }, toEncodable: (o) => o.toString());
}

StreamSubscription<LogRecord>? _sinkSubscription;

/// Sends records to the console: everything in debug, INFO and up in release.
/// Calling it again replaces the previous sink (no duplicate lines).
/// Release builds redact free text (see [formatLogRecord]).
void setUpLogging({
  void Function(String line)? sink,
  bool redact = kReleaseMode,
}) {
  hierarchicalLoggingEnabled = true;
  Logger.root.level = kReleaseMode ? Level.INFO : Level.ALL;
  final out = sink ?? debugPrint;
  unawaited(_sinkSubscription?.cancel());
  _sinkSubscription = Logger.root.onRecord.listen((r) {
    out(formatLogRecord(r, redact: redact));
    if (r.stackTrace != null && r.level >= Level.SEVERE) {
      out(r.stackTrace.toString());
    }
  });
}
