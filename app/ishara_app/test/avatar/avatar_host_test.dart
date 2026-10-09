import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_host.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/avatar_slots.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/theme/ishara_theme.dart';

import '../support/kit.dart';

/// Counts how many avatar views exist and how often one was created.
class _ViewProbe {
  int live = 0;
  int created = 0;
}

class _FakeView extends StatefulWidget {
  const new(this.probe);
  final _ViewProbe probe;
  @override
  State<_FakeView> createState() => _FakeViewState();
}

class _FakeViewState extends State<_FakeView> {
  @override
  void initState() {
    super.initState();
    widget.probe
      ..live += 1
      ..created += 1;
  }

  @override
  void dispose() {
    widget.probe.live -= 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: ValueKey('avatar-view'), color: Color(0xFF00FF00));
}

class _FakeSurface implements AvatarSurface {
  new(this.probe);
  final _ViewProbe probe;
  final sent = <Map<String, Object?>>[];
  final out = StreamController<String>.broadcast();

  @override
  Stream<String> get messages => out.stream;

  @override
  Future<void> send(Map<String, Object?> command) async => sent.add(command);

  @override
  Widget buildView() => _FakeView(probe);

  @override
  Future<void> dispose() => out.close();

  List<String> get cmds => [for (final c in sent) c['cmd']! as String];
}

class _Screen extends StatelessWidget {
  const new(this.name, {this.avatar = true});
  final String name;
  final bool avatar;
  @override
  Widget build(BuildContext context) => Scaffold(
    key: ValueKey('screen-$name'),
    body: Column(
      children: [
        Text(name),
        if (avatar)
          const SizedBox(width: 300, height: 260, child: AvatarStage()),
      ],
    ),
  );
}

