import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/assets/asset_bytes.dart';

/// A bundle whose ByteData is a view into a larger buffer (as platform
/// replies can be).
class _ViewBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final big = Uint8List.fromList([9, 9, 9, 1, 2, 3, 9, 9]);
    return ByteData.view(big.buffer, 3, 3);
  }
}

void main() {
  test('only the asset range of the buffer is returned', () async {
    expect(await readAssetBytes('x', bundle: _ViewBundle()), [1, 2, 3]);
  });

  testWidgets('reads from the app bundle by default', (t) async {
    final b = await t.runAsync(() => readAssetBytes('assets/avatar/cast.json'));
    expect(b, isNotEmpty);
  });
}
