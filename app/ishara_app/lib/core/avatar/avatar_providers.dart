import 'package:flutter/services.dart';
import 'package:ishara_app/core/assets/asset_bytes.dart';
import 'package:ishara_app/core/avatar/avatar_asset_server.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_slots.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/settings/settings_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'avatar_providers.g.dart';

/// The cast list (`assets/avatar/cast.json`).
const avatarCastAsset = 'assets/avatar/cast.json';

@Riverpod(keepAlive: true)
Future<AvatarCast> avatarCast(Ref ref) async =>
    AvatarCast.parse(await rootBundle.loadString(avatarCastAsset));

/// The character that signs for the user: the one the Avatar studio saved,
/// else the cast default. Null while the cast loads. Texts use its name
/// and, in Arabic, its gender (RB-1: hidden characters never come back from
/// [AvatarCast.byId]).
@Riverpod(keepAlive: true)
AvatarCharacter? currentCharacter(Ref ref) => ref
    .watch(avatarCastProvider)
    .value
    ?.byId(ref.watch(savedCharacterProvider));

/// The character id the Avatar studio saved (null = the cast default).
@Riverpod(keepAlive: true)
class SavedCharacter extends _$SavedCharacter {
  @override
  String? build() =>
      ref.watch(settingsStoreProvider).getString(SettingsStore.kCharacter);

  /// Saves [id] and switches the avatar that is already running, so the
  /// name shown and the character signing never disagree.
  Future<void> save(String id) async {
    state = id;
    final running = ref.read(avatarRuntimeProvider).value?.controller;
    // ids resolve through the cast (a hidden one shows the default)
    final shown = ref.read(avatarCastProvider).value?.byId(id).id ?? id;
    if (running != null && running.character != shown) {
      running.setCharacter(id);
    }
    await ref
        .read(settingsStoreProvider)
        .setString(SettingsStore.kCharacter, id);
  }
}

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
  final cast = await ref.watch(avatarCastProvider.future);
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
      cast: cast,
    );
  } else {
    final server = await ref.watch(avatarAssetServerProvider.future);
    surface = factory(server);
    controller = AvatarController(
      page: surface,
      library: library,
      libraryUrl: server.pageRelative(pack.avatarLibraryAsset),
      castUrl: server.pageRelative(avatarCastAsset),
      cast: cast,
    );
  }
  // the character the Avatar studio saved (the cast default otherwise)
  final saved = ref.read(savedCharacterProvider);
  if (saved != null && cast.byId(saved).id != cast.defaultId) {
    controller.setCharacter(cast.byId(saved).id);
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
