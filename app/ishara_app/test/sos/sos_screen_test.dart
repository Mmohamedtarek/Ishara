import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/sos/application/sos_controller.dart';
import 'package:ishara_app/features/sos/data/emergency_contacts_repository.dart';
import 'package:ishara_app/features/sos/data/sos_platform.dart';
import 'package:ishara_app/features/sos/domain/sos_location.dart';
import 'package:ishara_app/features/sos/presentation/emergency_contacts_screen.dart';
import 'package:ishara_app/features/talk/presentation/talk_screen.dart';

import '../support/fake_sos.dart';
import '../support/fake_speech.dart';
import '../support/fake_talk.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

const _nour = {'name': 'Mona', 'phone': '+201012345678'};
const _ali = {'name': 'Ali', 'phone': '+201123456789'};
const _sara = {'name': 'Sara', 'phone': '+442079460958'};

Fix _fixAgo(Duration ago) => Fix(
  latitude: 30.04442,
  longitude: 31.235712,
  accuracyMeters: 12,
  at: clock.now().subtract(ago),
);

class _Talk {
  new({List<Map<String, String>> contacts = const [], FakeLocation? location})
    : sos = SosFakes(location: location ?? FakeLocation()),
      store = MemoryKeyValueStore({
        'setup.spoken': 'en',
        if (contacts.isNotEmpty) 'sos.contacts': jsonEncode(contacts),
      });

  final talk = TalkFakes();
  final SosFakes sos;
  final MemoryKeyValueStore store;

  Future<void> pressSos(WidgetTester t) async {
    addTearDown(rootBundle.clear);
    addTearDown(talk.feed.dispose);
    await pumpScreen(
      t,
      const TalkScreen(),
      harness: Harness(store: store),
      overrides: [
        ...talk.overrides,
        ...sos.overrides,
        speechToTextProvider.overrideWithValue(FakeSpeechToText()),
        micPermissionsProvider.overrideWithValue(
          FakeMicPermissions(current: MicPermission.granted),
        ),
      ],
    );
    await tapIt(t, _key('talk-quick-sos'));
  }
}

/// SOS tests end after the toast and the 10 s locate limit.
void _sosTest(String name, Future<void> Function(WidgetTester t) body) =>
    testWidgets(name, (t) async {
      await body(t);
      await t.pump(const Duration(seconds: 12));
    });

