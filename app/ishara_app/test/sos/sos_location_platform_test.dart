import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';

/// Records every call PhoneLocation makes to geolocator.
class _Geo extends GeolocatorPlatform {
  final calls = <String>[];
  bool fixComes = true;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
    String? requestId,
  }) async {
    final s = locationSettings;
    calls.add(
      s is AndroidSettings
          ? 'current forceLocationManager=${s.forceLocationManager}'
          : 'current ${s.runtimeType}',
    );
    if (!fixComes) throw TimeoutException('no fix');
    return _position;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    calls.add('last forceLocationManager=$forceLocationManager');
    return _position;
  }
}

final _position = Position(
  latitude: 30.04442,
  longitude: 31.235712,
  timestamp: DateTime.utc(2026, 10, 15, 18),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  late _Geo geo;
  setUp(() {
    geo = _Geo();
    GeolocatorPlatform.instance = geo;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('SOS on Android never goes through Play services (no "Location '
      'Accuracy" dialog): the fresh fix and the last known one both use '
      "Android's LocationManager", () async {
    final where = await SosLocator.locate(const PhoneLocation());
    expect(where.kind, FixKind.fresh);
    geo.fixComes = false;
    final old = await SosLocator.locate(const PhoneLocation());
    expect(old.kind, FixKind.lastKnown);
    expect(geo.calls, [
      'current forceLocationManager=true',
      'current forceLocationManager=true',
      'last forceLocationManager=true',
    ]);
  });

  test('offerAccuracy (first contact only) is the one Play services '
      'request', () async {
    await const PhoneLocation().offerAccuracy();
    expect(geo.calls, ['current forceLocationManager=false']);
  });
}
