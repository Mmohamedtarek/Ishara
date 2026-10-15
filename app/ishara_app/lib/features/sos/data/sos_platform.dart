import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:url_launcher/url_launcher.dart';

/// Location while in use (never in the background), for SOS.
enum LocationAccess { granted, denied, deniedForever, serviceOff }

abstract interface class LocationPermissions {
  Future<LocationAccess> status();

  /// Asks the system once (while in use only).
  Future<LocationAccess> request();

  /// Offers the system "Location Accuracy" dialog (Android, Google Play
  /// services) if it is off. Only at a calm moment, when the first emergency
  /// contact is added: never during SOS.
  Future<void> offerAccuracy();
}

/// The phone's location service through geolocator's Android / iOS parts
/// (no Linux part: it pulls in MPL-2.0 packages). Read only when SOS is
/// pressed; nothing is kept or uploaded.
class PhoneLocation implements LocationSource, LocationPermissions {
  const new();

  static GeolocatorPlatform get _g => GeolocatorPlatform.instance;
  static final _log = Log('sos');

  /// SOS on Android reads Android's own LocationManager, never Google Play
  /// services' fused client: that client first checks the location settings
  /// and shows the system "Location Accuracy" dialog over the SOS sheet. The
  /// LocationManager never asks for a change; it takes what the phone gives
  /// (its fused provider on Android 12+, else GPS, else network).
  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<Fix?> current({required Duration limit}) async {
    if (await status() != LocationAccess.granted) return null;
    final settings = _android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: limit,
            forceLocationManager: true,
          )
        : LocationSettings(accuracy: LocationAccuracy.high, timeLimit: limit);
    try {
      return _fix(await _g.getCurrentPosition(locationSettings: settings));
    } on Object catch (e) {
      _log.info('no_fresh_fix', {'error': e.runtimeType.toString()});
      return null;
    }
  }

  @override
  Future<Fix?> lastKnown() async {
    if (await status() != LocationAccess.granted) return null;
    final p = await _g.getLastKnownPosition(forceLocationManager: _android);
    return p == null ? null : _fix(p);
  }

  static Fix _fix(Position p) => Fix(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracyMeters: p.accuracy,
    at: p.timestamp.toLocal(),
  );

  @override
  Future<LocationAccess> status() async {
    if (!await _g.isLocationServiceEnabled()) return LocationAccess.serviceOff;
    return _map(await _g.checkPermission());
  }

  @override
  Future<LocationAccess> request() async => _map(await _g.requestPermission());

  /// One short Play services request: if Location Accuracy is off, the
  /// system offers to turn it on (the user may say no). The position is
  /// thrown away.
  @override
  Future<void> offerAccuracy() async {
    if (!_android || await status() != LocationAccess.granted) return;
    try {
      await _g.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        ),
      );
    } on Object catch (e) {
      _log.info('accuracy_offer', {'error': e.runtimeType.toString()});
    }
  }

  static LocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    _ => LocationAccess.denied,
  };
}

/// What SOS opens on the phone. Every action opens another app filled in;
/// the user sends or calls there (no SEND_SMS, nothing goes out by itself).
abstract interface class SosLauncher {
  /// The SMS app, with [recipients] (E.164) and [body].
  Future<bool> sms(List<String> recipients, String body);

  /// The dialer with [number] (not a call).
  Future<bool> dial(String number);

  Future<bool> hasWhatsApp();

  /// WhatsApp, to [e164], with [text].
  Future<bool> whatsApp(String e164, String text);

  /// The system contact picker (no contacts permission); null if cancelled.
  Future<({String name, String number})?> pickContact();
}

class PhoneSosLauncher implements SosLauncher {
  const new();

  static const _channel = MethodChannel('ishara/contacts');

  /// The SMS URI: recipients separated by commas (RFC 5724), the message
  /// percent-encoded.
  static Uri smsUri(List<String> recipients, String body) => Uri.parse(
    'sms:${recipients.join(',')}?body=${Uri.encodeComponent(body)}',
  );

  static Uri telUri(String number) => Uri(scheme: 'tel', path: number);

  static Uri waUri(String e164, String text) => Uri.parse(
    'https://wa.me/${e164.replaceAll('+', '')}'
    '?text=${Uri.encodeComponent(text)}',
  );

  /// False when no app opened (none installed, the platform refused):
  /// an SOS tap never throws.
  static Future<bool> _open(Uri uri, {String kind = 'open'}) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      Log('sos').info('${kind}_failed', {'error': e.runtimeType.toString()});
      return false;
    }
  }

  @override
  Future<bool> sms(List<String> recipients, String body) =>
      _open(smsUri(recipients, body), kind: 'sms');

  @override
  Future<bool> dial(String number) => _open(telUri(number), kind: 'dial');

  @override
  Future<bool> hasWhatsApp() async {
    try {
      return await _channel.invokeMethod<bool>('hasWhatsApp') ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> whatsApp(String e164, String text) =>
      _open(waUri(e164, text), kind: 'whatsapp');

  @override
  Future<({String name, String number})?> pickContact() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('pickPhone');
      final number = r?['number'];
      if (number is! String) return null;
      return (name: (r?['name'] as String?) ?? '', number: number);
    } on Object {
      return null;
    }
  }
}
