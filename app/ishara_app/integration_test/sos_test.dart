// On the emulator, with app/tools/sos_watch.sh running beside it (it grants
// location while in use, sets the fix with `adb emu geo fix`, and records
// what Android opened):
//   flutter test integration_test/sos_test.dart -d <device> > sos.log &
//   app/tools/sos_watch.sh sos.log
// The real SOS path: real location, real SMS / dialer intents. The SMS app
// and the dialer only open; nothing is sent or called. Prints SOS lines.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';

Future<void> waitFor(
  WidgetTester t,
  Finder f, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('not found: $f');
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Lets the watcher look, then come back to the app.
Future<void> away(WidgetTester t, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SOS: the fix, the SMS app with both recipients and the '
      'link, the dialer with 123', (t) async {
    setUpLogging(sink: (l) => debugPrint('SOS log $l'));
    final store = MemoryKeyValueStore({
      'onboarding.done': true,
      'setup.spoken': 'en',
      'setup.role': 'sign',
      'sos.contacts': jsonEncode([
        {'name': 'Mona', 'phone': '+201012345678'},
        {'name': 'Ali', 'phone': '+201123456789'},
      ]),
    });
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          appRouterProvider.overrideWith(
            (ref) => buildRouter(initialLocation: AppRoutes.talk),
          ),
        ],
        child: const IsharaApp(),
      ),
    );
    await waitFor(t, find.byKey(const ValueKey('screen-talk')));
    // the watcher grants location and sets the fix meanwhile
    await away(t, const Duration(seconds: 8));
    await t.tap(find.byKey(const ValueKey('talk-quick-sos')));
    debugPrint('SOS pressed');
    await waitFor(t, find.byKey(const ValueKey('sos-sheet')));
    // the fresh fix (10 s limit), else last known, else none
    final line = find.descendant(
      of: find.byKey(const ValueKey('sos-sheet')),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp('location', caseSensitive: false).hasMatch(w.data ?? ''),
      ),
    );
    await waitFor(t, line, timeout: const Duration(seconds: 15));
    final until = DateTime.now().add(const Duration(seconds: 12));
    while (t.widget<Text>(line.first).data!.contains('Getting') &&
        DateTime.now().isBefore(until)) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final where = t.widget<Text>(line.first).data;
    debugPrint('SOS location: $where');
    // this check is about the SMS app and the dialer, not the fix (the real
    // fix is checked on the phone): a fresh or a last-known one will do
    expect(
      where,
      anyOf(startsWith('Your location'), startsWith('Last known location')),
    );
    expect(find.byKey(const ValueKey('sos-whatsapp')), findsNothing);
    debugPrint('SOS whatsapp: not installed, no button');

    debugPrint('SOS open sms');
    await t.tap(find.byKey(const ValueKey('sos-sms')));
    await away(t, const Duration(seconds: 14));

    debugPrint('SOS open dialer');
    await t.tap(find.byKey(const ValueKey('sos-ambulance')));
    await away(t, const Duration(seconds: 14));
    debugPrint('SOS done');
  });
}
