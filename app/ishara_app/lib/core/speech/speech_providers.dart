import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'speech_providers.g.dart';

/// The phone's speech recognizer (tests override it with a fake).
@Riverpod(keepAlive: true)
SpeechToText speechToText(Ref ref) {
  final s = PlatformSpeechToText();
  ref.onDispose(s.cancel);
  return s;
}

/// The microphone permission (tests override it with a fake).
@Riverpod(keepAlive: true)
MicPermissions micPermissions(Ref ref) => const PlatformMicPermissions();
