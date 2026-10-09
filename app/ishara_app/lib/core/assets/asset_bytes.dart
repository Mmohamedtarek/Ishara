import 'package:flutter/services.dart';

/// Reads a bundled asset's bytes: only the asset's own range of the buffer
/// (a [ByteData] from the bundle may be a view into a larger one).
Future<Uint8List> readAssetBytes(String path, {AssetBundle? bundle}) async {
  final data = await (bundle ?? rootBundle).load(path);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
