import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ishara_app/features/sos/application/sos_controller.dart';
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';

/// A scripted phone location (fresh fix, last known, delays, failures).
class FakeLocation implements LocationSource, LocationPermissions {
  new({
    this.fresh,
    this.last,
    this.access = LocationAccess.granted,
    this.freshDelay = Duration.zero,
    this.freshNever = false,
    this.lastNever = false,
  });

  Fix? fresh;
  Fix? last;
  LocationAccess access;
  Duration freshDelay;

  /// The fresh fix never comes (the 10 s limit must end it).
  bool freshNever;

  /// The last known position never comes either (a stalled platform call).
  bool lastNever;
  int requests = 0;
  final calls = <String>[];

  @override
  Future<Fix?> current({required Duration limit}) async {
    calls.add('current ${limit.inSeconds}s');
    if (access != LocationAccess.granted) return null;
    if (freshNever) return await Completer<Fix?>().future;
    if (freshDelay > Duration.zero) await Future<void>.delayed(freshDelay);
    return fresh;
  }

  @override
  Future<Fix?> lastKnown() async {
    calls.add('last');
    if (lastNever) return await Completer<Fix?>().future;
    return access == LocationAccess.granted ? last : null;
  }

  @override
  Future<LocationAccess> status() async => access;

  /// Times the Location Accuracy dialog was offered.
  int accuracyOffers = 0;

  @override
  Future<void> offerAccuracy() async {
    calls.add('offerAccuracy');
    accuracyOffers++;
  }

  @override
  Future<LocationAccess> request() async {
    requests++;
    return access;
  }
}

/// Records what SOS would open; nothing is opened.
class FakeLauncher implements SosLauncher {
  new({this.whatsAppInstalled = true, this.picked});

  bool whatsAppInstalled;
  ({String name, String number})? picked;
  final opened = <String>[];

  /// The phone has an SMS app / a phone app (false: nothing opens).
  bool smsApp = true;
  bool phoneApp = true;

  @override
  Future<bool> sms(List<String> recipients, String body) async {
    opened.add('sms ${recipients.join(',')} | $body');
    return smsApp;
  }

  @override
  Future<bool> dial(String number) async {
    opened.add('dial $number');
    return phoneApp;
  }

  @override
  Future<bool> hasWhatsApp() async => whatsAppInstalled;

  @override
  Future<bool> whatsApp(String e164, String text) async {
    opened.add('whatsapp $e164 | $text');
    return true;
  }

  @override
  Future<({String name, String number})?> pickContact() async => picked;
}

class SosFakes {
  new({FakeLocation? location, FakeLauncher? launcher})
    : location = location ?? FakeLocation(),
      launcher = launcher ?? FakeLauncher();

  final FakeLocation location;
  final FakeLauncher launcher;

  List<Override> get overrides => [
    locationSourceProvider.overrideWithValue(location),
    locationPermissionsProvider.overrideWithValue(location),
    sosLauncherProvider.overrideWithValue(launcher),
  ];
}
