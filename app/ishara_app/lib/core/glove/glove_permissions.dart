import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// The result of asking for the glove's runtime permissions.
enum GlovePermission {
  granted,

  /// Refused this time: asking again can show the system prompt.
  denied,

  /// Refused for good ("Don't ask again" / iOS): only the phone's settings
  /// can change it.
  permanentlyDenied,
}

/// Runtime permissions the glove needs before scanning (the Pair screen
/// asks; PROGRESS step 3). Only `lib/core/glove/` knows which glove source
/// is active, so the mock glove's version needs nothing.
abstract interface class GlovePermissions {
  /// Asks for what scanning and connecting need (shows the system prompt
  /// when it can).
  Future<GlovePermission> request();

  /// Android 11 and older: scanning also needs location. Called when the
  /// adapter reports "unauthorized" although [request] was granted.
  Future<GlovePermission> requestLocation();

  /// Whether scanning is already allowed, without asking (used at start-up
  /// to reconnect the paired glove; never shows a prompt).
  Future<bool> granted();

  /// Opens this app's page in the phone's settings.
  Future<bool> openSettings();
}

/// The mock glove: no permission needed.
class NoGlovePermissions implements GlovePermissions {
  const new();

  @override
  Future<GlovePermission> request() async => GlovePermission.granted;

  @override
  Future<GlovePermission> requestLocation() async => GlovePermission.granted;

  @override
  Future<bool> granted() async => true;

  @override
  Future<bool> openSettings() async => false;
}

/// The real glove (`permission_handler`, MIT, no network).
///
/// Android 12+: Nearby devices (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`; the
/// manifest marks SCAN `neverForLocation`). Android 11 and older: those are
/// granted at install and scanning needs location instead
/// ([requestLocation]). iOS: Bluetooth.
class PlatformGlovePermissions implements GlovePermissions {
  const new();

  static GlovePermission _merge(Iterable<PermissionStatus> all) {
    if (all.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return GlovePermission.permanentlyDenied;
    }
    if (all.every((s) => s.isGranted || s.isLimited)) {
      return GlovePermission.granted;
    }
    return GlovePermission.denied;
  }

  static List<Permission> get _wanted =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? [Permission.bluetooth]
      : [Permission.bluetoothScan, Permission.bluetoothConnect];

  @override
  Future<GlovePermission> request() async =>
      _merge((await _wanted.request()).values);

  @override
  Future<bool> granted() async {
    for (final p in _wanted) {
      if (!(await p.status).isGranted) return false;
    }
    return true;
  }

  @override
  Future<GlovePermission> requestLocation() async =>
      _merge([await Permission.locationWhenInUse.request()]);

  @override
  Future<bool> openSettings() => openAppSettings();
}
