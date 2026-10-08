import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ishara_app/core/glove/ble/reactive_ble_transport.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
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

/// Reads app assets (the kit's mock recordings).
Future<Uint8List> _readAsset(String path) async =>
    (await rootBundle.load(path)).buffer.asUint8List();

/// The simulated glove, or null when the real glove is active. Exposed for
/// the developer demo controls only.
@Riverpod(keepAlive: true)
MockGlove? mockGlove(Ref ref) {
  if (ref.watch(activeGloveKindProvider) != GloveSourceKind.mock) return null;
  final feed = MockFeed(MockLibrary(_readAsset));
  ref.onDispose(feed.dispose);
  return MockGlove(feed);
}

/// The glove the whole app uses.
@Riverpod(keepAlive: true)
GloveSource gloveSource(Ref ref) {
  final mock = ref.watch(mockGloveProvider);
  final source = GloveClient(
    mock ??
        ReactiveBleTransport(
          FlutterReactiveBleApi(),
          isAndroid: defaultTargetPlatform == TargetPlatform.android,
        ),
  );
  ref.onDispose(source.dispose);
  return source;
}
