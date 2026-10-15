import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:meta/meta.dart';

/// What happened (Phase 0 Firestore model `users/{uid}/activity/{eventId}`).
enum ActivityType {
  /// A pick-the-meaning step was answered.
  quiz,

  /// A "your turn" step ended (passed, or failed after its attempts).
  practice,

  /// A mission reached its result screen.
  missionDone,
}

/// One immutable entry of the Learn activity log. XP, medals, the streak,
/// signs learned and unlocks are all computed from these; no total is ever
/// stored.
///
/// For `missionDone`: [label] is null, [passed] = a medal was earned
/// (accuracy ≥ 80 %, Q-L2), [prob] = the accuracy (0–1), [xp] = the daily
/// challenge bonus (30 the first time that day, else 0, S8-4).
@immutable
class ActivityEvent {
  const new({
    required this.id,
    required this.type,
    required this.moduleId,
    required this.passed,
    required this.xp,
    required this.day,
    required this.at,
    required this.deviceId,
    this.label,
    this.prob,
  });

  /// The shape [toJson] writes.
  static const version = 1;

  /// Reads one entry; null when it isn't a valid version-1 event (a newer
  /// app's event, or damage). Callers keep such entries but don't count
  /// them.
  static ActivityEvent? tryParse(Object? json) {
    if (json is! Map<String, Object?> || json['v'] != version) return null;
    final type = ActivityType.values.asNameMap()[json['type']];
    final id = json['id'];
    final moduleId = json['moduleId'];
    final passed = json['passed'];
    final xp = json['xp'];
    final dayText = json['day'];
    final atText = json['at'];
    final deviceId = json['deviceId'];
    final label = json['label'];
    final prob = json['prob'];
    if (type == null ||
        id is! String ||
        moduleId is! String ||
        passed is! bool ||
        xp is! int ||
        xp < 0 ||
        dayText is! String ||
        atText is! String ||
        deviceId is! String ||
        (label != null && label is! String) ||
        (prob != null && prob is! num)) {
      return null;
    }
    final day = LocalDay.tryParse(dayText);
    final at = DateTime.tryParse(atText);
    if (day == null || at == null) return null;
    if ((type == ActivityType.missionDone) != (label == null)) return null;
    return ActivityEvent(
      id: id,
      type: type,
      moduleId: moduleId,
      passed: passed,
      xp: xp,
      day: day,
      at: at.toUtc(),
      deviceId: deviceId,
      label: label as String?,
      prob: (prob as num?)?.toDouble(),
    );
  }

  final String id;
  final ActivityType type;

  /// The sign (quiz, practice); null for `missionDone`.
  final String? label;

  /// The module, or `daily` for the daily challenge.
  final String moduleId;
  final bool passed;

  /// Practice: the smoothed probability of the label when it fired (Q-L4);
  /// `missionDone`: the accuracy. Null otherwise.
  final double? prob;
  final int xp;

  /// The phone's local day when it happened.
  final LocalDay day;

  /// When it happened (UTC).
  final DateTime at;
  final String deviceId;

  Map<String, Object?> toJson() => {
    'v': version,
    'id': id,
    'type': type.name,
    'label': label,
    'moduleId': moduleId,
    'passed': passed,
    'prob': prob,
    'xp': xp,
    'day': '$day',
    'at': at.toUtc().toIso8601String(),
    'deviceId': deviceId,
  };
}
