import 'dart:convert';
import 'dart:typed_data';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/ensemble.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:meta/meta.dart';

/// Reads one asset by path (rootBundle in the app, files in tests).
typedef AssetReader = Future<Uint8List> Function(String path);

/// Everything in the kit's `model/` folder: labels, Decider config and the
/// model files listed in `decider.json`, in that order.
@immutable
class ModelBundle {
  const new({required this.labels, required this.config, required this.models});

  /// Loads from [dir], by default the default pack's models (the app passes
  /// the active pack's `modelDir`).
  static Future<ModelBundle> load(AssetReader read, {String? dir}) async {
    final base =
        dir ?? PackRegistry.packs[PackRegistry.defaultLanguage]!.modelDir;
    Future<Uint8List> get(String name) async {
      try {
        return await read('$base/$name');
      } on Failure {
        rethrow;
      } on Exception catch (e, st) {
        throw AssetFailure(
          'missing',
          path: '$base/$name',
          cause: e,
          stackTrace: st,
        );
      }
    }

    final labels = Labels.parse(utf8.decode(await get('labels.txt')));
    final config = DeciderConfig.parse(utf8.decode(await get('decider.json')))
      ..validateAgainst(labels);
    final models = <String, Uint8List>{};
    for (final name in config.models) {
      models[name] = await get(name);
    }
    return ModelBundle(labels: labels, config: config, models: models);
  }

  final Labels labels;
  final DeciderConfig config;

  /// Model file name -> bytes, in `decider.json` order.
  final Map<String, Uint8List> models;

  /// Loads the interpreters (call in the isolate that will run them).
  Ensemble buildEnsemble() {
    final loaded = <ProbabilityModel>[];
    try {
      for (final e in models.entries) {
        loaded.add(
          TfliteModel.fromBytes(e.value, name: e.key, labels: labels.length),
        );
      }
    } on Object {
      for (final m in loaded) {
        m.close();
      }
      rethrow;
    }
    return Ensemble(loaded);
  }
}
