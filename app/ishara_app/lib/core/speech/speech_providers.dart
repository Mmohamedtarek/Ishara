import 'package:flutter/widgets.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_trace.dart';
import 'package:ishara_app/core/speech/text_to_speech.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'speech_providers.g.dart';

/// The phone's speech recognizer (tests override it with a fake).
@Riverpod(keepAlive: true)
SpeechToText speechToText(Ref ref) {
  final s = PlatformSpeechToText(trace: ref.watch(speechTraceProvider));
  ref.onDispose(s.cancel);
  return s;
}

/// The word-for-word speech log: debug builds with developer mode on only
/// (see [SpeechTrace]).
@Riverpod(keepAlive: true)
SpeechTrace speechTrace(Ref ref) =>
    SpeechTrace(() => ref.read(developerModeProvider));

/// The microphone permission (tests override it with a fake).
@Riverpod(keepAlive: true)
MicPermissions micPermissions(Ref ref) => const PlatformMicPermissions();

/// The phone's voice (tests override it with a fake).
@Riverpod(keepAlive: true)
TextToSpeech textToSpeech(Ref ref) {
  final tts = PlatformTextToSpeech(
    phoneLocales: () => [
      for (final l in WidgetsBinding.instance.platformDispatcher.locales)
        l.toLanguageTag(),
    ],
  );
  ref.onDispose(tts.stop);
  return tts;
}
