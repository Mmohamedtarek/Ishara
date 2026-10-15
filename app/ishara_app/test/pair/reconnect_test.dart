import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/features/pair/application/reconnect.dart';

import '../support/fake_glove.dart';

void main() {
  Future<(bool, FakeGloveSource)> run({
    FakeGloveSource? glove,
    bool paired = true,
    bool permission = true,
  }) async {
    final g = glove ?? FakeGloveSource();
    final kv = MemoryKeyValueStore();
    if (paired) {
      await OnboardingStore(kv)
          .saveGlove(const PairedGlove(id: 'g1', name: 'Ishara-3FA2'));
    }
    final c = ProviderContainer(
      overrides: [
        gloveSourceProvider.overrideWithValue(g),
        glovePermissionsProvider.overrideWithValue(
          FakeGlovePermissions(alreadyGranted: permission),
        ),
        keyValueStoreProvider.overrideWithValue(kv),
      ],
    );
    addTearDown(c.dispose);
    return (await c.read(reconnectPairedGloveProvider.future), g);
  }

  test('finds the paired glove, stops scanning, connects', () async {
    final (ok, g) = await run();
    expect(ok, isTrue);
    expect(g.commands, ['scan', 'connect g1']);
    expect(g.status.phase, GlovePhase.ready);
  });

  test('never asks for permissions at start-up', () async {
    final (ok, g) = await run(permission: false);
    expect(ok, isFalse);
    expect(g.commands, isEmpty);
  });

  test('nothing paired / not found', () async {
    expect((await run(paired: false)).$1, isFalse);
    final (ok, g) = await run(glove: FakeGloveSource(found: const []));
    expect(ok, isFalse);
    expect(g.commands, ['scan']);
  });

  test('#MPU FAIL: refused and disconnected, as in pairing (Q-K3)', () async {
    final (ok, g) = await run(glove: FakeGloveSource()..mpuFail = true);
    expect(ok, isFalse);
    expect(g.commands.last, 'disconnect');
  });

  test('two callers during one drop share one attempt (Talk and a mission, '
      'step 8)', () async {
    final g = FakeGloveSource();
    final kv = MemoryKeyValueStore();
    await OnboardingStore(kv)
        .saveGlove(const PairedGlove(id: 'g1', name: 'Ishara-3FA2'));
    final c = ProviderContainer(
      overrides: [
        gloveSourceProvider.overrideWithValue(g),
        glovePermissionsProvider.overrideWithValue(FakeGlovePermissions()),
        keyValueStoreProvider.overrideWithValue(kv),
      ],
    );
    addTearDown(c.dispose);
    final ref = c.read(_refProvider);
    final a = reconnectToPairedGlove(ref);
    final b = reconnectToPairedGlove(ref);
    expect(reconnecting(g), isTrue);
    expect(await a, isTrue);
    expect(await b, isTrue);
    expect(g.commands, ['scan', 'connect g1']);
    expect(reconnecting(g), isFalse);
  });
}

/// A plain Ref for calling the helper directly.
final _refProvider = Provider<Ref>((ref) => ref);
