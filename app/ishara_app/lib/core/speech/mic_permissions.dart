import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// The result of asking for the microphone.
enum MicPermission {
  granted,

  /// Refused this time: asking again can show the system prompt.
  denied,

  /// Refused for good ("Don't ask again" / iOS): only the phone's settings
  /// can change it.
  permanentlyDenied,
}

/// What speech → sign needs before listening: the microphone, and on iOS
/// speech recognition.
abstract interface class MicPermissions {
  /// Asks (shows the system prompt when it can).
  Future<MicPermission> request();

  /// The current answer, without asking (never shows a prompt).
  Future<MicPermission> check();

  /// Opens this app's page in the phone's settings.
  Future<bool> openSettings();
}

/// `permission_handler` 13.0.2 (MIT, no network; S6-4). Android:
/// `RECORD_AUDIO`. iOS: microphone and speech recognition.
class PlatformMicPermissions implements MicPermissions {
  const new();

  static List<Permission> get _wanted =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? [Permission.microphone, Permission.speech]
      : [Permission.microphone];

  static MicPermission _merge(Iterable<PermissionStatus> all) {
    if (all.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return MicPermission.permanentlyDenied;
    }
    if (all.every((s) => s.isGranted || s.isLimited)) {
      return MicPermission.granted;
    }
    return MicPermission.denied;
  }

  @override
  Future<MicPermission> request() async =>
      _merge((await _wanted.request()).values);

  @override
  Future<MicPermission> check() async =>
      _merge([for (final p in _wanted) await p.status]);

  @override
  Future<bool> openSettings() => openAppSettings();
}
