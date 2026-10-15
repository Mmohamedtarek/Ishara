import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_rules.g.dart';

/// Rules kept as data (`assets/config/app_rules.json`), not code.
@immutable
class AppRules {
  const new({
    required this.conversationGap,
    required this.emergencyRegion,
    required this.emergencyNumbers,
  });

  /// Throws [ParseFailure] if anything is missing or wrong.
  factory parse(String json) {
    Never fail(String why) =>
        throw ParseFailure('app_rules.json: $why', source: 'app_rules.json');
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      fail('not JSON');
    }
    if (root is! Map<String, Object?>) fail('not an object');
    final gap = root['conversationGapMinutes'];
    if (gap is! int || gap <= 0) fail('conversationGapMinutes');
    final emergency = root['emergency'];
    if (emergency is! Map<String, Object?>) fail('emergency');
    final region = emergency['region'];
    final all = emergency['numbers'];
    if (region is! String || all is! Map<String, Object?>) fail('emergency');
    final numbers = all[region];
    if (numbers is! Map<String, Object?> ||
        numbers.values.any((v) => v is! String || !_digits.hasMatch(v))) {
      fail('emergency numbers of $region');
    }
    return AppRules(
      conversationGap: Duration(minutes: gap),
      emergencyRegion: region,
      emergencyNumbers: Map.unmodifiable(numbers.cast<String, String>()),
    );
  }

  static final _digits = RegExp(r'^\d{2,6}$');

  /// Talk starts a new conversation after this long with no message (S9-4).
  final Duration conversationGap;

  /// The region whose numbers SOS offers (`EG`).
  final String emergencyRegion;

  /// By service: `ambulance`, `police`.
  final Map<String, String> emergencyNumbers;

  String? get ambulance => emergencyNumbers['ambulance'];
}

const appRulesAsset = 'assets/config/app_rules.json';

/// Loaded once (`main` waits for it before the first frame).
@Riverpod(keepAlive: true)
Future<AppRules> appRules(Ref ref) async =>
    AppRules.parse(await rootBundle.loadString(appRulesAsset));