void main() {
  late AvatarLibrary library;
  late _ViewProbe probe;
  late _FakeSurface surface;
  late AvatarController controller;

  setUpAll(() {
    library = AvatarLibrary.parse(
      readText('assets/packs/asl/avatar/library.json'),
      language: SignLanguage.asl,
    );
  });

  setUp(() {
    probe = _ViewProbe();
    surface = _FakeSurface(probe);
    controller = AvatarController(
      page: surface,
      library: library,
      libraryUrl: 'l',
      castUrl: 'c',
    );
  });

  final navKey = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester t, Widget home) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          avatarRuntimeProvider.overrideWith(
            (ref) async => AvatarRuntime(controller, surface),
          ),
        ],
        child: MaterialApp(
          navigatorKey: navKey,
          theme: IsharaTheme.build(
            brightness: Brightness.dark,
            isArabic: false,
          ),
          builder: (context, child) => AvatarHost(child: child!),
          home: home,
        ),
      ),
    );
    surface.out.add(jsonEncode({'type': 'loaded'}));
    await t.pumpAndSettle();
  }

  Finder viewIn(String screen) => find.descendant(
    of: find.byKey(ValueKey('screen-$screen')),
    matching: find.byKey(const ValueKey('avatar-view')),
  );

  testWidgets(
    'the avatar follows the visible screen; one view, never recreated',
    (t) async {
      await pumpApp(t, const _Screen('A'));
      expect(viewIn('A'), findsOneWidget);
      expect((probe.live, probe.created), (1, 1));

      navKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const _Screen('B')),
      );
      await t.pumpAndSettle();
      expect(viewIn('B'), findsOneWidget);
      expect(viewIn('A'), findsNothing);
      expect((probe.live, probe.created), (1, 1));

      navKey.currentState!.pop();
      await t.pumpAndSettle();
      expect(viewIn('A'), findsOneWidget);
      expect((probe.live, probe.created), (1, 1));
    },
  );

  testWidgets('no avatar on screen: parked offstage and paused', (t) async {
    await pumpApp(t, const _Screen('A'));
    surface.sent.clear();
    navKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const _Screen('C', avatar: false),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('avatar-view')), findsNothing);
    expect(
      find.byKey(const ValueKey('avatar-view'), skipOffstage: false),
      findsOneWidget,
    );
    expect((probe.live, probe.created), (1, 1));
    expect(surface.cmds, ['pause']);

    navKey.currentState!.pop();
    await t.pumpAndSettle();
    expect(viewIn('A'), findsOneWidget);
    expect(surface.cmds, ['pause', 'resume']);
    expect((probe.live, probe.created), (1, 1));
  });

  testWidgets('a dialog on top keeps the avatar on its screen, unpaused', (
    t,
  ) async {
    await pumpApp(t, const _Screen('A'));
    surface.sent.clear();
    unawaited(
      showDialog<void>(
        context: navKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('hi')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('hi'), findsOneWidget);
    expect(viewIn('A'), findsOneWidget);
    expect(surface.cmds, isNot(contains('pause')));
    navKey.currentState!.pop();
    await t.pumpAndSettle();
    expect(viewIn('A'), findsOneWidget);
    expect((probe.live, probe.created), (1, 1));
  });

  testWidgets('a slot in a hidden tab (tickers off) does not take the avatar', (
    t,
  ) async {
    await pumpApp(
      t,
      const Scaffold(
        body: Column(
          children: [
            Expanded(child: _Screen('visible')),
            Expanded(
              child: TickerMode(enabled: false, child: _Screen('hidden')),
            ),
          ],
        ),
      ),
    );
    expect(viewIn('visible'), findsOneWidget);
    expect(viewIn('hidden'), findsNothing);
    expect(probe.live, 1);
  });

  testWidgets('the app going to the background pauses the avatar', (t) async {
    await pumpApp(t, const _Screen('A'));
    surface.sent.clear();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(surface.cmds, ['pause']);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(surface.cmds, ['pause', 'resume']);
  });

  testWidgets('reduce motion follows the OS setting', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(t, const _Screen('A'));
    expect(
      surface.sent,
      contains(equals({'cmd': 'setReduceMotion', 'on': true})),
    );
  });

  testWidgets('placeholder until ready, then it fades out', (t) async {
    await pumpApp(t, const _Screen('A'));
    AnimatedOpacity placeholder() =>
        t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(placeholder().opacity, 1);
    surface.out.add(
      jsonEncode({
        'type': 'ready',
        'character': 'nour',
        'signs': library.labels.toList(),
      }),
    );
    await t.pumpAndSettle();
    expect(controller.status.value, AvatarStatus.ready);
    expect(placeholder().opacity, 0);
  });

  testWidgets('without a runtime yet, the stage shows the placeholder', (
    t,
  ) async {
    final never = Completer<AvatarRuntime>();
    await t.pumpWidget(
      ProviderScope(
        overrides: [avatarRuntimeProvider.overrideWith((ref) => never.future)],
        child: MaterialApp(
          theme: IsharaTheme.build(
            brightness: Brightness.light,
            isArabic: false,
          ),
          builder: (context, child) => AvatarHost(child: child!),
          home: const _Screen('A'),
        ),
      ),
    );
    await t.pump();
    expect(find.byType(AvatarSlot), findsNothing);
    expect(find.byKey(const ValueKey('avatar-view')), findsNothing);
  });

  test(
    'registry: last visible slot wins, the previous one gets it back',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final r = AvatarSlotRegistry();
      final a = Object();
      final b = Object();
      var notes = 0;
      r
        ..addListener(() => notes++)
        ..update(a, active: true);
      expect(r.owner, isNull, reason: 'committed after the frame');
      await _frame();
      expect(r.owner, a);
      r
        ..update(b, active: true)
        ..update(b, active: false)
        ..update(b, active: true);
      await _frame();
      expect(r.owner, b);
      r.release(b);
      await _frame();
      expect(r.owner, a);
      r.release(a);
      await _frame();
      expect(r.owner, isNull);
      expect(notes, 4);
      r
        ..dispose()
        ..update(a, active: true); // after dispose: ignored
    },
  );
}

Future<void> _frame() async {
  TestWidgetsFlutterBinding.instance
    ..handleBeginFrame(null)
    ..handleDrawFrame();
  await Future<void>.delayed(Duration.zero);
}
