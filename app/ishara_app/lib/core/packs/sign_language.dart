import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';

/// Sign languages the app knows about. App v1 runs ASL only; ArSL comes in a
/// later update as a new data pack (no new code).
enum SignLanguage {
  /// American Sign Language.
  asl,

  /// Egyptian Arabic Sign Language.
  arsl;

  /// Stored and synced as this string.
  String get id => name;

  /// Parses a stored value. Anything unknown (or null) is null.
  static SignLanguage? tryParse(String? id) => switch (id) {
    'asl' => asl,
    'arsl' => arsl,
    _ => null,
  };
}

/// Everything one sign language brings, all under `assets/packs/<lang>/`.
@immutable
class SignLanguagePack {
  const new({required this.language, required this.available});

  final SignLanguage language;

  /// False = listed in the UI ("Coming soon") but can never be loaded.
  final bool available;

  String get dir => 'assets/packs/${language.id}';

  /// The sign catalogue (`signs.json`).
  String get catalogueAsset => '$dir/signs.json';

  /// The recognizer models (labels, decider config, `.tflite`).
  String get modelDir => '$dir/kit/model';

  /// Mock glove recordings for this language.
  String get mockDir => '$dir/kit/mock';

  /// The avatar sign library (keyframes), added with the avatar.
  String get avatarLibraryAsset => '$dir/avatar_signs.js';
}

/// A pack that isn't available was requested.
final class PackUnavailableFailure extends Failure {
  new(this.language)
    : super('sign language pack ${language.id} is not available');

  final SignLanguage language;

  @override
  String get kind => 'pack_unavailable';
}

/// The packs of this app version.
abstract final class PackRegistry {
  /// ASL is available; ArSL is coming in a future update.
  static const Map<SignLanguage, SignLanguagePack> packs = {
    SignLanguage.asl: SignLanguagePack(
      language: SignLanguage.asl,
      available: true,
    ),
    SignLanguage.arsl: SignLanguagePack(
      language: SignLanguage.arsl,
      available: false,
    ),
  };

  /// The default sign language (prompt: ASL is the default in v1).
  static const SignLanguage defaultLanguage = SignLanguage.asl;

  static bool isAvailable(SignLanguage l) => packs[l]!.available;

  /// The pack for [l]. Throws [PackUnavailableFailure] if it isn't
  /// available: no feature can ever load such a pack.
  static SignLanguagePack require(SignLanguage l) {
    final p = packs[l]!;
    if (!p.available) throw PackUnavailableFailure(l);
    return p;
  }

  /// A stored or synced value → the language to use. Unknown, missing or
  /// unavailable (e.g. `arsl` in v1) → the default, never a crash.
  static SignLanguage resolve(String? stored) {
    final l = SignLanguage.tryParse(stored);
    return l != null && isAvailable(l) ? l : defaultLanguage;
  }
}
