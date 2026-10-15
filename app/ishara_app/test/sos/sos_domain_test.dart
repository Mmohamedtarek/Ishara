import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ishara_app/features/sos/application/sos_message.dart';
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/phone_number.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:ishara_app/l10n/gen/app_localizations.dart';

import '../support/fake_sos.dart';

const _link = 'https://maps.google.com/?q=30.044420,31.235712';

final _fix = Fix(
  latitude: 30.044420,
  longitude: 31.235712,
  accuracyMeters: 12.4,
  at: DateTime(2026, 10, 14, 18, 2),
);

void main() {
  group('phone numbers (Q-T4: Egyptian and international, E.164)', () {
    test('Egyptian mobiles as people write them', () {
      for (final (input, e164) in [
        ('01012345678', '+201012345678'),
        ('011 2345 6789', '+201123456789'),
        ('012-3456-7890', '+201234567890'),
        ('015 1234 5678', '+201512345678'),
        ('+20 10 1234 5678', '+201012345678'),
        ('00201012345678', '+201012345678'),
        ('٠١٠١٢٣٤٥٦٧٨', '+201012345678'), // Arabic-Indic digits
        ('+20 2 12345678', '+20212345678'), // Cairo landline
      ]) {
        expect(PhoneNumber.toE164(input), e164, reason: input);
      }
    });

    test('other international numbers in + form', () {
      expect(PhoneNumber.toE164('+44 20 7946 0958'), '+442079460958');
      expect(PhoneNumber.toE164('+1 (415) 555-0100'), '+14155550100');
    });

    test('refused: wrong Egyptian prefixes, local landlines, too short / long, '
        'letters', () {
      for (final bad in [
        '01312345678', // no 013 network
        '0101234567', // 10 digits
        '010123456789', // 12 digits
        '0212345678', // a local landline (only 01x locally)
        '+201312345678',
        '+0123456789',
        '+1234567', // too short
        '+1234567890123456', // 16 digits
        '12345678',
        'abc',
        '',
      ]) {
        expect(PhoneNumber.toE164(bad), isNull, reason: bad);
        expect(PhoneNumber.isValid(bad), isFalse);
      }
    });

    test('wa.me digits', () {
      expect(PhoneNumber.waDigits('+201012345678'), '201012345678');
    });
  });

  group('the location order (Q-T4 phase 1)', () {
    test('a fresh fix first (10 s limit)', () async {
      final f = FakeLocation(fresh: _fix, last: _fix);
      final w = await SosLocator.locate(f);
      expect(w.kind, FixKind.fresh);
      expect(f.calls, ['current 10s']);
    });

    test('no fresh fix in time: the last known one, with its age', () {
      fakeAsync((async) {
        final old = Fix(
          latitude: 1,
          longitude: 2,
          accuracyMeters: 30,
          at: DateTime(2026, 10, 14, 17, 58),
        );
        final f = FakeLocation(last: old)..freshNever = true;
        SosLocation? got;
        SosLocator.locate(f).then((w) => got = w).ignore();
        async.elapse(const Duration(seconds: 10));
        expect(got, isNull, reason: 'still waiting at 10 s');
        async.elapse(const Duration(seconds: 2));
        expect(got!.kind, FixKind.lastKnown);
        final age = got!.age(DateTime(2026, 10, 14, 18, 2));
        expect(SosLocator.ageMinutes(age!), 4);
      });
    });

    test('age: minutes under 1 h, hours under 48 h, then days; stale over '
        '1 h (step 9 review)', () {
      Duration m(int n) => Duration(minutes: n);
      expect(SosLocator.ageIn(m(59)), (AgeUnit.minutes, 59));
      expect(SosLocator.ageIn(m(61)), (AgeUnit.hours, 1));
      expect(SosLocator.ageIn(m(150)), (AgeUnit.hours, 3));
      expect(SosLocator.ageIn(const Duration(hours: 47)), (AgeUnit.hours, 47));
      expect(SosLocator.ageIn(const Duration(hours: 48)), (AgeUnit.days, 2));
      expect(SosLocator.ageIn(const Duration(days: 5)), (AgeUnit.days, 5));
      expect(SosLocator.stale(m(60)), isFalse);
      expect(SosLocator.stale(m(61)), isTrue);
    });

    test('age texts in both languages (ICU plurals; drafts O17 / O18)', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(
        en.sosLocOldHours(1, 12),
        'Last known location, about 1 hour ago (±12 m)',
      );
      expect(
        en.sosLocOldDays(3, 12),
        'Last known location, about 3 days ago (±12 m)',
      );
      expect(
        [
          for (final n in [1, 2, 3, 11]) ar.sosLocOldHours(n, 12),
        ],
        [
          'آخر مكان معروف، من حوالي ساعة (±12 م)',
          'آخر مكان معروف، من حوالي ساعتين (±12 م)',
          'آخر مكان معروف، من حوالي 3 ساعات (±12 م)',
          'آخر مكان معروف، من حوالي 11 ساعة (±12 م)',
        ],
      );
      expect(
        [
          for (final n in [2, 3, 11]) ar.sosLocOldDays(n, 12),
        ],
        [
          'آخر مكان معروف، من حوالي يومين (±12 م)',
          'آخر مكان معروف، من حوالي 3 أيام (±12 م)',
          'آخر مكان معروف، من حوالي 11 يوم (±12 م)',
        ],
      );
    });

    test('a stalled last-known lookup ends too: none after about 13 s, so '
        'SMS never stays busy', () {
      fakeAsync((async) {
        final f = FakeLocation()
          ..freshNever = true
          ..lastNever = true;
        SosLocation? got;
        SosLocator.locate(f).then((w) => got = w).ignore();
        async.elapse(const Duration(seconds: 12));
        expect(got, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(got!.kind, FixKind.none);
      });
    });

    test('nothing at all (no permission): none, never an error', () async {
      final w = await SosLocator.locate(
        FakeLocation(fresh: _fix, last: _fix, access: LocationAccess.denied),
      );
      expect(w.kind, FixKind.none);
      expect(w.fix, isNull);
      expect(w.age(DateTime.now()), isNull);
    });

    test('a failing location service falls through too', () async {
      final w = await SosLocator.locate(_Throwing());
      expect(w.kind, FixKind.none);
    });

    test('link, accuracy and age helpers', () {
      expect(
        SosLocator.mapLink(_fix),
        'https://maps.google.com/?q=30.044420,31.235712',
      );
      expect(SosLocator.accuracy(_fix), 12);
      expect(
        SosLocator.accuracy(
          Fix(
            latitude: 0,
            longitude: 0,
            accuracyMeters: double.nan,
            at: DateTime(2026),
          ),
        ),
        1,
      );
      expect(SosLocator.ageMinutes(const Duration(seconds: 89)), 1);
      expect(
        SosLocator.ageMinutes(const Duration(seconds: 20)),
        1,
        reason: 'never "about 0 minutes ago"',
      );
      expect(SosLocator.ageMinutes(const Duration(seconds: -5)), 0);
    });
  });

  group('the message (draft O14 / O15), both languages', () {
    setUpAll(() async {
      await initializeDateFormatting('en');
      await initializeDateFormatting('ar');
    });
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));

    test('with a location: link, ±accuracy, the fix time', () {
      final w = SosLocation(FixKind.fresh, _fix);
      final now = DateTime(2026, 10, 14, 18, 3);
      expect(
        sosMessage(en, w, 'en', now: now),
        'I need help. My location: $_link (±12 m, 18:02)',
      );
      expect(
        sosMessage(ar, w, 'ar', now: now),
        'محتاج مساعدة. مكاني: $_link (±12 م، 18:02)',
      );
    });

    test('a fix from another day carries its date (never reads as '
        "today's)", () {
      final w = SosLocation(FixKind.lastKnown, _fix);
      final now = DateTime(2026, 10, 15, 9);
      final m = sosMessage(en, w, 'en', now: now);
      expect(m, 'I need help. My location: $_link (±12 m, Oct 14, 18:02)');
      expect(sosMessage(ar, w, 'ar', now: now), contains('18:02'));
      expect(sosMessage(ar, w, 'ar', now: now), contains('14'));
    });

    test('without one', () {
      const w = SosLocation(FixKind.none);
      expect(
        sosMessage(en, w, 'en'),
        "I need help. I couldn't get my location.",
      );
      expect(sosMessage(ar, w, 'ar'), 'محتاج مساعدة. مقدرتش أجيب مكاني.');
    });
  });

  test('launch links: every recipient in the SMS, the message encoded', () {
    final sms = PhoneSosLauncher.smsUri([
      '+201012345678',
      '+201123456789',
    ], 'I need help. https://maps.google.com/?q=1,2');
    expect(
      sms.toString(),
      'sms:+201012345678,+201123456789?body=I%20need%20help.%20https%3A%2F%2F'
      'maps.google.com%2F%3Fq%3D1%2C2',
    );
    expect(PhoneSosLauncher.telUri('123').toString(), 'tel:123');
    expect(
      PhoneSosLauncher.waUri('+201012345678', 'hi there').toString(),
      'https://wa.me/201012345678?text=hi%20there',
    );
  });
}

class _Throwing implements LocationSource {
  @override
  Future<Fix?> current({required Duration limit}) =>
      Future.error(StateError('off'));

  @override
  Future<Fix?> lastKnown() => Future.error(StateError('off'));
}
