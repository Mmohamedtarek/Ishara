import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';
import 'package:ishara_app/features/learn/domain/activity_event.dart';
import 'package:ishara_app/features/learn/domain/local_day.dart';
import 'package:ishara_app/features/learn/presentation/learn_screen.dart';

import '../support/fake_learn.dart';
import '../support/screen_harness.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// Learn on a phone whose log already holds [events].
Future<Harness> _pump(
  WidgetTester t, {
  List<ActivityEvent> events = const [],
  AppLanguage language = AppLanguage.en,
  bool signedIn = false,
}) async {
  addTearDown(rootBundle.clear);
  final rig = LearnRig();
  addTearDown(rig.dispose);
  await rig.kv.setString(
    LocalActivityRepository.kEvents,
    jsonEncode([for (final e in events) e.toJson()]),
  );
  final auth = FakeAuthRepository(delay: Duration.zero);
  if (signedIn) {
    await auth.createAccount(email: 'a@b.co', password: 'secret123', name: 'A');
  }
  return await pumpScreen(
    t,
    const LearnScreen(),
    language: language,
    harness: Harness(glove: rig.glove, store: rig.kv, auth: auth),
    overrides: rig.screenOverrides,
  );
}

var _n = 0;
ActivityEvent _ev(
  ActivityType type,
  LocalDay day, {
  String? label,
  String module = 'start',
  bool passed = true,
}) => ActivityEvent(
  id: 'e${_n++}',
  type: type,
  label: label,
  moduleId: module,
  passed: passed,
  xp: switch (type) {
    ActivityType.quiz => 10,
    ActivityType.practice => 15,
    ActivityType.missionDone => 0,
  },
  day: day,
  at: DateTime.utc(2026),
  deviceId: 'dev',
);

/// "Start here" finished yesterday and today (a medal each time).
List<ActivityEvent> _startDone() {
  final today = LocalDay.of(clock.now());
  return [
    for (final l in ['hello', 'thanks', 'please', 'yes', 'no']) ...[
      _ev(ActivityType.quiz, today.previous, label: l),
      _ev(ActivityType.practice, today.previous, label: l),
    ],
    _ev(ActivityType.missionDone, today.previous),
    _ev(ActivityType.missionDone, today),
  ];
}

void main() {
  testWidgets('a new guest: zeros, the guest banner, Save opens sign-up', (
    t,
  ) async {
    await _pump(t);
    expect(_key('learn-guest'), findsOneWidget);
    for (final k in ['learn-xp', 'learn-signs', 'learn-medals']) {
      expect(
        find.descendant(of: _key(k), matching: find.text('0')),
        findsOneWidget,
        reason: k,
      );
    }
    expect(
      find.descendant(of: _key('learn-streak'), matching: find.text('0')),
      findsOneWidget,
    );
    await tapIt(t, _key('learn-guest-save'));
    expect(find.text('route:/auth?mode=signup'), findsOneWidget);
  });

  testWidgets('signing in while Learn is open hides the banner (live)', (
    t,
  ) async {
    final h = await _pump(t);
    expect(_key('learn-guest'), findsOneWidget);
    await t.runAsync(
      () => h.auth.createAccount(
        email: 'a@b.co',
        password: 'secret123',
        name: 'A',
      ),
    );
    await settle(t);
    expect(_key('learn-guest'), findsNothing);
  });

  testWidgets('signed in: no guest banner', (t) async {
    await _pump(t, signedIn: true);
    expect(_key('learn-guest'), findsNothing);
  });

  testWidgets('real numbers from the log: XP, signs learned, medals, streak', (
    t,
  ) async {
    await _pump(t, events: _startDone());
    expect(
      find.descendant(of: _key('learn-xp'), matching: find.text('125')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _key('learn-signs'), matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _key('learn-medals'), matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _key('learn-streak'), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('locked module: the prototype text, a toast, no mission; an '
      'open one starts its mission', (t) async {
    await _pump(t);
    expect(
      find.descendant(
        of: _key('learn-module-numbers'),
        matching: find.text('Finish the module above to unlock'),
      ),
      findsOneWidget,
    );
    await tapIt(t, _key('learn-module-numbers'));
    expect(find.textContaining('route:'), findsNothing);
    expect(find.text('Finish the module above to unlock'), findsNWidgets(5));
    await t.pump(const Duration(seconds: 3));
    await tapIt(t, _key('learn-module-start'));
    expect(find.text('route:/mission/start'), findsOneWidget);
  });

  testWidgets('after "Start here": Numbers opens, words from signs.json', (
    t,
  ) async {
    await _pump(t, events: _startDone());
    expect(find.text('One, Two, Three, Four, Five'), findsOneWidget);
    await tapIt(t, _key('learn-module-numbers'));
    expect(find.text('route:/mission/numbers'), findsOneWidget);
  });

  testWidgets('daily challenge: "5 signs", +30; done today after one', (
    t,
  ) async {
    await _pump(t);
    expect(find.text('5 signs · keep your streak'), findsOneWidget);
    await tapIt(t, _key('learn-daily'));
    expect(find.text('route:/mission/daily'), findsOneWidget);
  });

  testWidgets('daily done today', (t) async {
    await _pump(
      t,
      events: [
        _ev(
          ActivityType.missionDone,
          LocalDay.of(clock.now()),
          module: 'daily',
        ),
      ],
    );
    expect(find.text('Done for today · come back tomorrow'), findsOneWidget);
  });

  testWidgets('TalkBack: modules, stats and the streak are labelled', (
    t,
  ) async {
    final sem = t.ensureSemantics();
    await _pump(t, events: _startDone());
    expect(
      find.bySemanticsLabel(
        'Start here. Your first 5 signs: hello, thank you, please, yes, no. '
        '5 of 5 passed. +125 XP',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'People. Finish the module above to unlock. 0 of 5 passed. +125 XP',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('125 XP'), findsOneWidget);
    expect(find.bySemanticsLabel('5 signs learned'), findsOneWidget);
    expect(find.bySemanticsLabel('2 days'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('Arabic: texts, words and labels in Arabic', (t) async {
    final sem = t.ensureSemantics();
    await _pump(t, language: AppLanguage.ar, events: _startDone());
    expect(find.text('تعلّم الإشارات'), findsOneWidget);
    expect(find.text('واحد، اتنين، تلاتة، أربعة، خمسة'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^الناس\. خلّص الوحدة اللي فوق')),
      findsOneWidget,
    );
    sem.dispose();
  });
}
