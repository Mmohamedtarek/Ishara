import 'package:flutter/widgets.dart';
import 'package:ishara_app/core/settings/developer_mode.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/moonshine_speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:ishara_app/core/speech/speech_trace.dart';
import 'package:ishara_app/core/speech/text_to_speech.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'speech_providers.g.dart';

/// Speech to text: on Android, Moonshine for English (TV-21) and EgypTalk
/// for Arabic (TV-24); the phone's recognizer on iOS and as the fallback.
/// Tests override it with a fake.
@Riverpod(keepAlive: true)
SpeechToText speechToText(Ref ref) {
  final trace = ref.watch(speechTraceProvider);
  final s = speechEngine(PlatformSpeechToText(trace: trace), trace);
  ref.onDispose(s.cancel);
  if (s is OnDeviceRouter) ref.onDispose(s.dispose);
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
