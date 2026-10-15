import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/phrases/phrases_providers.dart';
import 'package:ishara_app/features/learn/application/learn_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'data_export.g.dart';

/// Hands a file to the user (the phone's share sheet; a fake in tests).
abstract interface class FileSharer {
  Future<void> share(Uint8List bytes, {required String name});
}

class PlatformFileSharer implements FileSharer {
  const new();

  @override
  Future<void> share(Uint8List bytes, {required String name}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: name, mimeType: 'application/json'),
        ],
        fileNameOverrides: [name],
      ),
    );
  }
}

@Riverpod(keepAlive: true)
FileSharer fileSharer(Ref ref) => const PlatformFileSharer();

/// Settings › Privacy › Export my data: one JSON file with the stored
/// conversation, the saved phrases and the Learn activity log, exactly as
/// the phone keeps them. Only the user sends it anywhere.
abstract final class DataExport {
  static const fileName = 'ishara-data.json';
  static const formatVersion = 1;

  static Map<String, Object> build(Ref ref) => {
    'app': 'Ishara',
    'format': formatVersion,
    'exportedAt': clock.now().toUtc().toIso8601String(),
    'conversation': ref.read(conversationRepositoryProvider).export(),
    'savedPhrases': ref.read(savedPhrasesRepositoryProvider).export(),
    'learnActivity': ref.read(activityRepositoryProvider).export(),
  };

  static Uint8List bytes(Map<String, Object> data) => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
  );
}

@riverpod
Future<void> Function() exportMyData(Ref ref) =>
    () => ref
        .read(fileSharerProvider)
        .share(
          DataExport.bytes(DataExport.build(ref)),
          name: DataExport.fileName,
        );
