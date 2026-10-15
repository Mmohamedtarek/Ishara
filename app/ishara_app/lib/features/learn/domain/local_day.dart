import 'package:meta/meta.dart';

/// A calendar day on the phone's own clock, written `yyyy-mm-dd` (the
/// activity log's `day`).
///
/// Day arithmetic is calendar arithmetic, never "24 hours earlier" on the
/// local clock: Egypt's daylight-saving switches happen at midnight (a day of
/// 23 or 25 hours), and a local "now − 24 h" would then skip or repeat a day.
@immutable
class LocalDay implements Comparable<LocalDay> {
  const new(this.year, this.month, this.day);

  /// The day of [local], a wall-clock time on the phone (`DateTime.now()`).
  factory of(DateTime local) => LocalDay(local.year, local.month, local.day);

  factory _fromUtc(DateTime d) => LocalDay(d.year, d.month, d.day);

  /// `yyyy-mm-dd`, or null for anything else (including impossible dates).
  static LocalDay? tryParse(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (m == null) return null;
    final d = LocalDay(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    final check = d._utc;
    return check.year == d.year && check.month == d.month && check.day == d.day
        ? d
        : null;
  }

  final int year;
  final int month;
  final int day;

  // A UTC date has no daylight saving: adding a day is always one day.
  DateTime get _utc => DateTime.utc(year, month, day);

  LocalDay get previous =>
      LocalDay._fromUtc(_utc.subtract(const Duration(days: 1)));

  LocalDay get next => LocalDay._fromUtc(_utc.add(const Duration(days: 1)));

  @override
  int compareTo(LocalDay other) => _utc.compareTo(other._utc);

  bool isBefore(LocalDay other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDay &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
