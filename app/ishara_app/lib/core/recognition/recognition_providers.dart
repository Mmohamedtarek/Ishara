import 'package:flutter/services.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_engine.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'recognition_providers.g.dart';

/// The active pack's models (labels, config, `.tflite`), loaded once.
@Riverpod(keepAlive: true)
Future<ModelBundle> modelBundle(Ref ref) => ModelBundle.load(
  (path) async => (await rootBundle.load(path)).buffer.asUint8List(),
  dir: ref.watch(activePackProvider).modelDir,
);

/// The recognizer in its background isolate.
@Riverpod(keepAlive: true)
Future<RecognizerEngine> recognizerEngine(Ref ref) async {
  final engine = await IsolateRecognizer.spawn(
    await ref.watch(modelBundleProvider.future),
  );
  ref.onDispose(engine.dispose);
  return engine;
}

/// Glove → text events for Talk and Learn.
@Riverpod(keepAlive: true)
Future<RecognitionService> recognitionService(Ref ref) async {
  final bundle = await ref.watch(modelBundleProvider.future);
  final service = RecognitionService(
    source: ref.watch(gloveSourceProvider),
    engine: await ref.watch(recognizerEngineProvider.future),
    labels: bundle.labels,
  );
  ref.onDispose(service.dispose);
  return service;
}
