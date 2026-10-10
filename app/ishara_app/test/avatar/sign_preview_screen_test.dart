import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';
import 'package:ishara_app/features/dev/presentation/sign_preview_screen.dart';

import '../support/kit.dart';

class _Surface implements AvatarSurface {
  final sent = <Map<String, Object?>>[];
  final out = StreamController<String>.broadcast();
  @override
  Stream<String> get messages => out.stream;
  @override
  Future<void> send(Map<String, Object?> command) async => sent.add(command);
  @override
  Widget buildView() => const SizedBox.expand();
  @override
  Future<void> dispose() => out.close();
}

void main() {
  testWidgets('preview: pick a sign, view, moment, play, compare pairs', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
    final surface = _Surface();
    final c = AvatarController(
      page: surface,
      library: library,
      libraryUrl: 'l',
      castUrl: 'c',
    );
    final container = ProviderContainer(
      overrides: [
        avatarRuntimeProvider.overrideWith(
          (ref) async => AvatarRuntime(c, surface),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Asset loading needs real async (not the test's fake clock).
    final catalogue = (await t.runAsync(
      () => container.read(signCatalogueProvider.future),
    ))!;
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: IsharaTheme.build(
            brightness: Brightness.dark,
            isArabic: false,
          ),
          builder: (context, child) => AvatarHost(child: child!),
          home: const SignPreviewScreen(),
        ),
      ),
    );
    surface.out.add(jsonEncode({'type': 'loaded'}));
    await t.pumpAndSettle();
    // first sign alphabetically until one is picked
    expect(find.textContaining('·  bye'), findsOneWidget);
    // bye was approved with the other new signs (2026-10-10)
    expect(find.text('pending approval (avatar: false)'), findsNothing);

    await t.tap(find.byKey(const ValueKey('sign-water')));
    await t.pumpAndSettle();
    expect(surface.sent.last, {
      'cmd': 'preview',
      'label': 'water',
      't': 0.0,
      'view': 0.0,
      'frozen': true,
    });
    await t.tap(find.text('Side (right)'));
    await t.pumpAndSettle();
    expect(surface.sent.last['view'], -90.0);

    await t.drag(find.byType(Slider), const Offset(200, 0));
    await t.pumpAndSettle();
    expect(surface.sent.last['t']! as double, greaterThan(0));

    await t.tap(find.text('1.5x'));
    await t.tap(find.text('Loop'));
    await t.pumpAndSettle();
    expect(surface.sent.last, containsPair('cmd', 'play'));
    expect(surface.sent.last, containsPair('loop', true));
    expect(surface.sent.last, containsPair('speed', 1.5));
    expect(find.text('playing'), findsOneWidget);
    await t.tap(find.text('Play'));
    await t.tap(find.text('Stop'));
    await t.pumpAndSettle();
    expect(surface.sent.last, {'cmd': 'stop'});

    await t.tap(find.byKey(const ValueKey('compare-five-four-four')));
    await t.pumpAndSettle();
    expect(surface.sent.last['label'], 'four');
    expect(find.text('being reviewed'), findsNothing);
    await t.tap(find.byKey(const ValueKey('sign-doctor')));
    await t.pumpAndSettle();
    expect(find.text('being reviewed'), findsOneWidget);
    // Whoever starts a sign, the screen shows it: header, words, chips,
    // description, live time (screen recordings are reviewed this way).
    final id = c.play('water');
    surface.out.add(
      jsonEncode({
        'type': 'signStarted',
        'id': id,
        'label': 'water',
        'ms': library.duration('water').inMilliseconds,
        'loop': false,
      }),
    );
    await t.pump(); // page → controller → screen: the clock starts
    await t.pump(); // its first tick (elapsed 0)
    await t.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('·  water'), findsOneWidget);
    expect(find.text('Water  ·  water'), findsOneWidget);
    expect(find.text(catalogue.byLabel('water')!.description), findsOneWidget);
    expect(find.text('glove'), findsOneWidget);
    expect(find.text('pending approval (avatar: false)'), findsNothing);
    final live = t.widget<Slider>(find.byType(Slider)).value;
    // 0.7 s after the start, at speed 1: 0.7 − 0.32 lead-in = 0.38 s
    expect(live, closeTo(.38, .05));
    surface.out.add(
      jsonEncode({
        'type': 'signEnded',
        'id': id,
        'label': 'water',
        'interrupted': false,
      }),
    );
    await t.pump();
    final stopped = t.widget<Slider>(find.byType(Slider)).value;
    await t.pump(const Duration(milliseconds: 300));
    expect(t.widget<Slider>(find.byType(Slider)).value, stopped);
    // a new sign at another speed (e.g. Talk at 1.5x) replaces it
    final id2 = c.play('bye', speed: 1.5);
    surface.out.add(
      jsonEncode({
        'type': 'signStarted',
        'id': id2,
        'label': 'bye',
        'ms': library.duration('bye', speed: 1.5).inMilliseconds,
        'loop': false,
      }),
    );
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Bye  ·  bye'), findsOneWidget);
    expect(find.text('pending approval (avatar: false)'), findsNothing);
    expect(
      t.widget<Slider>(find.byType(Slider)).value,
      closeTo(.6 * 1.5 - .32, .05),
    );

    // Closing the screen gives the shared avatar back as others expect it.
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(surface.sent.sublist(surface.sent.length - 2), [
      {'cmd': 'preview', 'label': null, 't': 0.0, 'view': 0.0, 'frozen': true},
      {'cmd': 'stop'},
    ]);
    await t.runAsync(c.dispose); // a broadcast cancel needs real async
  });

  testWidgets('opened and closed without any interaction: no error', (t) async {
    final library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
    final surface = _Surface();
    final c = AvatarController(
      page: surface,
      library: library,
      libraryUrl: 'l',
      castUrl: 'c',
    );
    final container = ProviderContainer(
      overrides: [
        avatarRuntimeProvider.overrideWith(
          (ref) async => AvatarRuntime(c, surface),
        ),
      ],
    );
    addTearDown(container.dispose);
    await t.runAsync(() => container.read(signCatalogueProvider.future));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: IsharaTheme.build(
            brightness: Brightness.dark,
            isArabic: false,
          ),
          home: const SignPreviewScreen(),
        ),
      ),
    );
    await t.pump();
    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
    await t.runAsync(c.dispose);
  });

  testWidgets('a sign waiting for approval (avatar: false) is marked', (
    t,
  ) async {
    // every sign is approved now: mark one as new again (sign rule 2)
    final j = jsonDecode(
      readText('assets/packs/asl/signs.json'),
    ) as Map<String, dynamic>;
    for (final s in j['signs'] as List<dynamic>) {
      if ((s as Map<String, dynamic>)['label'] == 'bye') s['avatar'] = false;
    }
    final catalogue = SignCatalogue.parse(
      jsonEncode(j),
      labels: Labels.parse(readText('assets/packs/asl/kit/model/labels.txt')),
    );
    final surface = _Surface();
    final c = AvatarController(
      page: surface,
      library: AvatarLibrary.parse(
        readText('assets/packs/asl/avatar/library.json'),
        language: SignLanguage.asl,
      ),
      libraryUrl: 'l',
      castUrl: 'c',
    );
    final container = ProviderContainer(
      overrides: [
        avatarRuntimeProvider.overrideWith(
          (ref) async => AvatarRuntime(c, surface),
        ),
        signCatalogueProvider.overrideWith((ref) async => catalogue),
      ],
    );
    addTearDown(container.dispose);
    await t.runAsync(() => container.read(signCatalogueProvider.future));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: IsharaTheme.build(
            brightness: Brightness.dark,
            isArabic: false,
          ),
          home: const SignPreviewScreen(),
        ),
      ),
    );
    surface.out.add(jsonEncode({'type': 'loaded'}));
    await t.pumpAndSettle();
    expect(find.textContaining('·  bye'), findsOneWidget);
    expect(find.text('pending approval (avatar: false)'), findsOneWidget);
  });
}
