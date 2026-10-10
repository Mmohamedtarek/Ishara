import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/assets/asset_bytes.dart';
import 'package:ishara_app/core/glove/ble/reactive_ble_transport.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_permissions.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'glove_providers.g.dart';

/// Which glove the app talks to. Only `lib/core/glove/` uses this.
enum GloveSourceKind { mock, ble }

/// `--dart-define=GLOVE=mock|ble`. Without the flag: mock in debug and
/// profile builds, the real glove in release builds.
GloveSourceKind gloveKindFromEnvironment({
  String define = const String.fromEnvironment('GLOVE'),
  bool release = kReleaseMode,
}) => switch (define) {
  'mock' => GloveSourceKind.mock,
  'ble' => GloveSourceKind.ble,
  _ => release ? GloveSourceKind.ble : GloveSourceKind.mock,
};

/// The hidden developer switch (Settings). null = use the build flag.
@Riverpod(keepAlive: true)
class GloveSourceOverride extends _$GloveSourceOverride {
  @override
  GloveSourceKind? build() => null;

  // A setter would hide the intent of the developer switch.
  // ignore: use_setters_to_change_properties
  void set(GloveSourceKind? kind) => state = kind;
}

@Riverpod(keepAlive: true)
GloveSourceKind activeGloveKind(Ref ref) =>
    ref.watch(gloveSourceOverrideProvider) ?? gloveKindFromEnvironment();

/// The simulated glove, or null when the real glove is active. Exposed for
/// the developer demo controls only.
@Riverpod(keepAlive: true)
MockGlove? mockGlove(Ref ref) {
  if (ref.watch(activeGloveKindProvider) != GloveSourceKind.mock) return null;
  final feed = MockFeed(
    MockLibrary(readAssetBytes, root: ref.watch(activePackProvider).mockDir),
  );
  ref.onDispose(feed.dispose);
  return MockGlove(feed);
}

/// The glove the whole app uses.
@Riverpod(keepAlive: true)
GloveSource gloveSource(Ref ref) {
  final mock = ref.watch(mockGloveProvider);
  final source = GloveClient(
    mock ?? ReactiveBleTransport(FlutterReactiveBleApi()),
  );
  ref.onDispose(source.dispose);
  return source;
}

/// The permissions the active glove needs (none for the mock glove).
@Riverpod(keepAlive: true)
GlovePermissions glovePermissions(Ref ref) =>
    ref.watch(activeGloveKindProvider) == GloveSourceKind.mock
    ? const NoGlovePermissions()
    : const PlatformGlovePermissions();

/// The glove's status as a stream for the UI (starts with the current one).
@Riverpod(keepAlive: true)
Stream<GloveStatus> gloveStatus(Ref ref) async* {
  final source = ref.watch(gloveSourceProvider);
  yield source.status;
  yield* source.statusChanges;
}
