import 'package:flutter/services.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pack_providers.g.dart';

/// The sign language in use. ASL by default; ArSL can be chosen in the UI
/// but never becomes active in v1.
@Riverpod(keepAlive: true)
class ActiveSignLanguage extends _$ActiveSignLanguage {
  @override
  SignLanguage build() => PackRegistry.defaultLanguage;

  /// Selects [language] if its pack is available. Returns false otherwise:
  /// nothing changes and nothing is saved (the caller shows the "coming
  /// soon" dialog).
  bool select(SignLanguage language) {
    if (!PackRegistry.isAvailable(language)) return false;
    state = language;
    return true;
  }

  /// Applies a stored or synced value; `arsl`, unknown or missing → ASL.
  void restore(String? stored) => state = PackRegistry.resolve(stored);
}

/// The active language's pack (always an available one).
@Riverpod(keepAlive: true)
SignLanguagePack activePack(Ref ref) =>
    PackRegistry.require(ref.watch(activeSignLanguageProvider));

/// The active pack's model labels (`labels.txt` only: the word list doesn't
/// need the model files).
@Riverpod(keepAlive: true)
Future<Labels> packLabels(Ref ref) async {
  final pack = ref.watch(activePackProvider);
  return Labels.parse(
    await rootBundle.loadString('${pack.modelDir}/labels.txt'),
  );
}

/// The active pack's sign catalogue, checked against its model labels and
/// its language (a catalogue of another, or unavailable, language is
/// refused).
@Riverpod(keepAlive: true)
Future<SignCatalogue> signCatalogue(Ref ref) async {
  final pack = ref.watch(activePackProvider);
  final labels = await ref.watch(packLabelsProvider.future);
  final cat = SignCatalogue.parse(
    await rootBundle.loadString(pack.catalogueAsset),
    labels: labels,
  );
  if (cat.language != pack.language) {
    throw ParseFailure(
      '${pack.catalogueAsset} is for ${cat.language.id}, '
      'not ${pack.language.id}',
      source: 'signs.json',
    );
  }
  return cat;
}
