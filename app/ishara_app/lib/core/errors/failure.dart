/// Typed failures. Code never swallows an error: it either handles a specific
/// [Failure] subtype or lets it reach the UI / logger.
///
/// Areas define their own subtypes next to their code (for example
/// `core/glove/glove_failures.dart`).
abstract class Failure implements Exception {
  const new(this.message, {this.cause, this.stackTrace});

  /// Developer-facing description (never shown to the user as is).
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  /// Short machine-readable kind, used in logs.
  String get kind;

  @override
  String toString() =>
      'Failure($kind): $message${cause == null ? '' : ' <- $cause'}';
}

/// A bundled asset is missing or unreadable (for example a kit file).
final class AssetFailure extends Failure {
  const new(super.message, {required this.path, super.cause, super.stackTrace});

  final String path;

  @override
  String get kind => 'asset';
}

/// Data didn't have the expected shape (JSON, CSV, BLE frame, `#` line).
final class ParseFailure extends Failure {
  const new(super.message, {this.source, super.cause, super.stackTrace});

  /// What was being parsed, for the log (never sensor values or sentences).
  final String? source;

  @override
  String get kind => 'parse';
}

/// A failure the code didn't expect. Reported to the logger as an error.
final class UnexpectedFailure extends Failure {
  const new(super.message, {super.cause, super.stackTrace});

  @override
  String get kind => 'unexpected';
}

/// Result of an operation that can fail with a [Failure].
sealed class Result<T> {
  const new();

  /// Runs [body]; a thrown [Failure] becomes [Err], any other [Exception]
  /// becomes [Err] with an [UnexpectedFailure] that keeps it. [Error]s
  /// (programming bugs such as a failed null check) are not caught: they reach
  /// the global error handler and the crash report.
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on Failure catch (f) {
      return Err(f);
    } on Exception catch (e, st) {
      return Err(UnexpectedFailure(e.toString(), cause: e, stackTrace: st));
    }
  }

  /// The value, or throws the [Failure].
  T get valueOrThrow => switch (this) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
}

final class Ok<T> extends Result<T> {
  const new(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const new(this.failure);
  final Failure failure;
}