void main() {
  _sosTest('no contacts: call 123 and "Add an emergency contact"; '
      'nothing goes out by itself', (t) async {
    final s = _Talk(location: FakeLocation(fresh: _fixAgo(Duration.zero)));
    await s.pressSos(t);
    expect(_key('sos-ambulance'), findsOneWidget);
    expect(find.text('Call ambulance 123'), findsOneWidget);
    expect(_key('sos-add-contact'), findsOneWidget);
    expect(_key('sos-sms'), findsNothing);
    expect(s.sos.launcher.opened, isEmpty);
    await tapIt(t, _key('sos-ambulance'));
    expect(s.sos.launcher.opened, ['dial 123']);
    await tapIt(t, _key('sos-add-contact'));
    expect(find.text('route:/settings/emergency'), findsOneWidget);
  });

  _sosTest('one contact: SMS with the link, WhatsApp to them, call them; '
      'each its own tap', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(fresh: _fixAgo(Duration.zero)),
    );
    await s.pressSos(t);
    expect(find.text('Your location (±12 m)'), findsOneWidget);
    expect(s.sos.launcher.opened, isEmpty);
    await tapIt(t, _key('sos-sms'));
    expect(s.sos.launcher.opened.single, startsWith('sms +201012345678 | '));
    expect(
      s.sos.launcher.opened.single,
      contains('https://maps.google.com/?q=30.044420,31.235712 (±12 m,'),
    );
    expect(find.text('Send on WhatsApp to Mona'), findsOneWidget);
    await tapIt(t, _key('sos-whatsapp'));
    expect(s.sos.launcher.opened.last, startsWith('whatsapp +201012345678'));
    await tapIt(t, _key('sos-call-0'));
    expect(s.sos.launcher.opened.last, 'dial +201012345678');
  });

  _sosTest('three contacts: the SMS goes to all; WhatsApp asks to whom', (
    t,
  ) async {
    final s = _Talk(
      contacts: [_nour, _ali, _sara],
      location: FakeLocation(fresh: _fixAgo(Duration.zero)),
    );
    await s.pressSos(t);
    await tapIt(t, _key('sos-sms'));
    expect(
      s.sos.launcher.opened.single,
      startsWith('sms +201012345678,+201123456789,+442079460958 | '),
    );
    for (final i in [0, 1, 2]) {
      expect(_key('sos-call-$i'), findsOneWidget);
    }
    await tapIt(t, _key('sos-whatsapp'));
    expect(_key('sos-pick'), findsOneWidget);
    await tapIt(t, _key('sos-pick-1'));
    expect(s.sos.launcher.opened.last, startsWith('whatsapp +201123456789'));
  });

  _sosTest('permission denied: says so, SOS still works (no location)', (
    t,
  ) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(access: LocationAccess.denied),
    );
    await s.pressSos(t);
    expect(_key('sos-location-off'), findsOneWidget);
    expect(
      find.text(
        "Couldn't get your location. You can still send a message or "
        'call.',
      ),
      findsOneWidget,
    );
    await tapIt(t, _key('sos-sms'));
    expect(
      s.sos.launcher.opened.single,
      "sms +201012345678 | I need help. I couldn't get my location.",
    );
  });

  _sosTest('no fresh fix: the last known one with its age', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(last: _fixAgo(const Duration(minutes: 4))),
    );
    await s.pressSos(t);
    expect(
      find.text('Last known location, about 4 minutes ago (±12 m)'),
      findsOneWidget,
    );
    expect(_key('sos-location-stale'), findsNothing, reason: 'under 1 hour');
  });

  _sosTest('a last known position 3 hours old: told in hours, with "may be '
      'out of date"', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(last: _fixAgo(const Duration(hours: 3))),
    );
    await s.pressSos(t);
    expect(
      find.text('Last known location, about 3 hours ago (±12 m)'),
      findsOneWidget,
    );
    expect(find.text('This location may be out of date.'), findsOneWidget);
  });

  _sosTest('3 days old: told in days', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(last: _fixAgo(const Duration(days: 3))),
    );
    await s.pressSos(t);
    expect(
      find.text('Last known location, about 3 days ago (±12 m)'),
      findsOneWidget,
    );
    expect(_key('sos-location-stale'), findsOneWidget);
  });

  _sosTest('no SMS app: says so and offers Copy message (the SMS text, '
      'with a toast)', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(fresh: _fixAgo(Duration.zero)),
    )..sos.launcher.smsApp = false;
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await s.pressSos(t);
    expect(_key('sos-open-failed'), findsNothing);
    await tapIt(t, _key('sos-sms'));
    expect(find.text("Couldn't open the SMS app."), findsOneWidget);
    await tapIt(t, _key('sos-copy'));
    expect(copied, startsWith('I need help. My location: https://maps.'));
    expect(find.text('Message copied'), findsOneWidget);
  });

  _sosTest('no phone app: says so; a call that opens clears it', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(fresh: _fixAgo(Duration.zero)),
    )..sos.launcher.phoneApp = false;
    await s.pressSos(t);
    await tapIt(t, _key('sos-ambulance'));
    expect(find.text("Couldn't open the phone app."), findsOneWidget);
    expect(_key('sos-copy'), findsOneWidget);
    s.sos.launcher.phoneApp = true;
    await tapIt(t, _key('sos-call-0'));
    expect(_key('sos-open-failed'), findsNothing);
  });

  _sosTest('WhatsApp missing: no WhatsApp button', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(fresh: _fixAgo(Duration.zero)),
    )..sos.launcher.whatsAppInstalled = false;
    await s.pressSos(t);
    expect(_key('sos-sms'), findsOneWidget);
    expect(_key('sos-whatsapp'), findsNothing);
  });

  _sosTest('D23 is spoken before the location arrives; the send button '
      'waits for it, calls never do', (t) async {
    final s = _Talk(
      contacts: [_nour],
      location: FakeLocation(
        fresh: _fixAgo(Duration.zero),
        freshDelay: const Duration(seconds: 5),
      ),
    );
    await s.pressSos(t);
    expect(s.talk.tts.spoken, ['I need help, please.']);
    expect(
      s.sos.location.accuracyOffers,
      0,
      reason: 'SOS never shows a system dialog',
    );
    expect(find.text('Getting your location…'), findsOneWidget);
    await tapIt(t, _key('sos-sms'));
    expect(s.sos.launcher.opened, isEmpty, reason: 'still locating');
    await tapIt(t, _key('sos-call-0'));
    expect(s.sos.launcher.opened, ['dial +201012345678']);
    await t.pump(const Duration(seconds: 5));
    await settle(t);
    expect(find.text('Your location (±12 m)'), findsOneWidget);
  });

  group('emergency contacts', () {
    Future<(Harness, FakeLocation)> pump(
      WidgetTester t, {
      LocationAccess access = LocationAccess.denied,
      List<Map<String, String>> contacts = const [],
    }) async {
      addTearDown(rootBundle.clear);
      final location = FakeLocation(access: access);
      final sos = SosFakes(
        location: location,
        launcher: FakeLauncher(
          picked: (name: 'Mona Ali', number: '010 1234 5678'),
        ),
      );
      final h = await pumpScreen(
        t,
        const EmergencyContactsScreen(),
        harness: Harness(
          store: MemoryKeyValueStore({
            if (contacts.isNotEmpty) 'sos.contacts': jsonEncode(contacts),
          }),
        ),
        overrides: sos.overrides,
      );
      return (h, location);
    }

    EmergencyContactsRepository repo(WidgetTester t) =>
        ProviderScope.containerOf(
          t.element(find.byType(EmergencyContactsScreen)),
        ).read(emergencyContactsRepositoryProvider);

    testWidgets('typed: validated, stored in E.164; the first one asks for '
        'location once', (t) async {
      final (_, location) = await pump(t);
      await tapIt(t, _key('emergency-add'));
      await t.enterText(_key('contact-name'), 'Mona');
      await t.enterText(_key('contact-phone'), '0131234567');
      await tapIt(t, _key('contact-save'));
      expect(
        find.text(
          'Enter an Egyptian number (01…) or an international one '
          'starting with +.',
        ),
        findsOneWidget,
      );
      await t.enterText(_key('contact-phone'), '010 1234 5678');
      await tapIt(t, _key('contact-save'));
      expect(
        repo(t).contacts.single,
        const EmergencyContact(name: 'Mona', phone: '+201012345678'),
      );
      expect(_key('location-ask'), findsOneWidget);
      location.access = LocationAccess.granted; // the user allows it
      await tapIt(t, _key('location-allow'));
      expect(location.requests, 1);
      expect(location.accuracyOffers, 1, reason: 'the calm moment');
    });

    testWidgets('location already allowed: the first contact only offers '
        'Location Accuracy (no explanation dialog)', (t) async {
      final (_, location) = await pump(t, access: LocationAccess.granted);
      await tapIt(t, _key('emergency-add'));
      await t.enterText(_key('contact-name'), 'Mona');
      await t.enterText(_key('contact-phone'), '01012345678');
      await tapIt(t, _key('contact-save'));
      expect(_key('location-ask'), findsNothing);
      expect(location.accuracyOffers, 1);
    });

    testWidgets('picked from the phone (no permission); at most 3', (t) async {
      final (_, location) = await pump(
        t,
        access: LocationAccess.granted,
        contacts: [_ali, _sara],
      );
      await tapIt(t, _key('emergency-add'));
      await tapIt(t, _key('contact-pick'));
      await tapIt(t, _key('contact-save'));
      expect(
        repo(t).contacts.last,
        const EmergencyContact(name: 'Mona Ali', phone: '+201012345678'),
      );
      expect(location.requests, 0, reason: 'not the first contact');
      expect(location.accuracyOffers, 0);
      expect(_key('emergency-add'), findsNothing);
      expect(_key('emergency-full'), findsOneWidget);
    });

    testWidgets('edit and remove', (t) async {
      await pump(t, contacts: [_ali]);
      await tapIt(t, _key('emergency-contact-0'));
      await t.enterText(_key('contact-name'), 'Ali Hassan');
      await tapIt(t, _key('contact-save'));
      expect(repo(t).contacts.single.name, 'Ali Hassan');
      await tapIt(t, _key('emergency-contact-0'));
      await tapIt(t, _key('contact-remove'));
      expect(repo(t).contacts, isEmpty);
    });
  });
}
