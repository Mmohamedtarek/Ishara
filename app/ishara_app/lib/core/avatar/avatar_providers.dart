import 'package:flutter/services.dart';
import 'package:ishara_app/core/assets/asset_bytes.dart';
import 'package:ishara_app/core/avatar/avatar_asset_server.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_slots.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'avatar_providers.g.dart';

/// The cast list (`assets/avatar/cast.json`).
const avatarCastAsset = 'assets/avatar/cast.json';

@Riverpod(keepAlive: true)
Future<AvatarCast> avatarCast(Ref ref) async =>
    AvatarCast.parse(await rootBundle.loadString(avatarCastAsset));

/// The active pack's avatar sign library.
@Riverpod(keepAlive: true)
Future<AvatarLibrary> avatarLibrary(Ref ref) async {
  final pack = ref.watch(activePackProvider);
  return AvatarLibrary.parse(
    await rootBundle.loadString(pack.avatarLibraryAsset),
    language: pack.language,
  );
}

/// The loopback server the avatar page loads from.
@Riverpod(keepAlive: true)
Future<AvatarAssetServer> avatarAssetServer(Ref ref) async {
  final server = await AvatarAssetServer.start(readAssetBytes);
  ref.onDispose(server.close);
  return server;
}

/// Builds the page the avatar runs in: a WebView, or, where none exists
/// (tests, unsupported platforms), [UnavailableAvatarSurface] (no server is
/// started then). Tests override it to drive a fake page.
@Riverpod(keepAlive: true)
AvatarSurface Function(AvatarAssetServer)? avatarSurfaceFactory(Ref ref) =>
    webViewAvailable ? WebViewAvatarPage.new : null;

/// The avatar: one page and one controller for the whole app (prompt:
/// "keep one WebView alive for the whole app").
class AvatarRuntime {
  const new(this.controller, this.surface);
  final AvatarController controller;
  final AvatarSurface surface;
}

@Riverpod(keepAlive: true)
Future<AvatarRuntime> avatarRuntime(Ref ref) async {
  final factory = ref.watch(avatarSurfaceFactoryProvider);
  final library = await ref.watch(avatarLibraryProvider.future);
  final pack = ref.watch(activePackProvider);
  final AvatarSurface surface;
  final AvatarController controller;
  if (factory == null) {
    surface = UnavailableAvatarSurface();
    controller = AvatarController(
      page: surface,
      library: library,
      libraryUrl: '',
      castUrl: '',
    );
  } else {
    final server = await ref.watch(avatarAssetServerProvider.future);
    surface = factory(server);
    controller = AvatarController(
      page: surface,
      library: library,
      libraryUrl: server.pageRelative(pack.avatarLibraryAsset),
      castUrl: server.pageRelative(avatarCastAsset),
    );
  }
  ref.onDispose(() async {
    await controller.dispose();
    await surface.dispose();
  });
  return AvatarRuntime(controller, surface);
}

/// Which avatar slot on screen shows the avatar.
@Riverpod(keepAlive: true)
AvatarSlotRegistry avatarSlotRegistry(Ref ref) {
  final r = AvatarSlotRegistry();
  ref.onDispose(r.dispose);
  return r;
}
