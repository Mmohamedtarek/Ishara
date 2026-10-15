import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/features/history/domain/history.dart';

TalkMessage _m(
  String text,
  DateTime at, {
  String? conv,
  MessageSide side = MessageSide.me,
}) => TalkMessage(side: side, text: text, at: at, conversation: conv);

void main() {
  group('grouping (S9-4, S9-5)', () {
    test('one conversation per id, newest first, messages in order', () {
      final all = [
        _m('a', DateTime(2026, 10, 14, 9), conv: 'c1'),
        _m('b', DateTime(2026, 10, 14, 9, 1), conv: 'c1'),
        _m('c', DateTime(2026, 10, 14, 11), conv: 'c2'),
      ];
      final g = History.group(all);
      expect([for (final c in g) c.key], ['c2', 'c1']);
      expect(g.last.messages.map((m) => m.text), ['a', 'b']);
      expect(g.last.start, DateTime(2026, 10, 14, 9));
      expect(g.last.end, DateTime(2026, 10, 14, 9, 1));
    });

    test('older messages (no id) group per local day', () {
      final g = History.group([
        _m('a', DateTime(2026, 10, 13, 23, 59)),
        _m('b', DateTime(2026, 10, 14, 0, 1)),
        _m('c', DateTime(2026, 10, 14, 8)),
      ]);
      expect([for (final c in g) c.messages.length], [2, 1]);
      expect(g.first.key, 'day:2026-10-14');
    });

    test('no messages, no conversations', () {
      expect(History.group(const []), isEmpty);
    });
  });

  group('title day marker (Q-B4)', () {
    test('today, yesterday, a date, across midnight', () {
      final now = DateTime(2026, 10, 15, 0, 5);
      expect(
        History.marker(DateTime(2026, 10, 15, 0, 1), now),
        DayMarker.today,
      );
      expect(
        History.marker(DateTime(2026, 10, 14, 23, 59), now),
        DayMarker.yesterday,
      );
      expect(History.marker(DateTime(2026, 10, 13, 12), now), DayMarker.date);
    });

    test('a timezone change: titles use the wall time stored with each '
        'message (what the phone showed then)', () {
      // a message at 23:30 Cairo time stays "yesterday" at 00:10 the next
      // day even if the phone moved to another zone meanwhile: the stored
      // time is the wall time, not an instant
      final at = DateTime.parse('2026-10-14T23:30:00.000');
      expect(at.isUtc, isFalse);
      expect(
        History.marker(at, DateTime(2026, 10, 15, 0, 10)),
        DayMarker.yesterday,
      );
    });

    test("Egypt's 23-hour day: calendar days, not 24 hours", () {
      // 25 Apr 00:30 minus 24 h is still "yesterday" by the calendar
      expect(
        History.marker(
          DateTime(2026, 4, 24, 0, 40),
          DateTime(2026, 4, 25, 0, 30),
        ),
        DayMarker.yesterday,
      );
    });
  });

  group('search (Arabic forms and diacritics, case)', () {
    final conv = Conversation(
      key: 'c',
      messages: [
        _m('Hello, the Doctor will call', DateTime(2026, 10, 14, 9)),
        _m('أهلاً، الدكتور هيتصل بيك', DateTime(2026, 10, 14, 9, 1)),
        _m('محتاج مساعدة من فضلك', DateTime(2026, 10, 14, 9, 2)),
        _m('أنا جعانة', DateTime(2026, 10, 14, 9, 3)),
        _m('مستشفى', DateTime(2026, 10, 14, 9, 4)),
      ],
    );
    String? hit(String q) => History.match(conv, q)?.text;

    test('English: case and punctuation', () {
      expect(hit('doctor'), 'Hello, the Doctor will call');
      expect(hit('HELLO'), 'Hello, the Doctor will call');
      expect(hit('nurse'), isNull);
    });

    test('Arabic: diacritics, hamza / alef forms, ة / ه, ى / ي', () {
      expect(hit('اهلا'), 'أهلاً، الدكتور هيتصل بيك'); // أ → ا, tanween
      expect(hit('إهلا'), 'أهلاً، الدكتور هيتصل بيك');
      expect(hit('مساعده'), 'محتاج مساعدة من فضلك'); // ة / ه
      expect(hit('جعانه'), 'أنا جعانة');
      expect(hit('مستشفي'), 'مستشفى'); // ى / ي
      expect(hit('انا'), 'أنا جعانة');
    });

    test('an empty query matches with the first sentence; search lists '
        'matching conversations only', () {
      expect(hit(''), 'Hello, the Doctor will call');
      final other = Conversation(
        key: 'd',
        messages: [_m('yes', DateTime(2026, 10, 14, 10))],
      );
      expect(History.search([conv, other], 'yes').map((e) => e.$1.key), ['d']);
      expect(History.search([conv, other], ''), hasLength(2));
    });
  });
}
