import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/avatar/avatar_asset_server.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';

class _Surface implements AvatarSurface {
  AvatarAssetServer? server;
  bool disposed = false;
  final _out = StreamController<String>.broadcast();

  @override
  Stream<String> get messages => _out.stream;

  @override
  Future<void> send(Map<String, Object?> command) async {}

  @override
  Widget buildView() => const SizedBox();

  @override
  Future<void> dispose() async {
    disposed = true;
    await _out.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cast and library load from the bundle', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final cast = await c.read(avatarCastProvider.future);
    expect(cast.defaultId, 'nour');
    final lib = await c.read(avatarLibraryProvider.future);
    expect(lib.has('hello'), isTrue);
  });

  test(
    'no WebView here (flutter test): the avatar fails cleanly, no server',
    () async {
      expect(webViewAvailable, isFalse);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(avatarSurfaceFactoryProvider), isNull);
      final rt = await c.read(avatarRuntimeProvider.future);
      expect(rt.surface, isA<UnavailableAvatarSurface>());
      await Future<void>.delayed(Duration.zero);
      expect(rt.controller.status.value, AvatarStatus.failed);
    },
  );

  test(
    'with a WebView: served from loopback, page-relative data URLs',
    () async {
      final surface = _Surface();
      final c = ProviderContainer(
        overrides: [
          avatarSurfaceFactoryProvider.overrideWithValue((server) {
            surface.server = server;
            return surface;
          }),
        ],
      );
      final rt = await c.read(avatarRuntimeProvider.future);
      expect(identical(rt.surface, surface), isTrue);
      expect(surface.server!.pageUri.host, '127.0.0.1');
      expect(rt.controller.libraryUrl, '../packs/asl/avatar/library.json');
      expect(rt.controller.castUrl, '../avatar/cast.json');
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(surface.disposed, isTrue);
    },
  );
}
