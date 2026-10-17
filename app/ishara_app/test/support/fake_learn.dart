import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ishara_app/core/avatar/avatar_controller.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/webview_avatar_page.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/core/storage/database/app_database.dart';
import 'package:ishara_app/core/storage/key_value_store.dart';
import 'package:ishara_app/core/storage/legacy_store.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:ishara_app/features/learn/application/mission_controller.dart';
import 'package:ishara_app/features/learn/data/activity_repository.dart';

import 'fake_glove.dart';
import 'fake_talk.dart';

/// The shipped ASL catalogue, read from disk.
final SignCatalogue shippedSignCatalogue = SignCatalogue.parse(
  File('assets/packs/asl/signs.json').readAsStringSync(),
  labels: Labels.parse(
    File('assets/packs/asl/kit/model/labels.txt').readAsStringSync(),
  ),
);

/// An avatar page that records the commands it gets.
class RecordingAvatarSurface implements AvatarSurface {
  final sent = <Map<String, Object?>>[];
  final _out = StreamController<String>.broadcast(sync: true);

  /// The page is up: queued commands are delivered.
  void loaded() => _out.add(jsonEncode({'type': 'loaded'}));

  /// The `play` commands, as (label, speed, loop).
  List<(String, double, bool)> get plays => [
    for (final c in sent)
      if (c['cmd'] == 'play')
        (
          c['label']! as String,
          (c['speed']! as num).toDouble(),
          c['loop']! as bool,
        ),
  ];

  @override
  Stream<String> get messages => _out.stream;

  @override
  Future<void> send(Map<String, Object?> command) async => sent.add(command);

  @override
  Widget buildView() => const SizedBox.expand();

  @override
  Future<void> dispose() => _out.close();
}

/// Everything a mission or the Learn screen needs, without a device.
class LearnRig {
  /// [samePhone]: another rig, to go on with that phone's store and Learn
  /// log (its database). [source] / [recognition]: a real glove and
  /// recognizer instead of the fakes.
  new({
    FakeGloveSource? glove,
    LearnRig? samePhone,
    this.seed = 1,
    this.source,
    this.recognition,
  }) : glove = glove ?? FakeGloveSource(),
       _phone = samePhone,
       kv =
           samePhone?.kv ??
           MemoryKeyValueStore({
             'onboarding.done': true,
             'glove.id': 'g1',
             'glove.name': 'Ishara-3FA2',
           });

  final LearnRig? _phone;

  /// The phone's Learn log, in a database in memory; made when the rig is
  /// first used, from the old-store values seeded in [kv] (as the app's
  /// fallback reads them).
  late final ActivityRepository activity =
      _phone?.activity ??
      LocalActivityRepository(
        AppDatabase(NativeDatabase.memory()),
        initial: LegacyData.read(kv).activity,
      );

  final FakeGloveSource glove;
  final GloveSource? source;
  final RecognitionFeed? recognition;
  final MemoryKeyValueStore kv;
  final int seed;
  final feed = FakeRecognitionFeed();
  final avatar = RecordingAvatarSurface();
  final perms = FakeGlovePermissions();

  late final AvatarController avatarController = AvatarController(
    page: avatar,
    library: AvatarLibrary.parse(
      File('assets/packs/asl/avatar/library.json').readAsStringSync(),
      language: SignLanguage.asl,
    ),
    libraryUrl: 'l',
    castUrl: 'c',
  );

  /// For `pumpScreen`, which sets the glove, permissions and store itself
  /// (give it [glove] and [kv]).
  List<Override> get screenOverrides => overrides.sublist(3);

  List<Override> get overrides => [
    keyValueStoreProvider.overrideWithValue(kv),
    gloveSourceProvider.overrideWithValue(source ?? glove),
    glovePermissionsProvider.overrideWithValue(perms),
    activityRepositoryProvider.overrideWithValue(activity),
    recognitionFeedProvider.overrideWithValue(AsyncData(recognition ?? feed)),
    signCatalogueProvider.overrideWithValue(AsyncData(shippedSignCatalogue)),
    learnCatalogProvider.overrideWithValue(
      AsyncData(learnCatalogFrom(shippedSignCatalogue)),
    ),
    missionSeedProvider.overrideWithValue(seed),
    avatarRuntimeProvider.overrideWithValue(
      AsyncData(AvatarRuntime(avatarController, avatar)),
    ),
  ];

  Future<void> dispose() async {
    await feed.dispose();
    await glove.dispose();
    await avatarController.dispose();
  }
}
