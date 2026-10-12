import 'package:ishara_app/core/assets/asset_bytes.dart';
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
  readAssetBytes,
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

/// Recognition as Talk reads it (tests override it with a fake feed).
@Riverpod(keepAlive: true)
Future<RecognitionFeed> recognitionFeed(Ref ref) =>
    ref.watch(recognitionServiceProvider.future);

/// Q-T2 / S7-21: the conversation ends this long after the last spoken word
/// (`active_s` in `decider.json`).
@Riverpod(keepAlive: true)
Future<Duration> conversationTimeout(Ref ref) async {
  final config = (await ref.watch(modelBundleProvider.future)).config;
  return Duration(milliseconds: (config.activeSeconds * 1000).round());
}
