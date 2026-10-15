import 'dart:math';

import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_id.g.dart';

/// A random id for this install (128 bits), made once and kept on the
/// phone. Learn events carry it (Phase 0 model `deviceId`), so two phones'
/// logs merge without clashes. Nothing about the phone is in it.
class DeviceId {
  static const key = 'device.id';

  /// The stored id, or a new one (stored).
  static String of(KeyValueStore kv, {Random? random}) {
    final stored = kv.getString(key);
    if (stored != null && stored.isNotEmpty) return stored;
    final r = random ?? Random.secure();
    final id = [
      for (var i = 0; i < 16; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    kv.setString(key, id).ignore();
    return id;
  }
}

@Riverpod(keepAlive: true)
String deviceId(Ref ref) => DeviceId.of(ref.watch(keyValueStoreProvider));
