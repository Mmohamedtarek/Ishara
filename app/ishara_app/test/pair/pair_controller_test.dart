import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/pair/application/pair_controller.dart';

import '../support/fake_glove.dart';

void main() {
  late FakeGloveSource glove;
  late FakeGlovePermissions perms;
  late MemoryKeyValueStore kv;
  late ProviderContainer c;

  setUp(() {
    glove = FakeGloveSource();
    perms = FakeGlovePermissions();
    kv = MemoryKeyValueStore();
    c =
        ProviderContainer(
            overrides: [
              gloveSourceProvider.overrideWithValue(glove),
              glovePermissionsProvider.overrideWithValue(perms),
              keyValueStoreProvider.overrideWithValue(kv),
            ],
          )
          // keep the auto-dispose controller alive for the test
          ..listen(pairControllerProvider, (_, _) {});
  });
  tearDown(() => c.dispose());

  PairState s() => c.read(pairControllerProvider);
  PairController ctl() => c.read(pairControllerProvider.notifier);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'permission → scan → found → connect: 3 checks pass, glove saved',
    () async {
      final seen = <List<CheckState>>[];
      c.listen(pairControllerProvider, (_, n) => seen.add(n.checks));
      await ctl().start();
      await settle();
      expect(s().stage, PairStage.found);
      expect(s().gloves.single.name, 'Ishara-3FA2');
      await ctl().connect(s().gloves.single);
      expect(s().stage, PairStage.connected);
      expect(s().checks, List.filled(3, CheckState.ok));
      expect(s().status.battery?.percent, 78);
      expect(s().status.info?.firmware, '0.3.0');
      // the checks advanced in order (Q-K3)
      expect(
        seen,
        anyElement(
          equals([CheckState.running, CheckState.waiting, CheckState.waiting]),
        ),
      );
      expect(
        seen,
        anyElement(
          equals([CheckState.ok, CheckState.running, CheckState.waiting]),
        ),
      );
      expect(
        seen,
        anyElement(equals([CheckState.ok, CheckState.ok, CheckState.running])),
      );
      expect(
        OnboardingStore(kv).glove,
        const PairedGlove(id: 'g1', name: 'Ishara-3FA2'),
      );
    },
  );

  test('gloves are sorted by signal, strongest first', () async {
    glove.found = const [
      DiscoveredGlove(id: 'a', name: 'Ishara-000A', rssi: -80),
      DiscoveredGlove(id: 'b', name: 'Ishara-000B', rssi: -50),
    ];
    await ctl().start();
    await settle();
    expect(s().gloves.map((g) => g.id), ['b', 'a']);
  });

  test('permission refused once / for good', () async {
    perms.answer = GlovePermission.denied;
    await ctl().start();
    expect(s().stage, PairStage.permissionDenied);
    expect(s().permission, GlovePermission.denied);
    expect(glove.commands, isEmpty);
    perms.answer = GlovePermission.permanentlyDenied;
    await ctl().start();
    expect(s().permission, GlovePermission.permanentlyDenied);
    await ctl().openSettings();
    expect(perms.settingsOpened, 1);
  });

  test('Android 11: unauthorized asks for location once, then scans', () async {
    glove
      ..scanError = const BluetoothUnavailableFailure(
        BluetoothProblem.unauthorized,
      )
      ..scanErrorTimes = 1;
    await ctl().start();
    for (var i = 0; i < 5; i++) {
      await settle();
    }
    expect(s().stage, PairStage.found);
  });

  test('location refused → permission denied', () async {
    glove.scanError = const BluetoothUnavailableFailure(
      BluetoothProblem.unauthorized,
    );
    perms.location = GlovePermission.permanentlyDenied;
    await ctl().start();
    await settle();
    await settle();
    expect(s().stage, PairStage.permissionDenied);
  });

  test('Bluetooth off', () async {
    glove.scanError = const BluetoothUnavailableFailure(BluetoothProblem.off);
    await ctl().start();
    await settle();
    expect(s().stage, PairStage.bluetoothProblem);
    expect(s().bluetooth, BluetoothProblem.off);
  });

  test('nothing found → not found; Scan again scans', () async {
    glove.found = const [];
    await ctl().start();
    await settle();
    expect(s().stage, PairStage.notFound);
    glove.found = const [
      DiscoveredGlove(id: 'g1', name: 'Ishara-3FA2', rssi: -55),
    ];
    await ctl().scanAgain();
    await settle();
    expect(s().stage, PairStage.found);
  });

  test('a failed check is marked; nothing is saved', () async {
    glove
      ..connectError = const GloveProtocolMismatchFailure(2)
      ..failAt = GlovePhase.checkingSensors;
    await ctl().start();
    await settle();
    await ctl().connect(s().gloves.single);
    expect(s().stage, PairStage.failed);
    expect(s().failure, isA<GloveProtocolMismatchFailure>());
    expect(s().checks, [CheckState.ok, CheckState.failed, CheckState.waiting]);
    expect(s().failedCheck, 1);
    expect(OnboardingStore(kv).glove, isNull);
  });

  test('#MPU FAIL fails check 2 (Q-K3) and disconnects', () async {
    glove.mpuFail = true;
    await ctl().start();
    await settle();
    await ctl().connect(s().gloves.single);
    expect(s().stage, PairStage.failed);
    expect(s().mpuFail, isTrue);
    expect(s().checks[1], CheckState.failed);
    expect(glove.commands.last, 'disconnect');
    expect(OnboardingStore(kv).glove, isNull);
  });

  test(
    'coming back while connected stays connected (prototype keep)',
    () async {
      await ctl().start();
      await settle();
      await ctl().connect(s().gloves.single);
      c.invalidate(pairControllerProvider);
      expect(s().stage, PairStage.connected);
      // Scan again from connected disconnects first
      await ctl().scanAgain();
      await settle();
      expect(
        glove.commands.skip(2),
        containsAllInOrder(['disconnect', 'scan']),
      );
      expect(s().stage, PairStage.found);
    },
  );
}
