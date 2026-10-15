// Run in Egypt's time zone (CI does):
//   TZ=Africa/Cairo flutter test test/learn/domain/egypt_time_zone_test.dart
// In any other time zone it is skipped (the normal suite runs it that way).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/features/learn/domain/learn_progress.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';

void main() {
  final cairo = Platform.environment['TZ'] == 'Africa/Cairo';
  final skip = cairo ? null : 'needs TZ=Africa/Cairo';

  // The phone reads real instants in local time, as the app's clock does.
  LocalDay dayAt(DateTime utc) => LocalDay.of(utc.toLocal());

  test('spring forward (24 Apr 2026, 00:00 → 01:00): missions 15 minutes apart '
      'across the switch are on two days in a row', () {
    final a = DateTime.utc(2026, 4, 23, 21, 50); // 23:50 EET
    final b = DateTime.utc(2026, 4, 23, 22, 5); // 01:05 EEST
    expect(a.toLocal().timeZoneName, 'EET');
    expect(b.toLocal().timeZoneName, 'EEST');
    expect(dayAt(a), const LocalDay(2026, 4, 23));
    expect(dayAt(b), const LocalDay(2026, 4, 24));
    expect(LearnProgress.streakOn({dayAt(a), dayAt(b)}, dayAt(b)), 2);
  }, skip: skip);

  test('the day after the 23-hour day: "24 h earlier" would skip 24 Apr, the '
      'calendar day before does not', () {
    final now = DateTime.utc(2026, 4, 24, 21, 30); // 25 Apr 00:30 EEST
    final today = dayAt(now);
    expect(today, const LocalDay(2026, 4, 25));
    // what a "now − 24 h" rule would call yesterday
    expect(
      dayAt(now.subtract(const Duration(hours: 24))),
      const LocalDay(2026, 4, 23),
    );
    expect(today.previous, const LocalDay(2026, 4, 24));
    expect(
      LearnProgress.streakOn({
        const LocalDay(2026, 4, 23),
        const LocalDay(2026, 4, 24),
        today,
      }, today),
      3,
    );
  }, skip: skip);

  test('fall back (29 Oct 2026, 24:00 → 23:00): both 23:30s are 29 Oct, the '
      'streak goes on to 30 Oct', () {
    final first = DateTime.utc(2026, 10, 29, 20, 30); // 23:30 EEST
    final second = DateTime.utc(2026, 10, 29, 21, 30); // 23:30 EET
    final next = DateTime.utc(2026, 10, 29, 22, 30); // 30 Oct 00:30 EET
    expect(first.toLocal().timeZoneName, 'EEST');
    expect(second.toLocal().timeZoneName, 'EET');
    expect(dayAt(first), const LocalDay(2026, 10, 29));
    expect(dayAt(second), const LocalDay(2026, 10, 29));
    expect(dayAt(next), const LocalDay(2026, 10, 30));
    expect(LearnProgress.streakOn({dayAt(first), dayAt(next)}, dayAt(next)), 2);
  }, skip: skip);
}
