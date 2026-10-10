import 'dart:convert';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';

/// One character the avatar can use (`assets/avatar/cast.json`).
///
/// RB-1: the characters are sample models; they are data, so replacing them
/// needs no code change.
@immutable
class AvatarCharacter {
  const new({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.feminine,
  });

  final String id;
  final String nameEn;
  final String nameAr;

  /// Arabic texts use their feminine forms with this character.
  final bool feminine;

  String name({required bool arabic}) => arabic ? nameAr : nameEn;
}

/// The character list, in picker order.
///
/// A character marked `"hidden": true` in cast.json stays in the files but
/// not in the app: it is not in [characters], and a stored or synced choice
/// of it falls back to the default ([byId]). RB-1: Sara is hidden in v1
/// (user decision); removing the flag brings her back.
@immutable
class AvatarCast {
  const new _(this.characters, this.defaultId);

  factory parse(String json) {
    Never fail(String m) => throw ParseFailure(m, source: 'cast.json');
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw ParseFailure('not JSON', source: 'cast.json', cause: e);
    }
    if (root is! Map<String, Object?>) fail('the root is not an object');
    final chars = root['characters'];
    if (chars is! Map<String, Object?> || chars.isEmpty) fail('no characters');
    final list = <AvatarCharacter>[];
    for (final MapEntry(:key, :value) in chars.entries) {
      if (value is! Map<String, Object?>) fail('character $key');
      final hide = value['hidden'] ?? false;
      if (hide is! bool) fail('character $key: hidden must be true or false');
      // checked even when hidden, so removing the flag can't break the app
      String text(String k) => switch (value[k]) {
        final String s when s.trim().isNotEmpty => s,
        _ => fail('character $key: "$k" must be text'),
      };
      if (value['kind'] != 'glb') fail('character $key: kind must be glb');
      final src = text('src');
      if (!src.startsWith('characters/') || !src.endsWith('.glb')) {
        fail('character $key: src must be characters/<name>.glb');
      }
      final character = AvatarCharacter(
        id: key,
        nameEn: text('en'),
        nameAr: text('ar'),
        feminine: value['fem'] == true,
      );
      if (!hide) list.add(character);
    }
    if (list.isEmpty) fail('every character is hidden');
    final def = root['default'];
    if (def is! String || !list.any((c) => c.id == def)) {
      fail('default must name a character that is not hidden');
    }
    return AvatarCast._(List.unmodifiable(list), def);
  }

  /// The characters the app offers (hidden ones left out).
  final List<AvatarCharacter> characters;
  final String defaultId;

  /// Setup, Settings and the Avatar studio show a character choice only
  /// when there is one to make; with one character they show it alone.
  bool get showPicker => characters.length > 1;

  AvatarCharacter byId(String? id) => characters.firstWhere(
    (c) => c.id == id,
    orElse: () => characters.firstWhere((c) => c.id == defaultId),
  );
}
