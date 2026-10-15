import 'dart:async';
import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A position from the phone.
@immutable
class Fix {
  const new({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.at,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// When the phone measured it.
  final DateTime at;
}

/// Where SOS reads the position from (the phone's location service; a fake
/// in tests). Read only when SOS is pressed: no background location.
abstract interface class LocationSource {
  /// A fresh, precise fix; null if there is none within [limit].
  Future<Fix?> current({required Duration limit});

  /// The phone's last known position, if any.
  Future<Fix?> lastKnown();
}

/// The unit a last known position's age is told in.
enum AgeUnit { minutes, hours, days }

/// How the position was found.
enum FixKind {
  /// Measured now.
  fresh,

  /// The phone's last known position (shown with its age).
  lastKnown,

  /// None (no permission, location off, or no fix at all).
  none,
}

@immutable
class SosLocation {
  const new(this.kind, [this.fix]);

  final FixKind kind;
  final Fix? fix;

  /// How old the fix is at [now] (null without one).
  Duration? age(DateTime now) {
    final f = fix;
    return f == null ? null : now.difference(f.at);
  }
}

/// Q-T4 phase 1: a fresh precise fix within 10 s, else the last known
/// position, else none. Never throws: SOS must go on without a position.
abstract final class SosLocator {
  static const freshLimit = Duration(seconds: 10);

  /// The last known position is the phone's cache: it answers at once.
  static const lastKnownLimit = Duration(seconds: 2);

  static Future<SosLocation> locate(LocationSource source) async {
    try {
      final fresh = await source
          .current(limit: freshLimit)
          .timeout(freshLimit + const Duration(seconds: 1));
      if (fresh != null) return SosLocation(FixKind.fresh, fresh);
    } on Object {
      // no permission, location off, timeout: try the last known one
    }
    try {
      // a stalled platform call never keeps the SMS button waiting
      final last = await source.lastKnown().timeout(lastKnownLimit);
      if (last != null) return SosLocation(FixKind.lastKnown, last);
    } on Object {
      // nothing more to try
    }
    return const SosLocation(FixKind.none);
  }

  /// `https://maps.google.com/?q=lat,lng` (6 decimals, about 0.1 m).
  static String mapLink(Fix f) =>
      'https://maps.google.com/?q='
      '${f.latitude.toStringAsFixed(6)},${f.longitude.toStringAsFixed(6)}';

  /// Whole metres, at least 1.
  static int accuracy(Fix f) =>
      f.accuracyMeters.isFinite && f.accuracyMeters >= 1
      ? f.accuracyMeters.round()
      : 1;

  /// The age in whole minutes, rounded (for "about 4 minutes ago").
  static int ageMinutes(Duration age) =>
      age.isNegative ? 0 : math.max(1, (age.inSeconds / 60).round());

  /// How the age is told: minutes under 1 hour, hours under 48 hours, then
  /// days (user, step 9 review), each rounded, at least 1.
  static (AgeUnit, int) ageIn(Duration age) {
    if (age < const Duration(hours: 1)) {
      return (AgeUnit.minutes, ageMinutes(age));
    }
    if (age < const Duration(hours: 48)) {
      return (AgeUnit.hours, math.max(1, (age.inMinutes / 60).round()));
    }
    return (AgeUnit.days, math.max(2, (age.inHours / 24).round()));
  }

  /// A last known position older than 1 hour may be out of date.
  static bool stale(Duration age) => age > const Duration(hours: 1);
}
