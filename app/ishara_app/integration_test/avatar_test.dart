// On a device / emulator (WebView + WebGL):
//   flutter test integration_test/avatar_test.dart -d emulator-5554
// The real avatar page: loads offline from the loopback server, reaches
// ready, plays every sign of the library to its end, and reports the frame
// rate. Prints one AVATAR line per result for the step record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ishara_app/app.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_events.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/router/app_router.dart';
import 'package:ishara_app/core/router/app_routes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the avatar runs: ready, every sign, frame rate', (t) async {
    setUpLogging(sink: (l) => debugPrint('AVATAR log $l'));
    final container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWith(
          (ref) => buildRouter(initialLocation: AppRoutes.signPreview),
        ),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(container: container, child: const IsharaApp()),
    );

    final rt = await _until(
      t,
      () => container.read(avatarRuntimeProvider).value,
      const Duration(seconds: 20),
      'runtime',
    );
    final c = rt.controller;
    final events = <AvatarEvent>[];
    final sub = c.events.listen(events.add);
    addTearDown(sub.cancel);
    final raw = rt.surface.messages.listen((m) => debugPrint('AVATAR msg $m'));
    addTearDown(raw.cancel);

    final sw = Stopwatch()..start();
    await _until(
      t,
      () => c.status.value != AvatarStatus.loading ? c.status.value : null,
      const Duration(seconds: 90),
      'avatar ready',
    );
    final errors = [
      for (final e in events.whereType<AvatarError>()) '${e.code}:${e.message}',
    ];
    debugPrint(
      'AVATAR ready_ms=${sw.elapsedMilliseconds} '
      'status=${c.status.value.name} errors=$errors',
    );
    expect(c.status.value, AvatarStatus.ready);

    // Every sign plays to its end, with its own id and the library's timing.
    final labels = c.library.labels.toList()..sort();
    for (final label in labels) {
      events.clear();
      final id = c.play(label);
      final ended = await _until(
        t,
        () =>
            events.whereType<SignEnded>().where((e) => e.id == id).firstOrNull,
        const Duration(seconds: 10),
        'end of $label (id $id; got ${[for (final e in events) _describe(e)]})',
      );
      final started = events.whereType<SignStarted>().firstWhere(
        (e) => e.id == id,
      );
      expect(started.label, label);
      expect(ended.interrupted, isFalse, reason: label);
      final want = c.library.duration(label).inMilliseconds;
      expect(
        (started.duration.inMilliseconds - want).abs(),
        lessThanOrEqualTo(1),
        reason: label,
      );
      expect(events.whereType<AvatarError>(), isEmpty, reason: label);
    }
    debugPrint('AVATAR played=${labels.length}');

    // Pausing (no screen shows the avatar) ends the sign: nobody saw it.
    events.clear();
    final looped = c.play(labels.first, loop: true);
    await _until(
      t,
      () => events
          .whereType<SignStarted>()
          .where((e) => e.id == looped)
          .firstOrNull,
      const Duration(seconds: 5),
      'start of the looped sign',
    );
    c.pause();
    final cut = await _until(
      t,
      () => events
          .whereType<SignEnded>()
          .where((e) => e.id == looped)
          .firstOrNull,
      const Duration(seconds: 5),
      'end of the paused sign',
    );
    expect(cut.interrupted, isTrue);
    c.resume();
    debugPrint('AVATAR pause_interrupts=ok');

    // Frame rate while signing (looped sign, 6 s).
    events.clear();
    c
      ..setStats(on: true)
      ..play('please', loop: true);
    final until = DateTime.now().add(const Duration(seconds: 7));
    while (DateTime.now().isBefore(until)) {
      await t.pump(const Duration(milliseconds: 100));
    }
    c
      ..setStats(on: false)
      ..stop();
    final fps = events.whereType<AvatarStats>().map((e) => e.fps).toList();
    debugPrint('AVATAR fps=${fps.map((f) => f.toStringAsFixed(1)).toList()}');
    expect(fps, isNotEmpty);
    await t.pump(const Duration(seconds: 1));
  });
}

String _describe(AvatarEvent e) => switch (e) {
  SignStarted(:final id, :final label) => 'started $id $label',
  SignEnded(:final id, :final label) => 'ended $id $label',
  AvatarError(:final code, :final message) => 'error $code $message',
  _ => e.runtimeType.toString(),
};

Future<T> _until<T>(
  WidgetTester t,
  T? Function() read,
  Duration timeout,
  String what,
) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final v = read();
    if (v != null) return v;
    await t.pump(const Duration(milliseconds: 100));
  }
  throw TimeoutException('waiting for $what', timeout);
}
