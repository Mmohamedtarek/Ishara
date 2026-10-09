import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// What the avatar page reports (engine.js `post(type, data)`).
@immutable
sealed class AvatarEvent {
  const new();

  /// Parses one message from the page. Unknown or malformed messages give
  /// an [AvatarError] (`bad_message`), never an exception.
  static AvatarEvent parse(String message) {
    final Object? m;
    try {
      m = jsonDecode(message);
    } on FormatException {
      return const AvatarError('bad_message', 'not JSON');
    }
    if (m is! Map<String, Object?>) {
      return const AvatarError('bad_message', 'not an object');
    }
    final map = m;
    String? str(String k) => switch (map[k]) {
      final String s => s,
      _ => null,
    };
    int? id() => switch (map['id']) {
      final int i => i,
      _ => null,
    };
    Duration ms() => Duration(
      microseconds: switch (map['ms']) {
        final num v when v.isFinite && v >= 0 => (v * 1000).round(),
        _ => 0,
      },
    );
    return switch (str('type')) {
      'pageStarted' => const AvatarPageStarted(),
      'loaded' => const AvatarLoaded(),
      'ready' when str('character') != null && m['signs'] is List<Object?> =>
        AvatarReady(
          character: str('character')!,
          signs: (m['signs']! as List<Object?>).whereType<String>().toSet(),
        ),
      'character' when str('character') != null => AvatarCharacterShown(
        str('character')!,
      ),
      'signStarted' => SignStarted(
        id: id(),
        label: str('label'),
        duration: ms(),
        loop: m['loop'] == true,
      ),
      'signEnded' => SignEnded(
        id: id(),
        label: str('label'),
        interrupted: m['interrupted'] == true,
      ),
      'thumbnail' => _thumbnail(str('character'), str('dataUrl')),
      'stats' when m['fps'] is num => AvatarStats(
        (m['fps']! as num).toDouble(),
      ),
      'contextRestored' => const AvatarContextRestored(),
      'error' => AvatarError(str('code') ?? 'unknown', str('message') ?? ''),
      _ => AvatarError('bad_message', 'unknown type ${str('type')}'),
    };
  }

  static AvatarEvent _thumbnail(String? character, String? url) {
    const prefix = 'data:image/jpeg;base64,';
    if (character == null || url == null || !url.startsWith(prefix)) {
      return const AvatarError('bad_message', 'bad thumbnail');
    }
    try {
      return AvatarThumbnail(
        character,
        base64Decode(url.substring(prefix.length)),
      );
    } on FormatException {
      return const AvatarError('bad_message', 'bad thumbnail');
    }
  }
}

/// The WebView started (re)loading the page; the old page is gone.
final class AvatarPageStarted extends AvatarEvent {
  const new();
}

/// The page's script is running and waits for `init`. Sent again if the
/// WebView reloads the page (for example after its renderer was restarted).
final class AvatarLoaded extends AvatarEvent {
  const new();
}

/// The first character is on screen; commands now run.
final class AvatarReady extends AvatarEvent {
  const new({required this.character, required this.signs});

  final String character;

  /// The labels the engine baked.
  final Set<String> signs;
}

/// A character finished loading and is now shown.
final class AvatarCharacterShown extends AvatarEvent {
  const new(this.character);
  final String character;
}

/// A sign (or, with [label] null, a word without a sign) started; it lasts
/// [duration] at the requested speed. Every [SignStarted] is followed by
/// exactly one [SignEnded] with the same [id].
final class SignStarted extends AvatarEvent {
  const new({
    required this.id,
    required this.label,
    required this.duration,
    required this.loop,
  });

  final int? id;
  final String? label;
  final Duration duration;
  final bool loop;
}

/// The sign with [id] ended, or was [interrupted] by another command.
final class SignEnded extends AvatarEvent {
  const new({required this.id, required this.label, required this.interrupted});

  final int? id;
  final String? label;
  final bool interrupted;
}

/// A face thumbnail for the character picker (JPEG).
final class AvatarThumbnail extends AvatarEvent {
  const new(this.character, this.jpeg);
  final String character;
  final Uint8List jpeg;
}

/// Frames per second over the last 2 s (only while stats are on).
final class AvatarStats extends AvatarEvent {
  const new(this.fps);
  final double fps;
}

/// The GPU context came back after being lost.
final class AvatarContextRestored extends AvatarEvent {
  const new();
}

/// Something failed in the page. [code]s: `webgl`, `three_load`, `init`,
/// `data`, `character` (loading), `unknown_sign`, `bad_command`, `command`,
/// `script`, `context_lost`; `bad_message` = the app couldn't read a message;
/// `page` = the WebView itself failed; `unsupported` = no WebView here.
final class AvatarError extends AvatarEvent {
  const new(this.code, this.message);

  final String code;

  /// Developer-facing detail, never shown to the user.
  final String message;
}
