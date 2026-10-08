import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ishara_app/core/recognition/model_bundle.dart';

/// Reads the synced kit (`assets/packs/asl/kit/`) from disk in host tests.
Future<Uint8List> readAsset(String path) => File(path).readAsBytes();

Map<String, dynamic> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

String readText(String path) => File(path).readAsStringSync();

Future<ModelBundle> loadKitBundle() => ModelBundle.load(readAsset);

/// `[[...], ...]` JSON -> list of int lists.
List<List<int>> intRows(Object? rows) => [
  for (final r in rows! as List<dynamic>)
    [for (final v in r as List<dynamic>) (v as num).toInt()],
];

List<double> doubles(Object? row) => [
  for (final v in row! as List<dynamic>) (v as num).toDouble(),
];
