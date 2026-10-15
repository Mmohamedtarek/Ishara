import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/config/app_rules.dart';
import 'package:ishara_app/core/device/keep_screen_on.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/speech/text_to_speech.dart';

/// Records what is spoken; [hasVoice] is what [setLanguage] answers.
class FakeTextToSpeech implements TextToSpeech {
  bool hasVoice = true;
  final spoken = <String>[];
  final languages = <SpokenLanguage>[];
  int stops = 0;

  @override
  Future<bool> setLanguage(SpokenLanguage language) async {
    languages.add(language);
    return hasVoice;
  }

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;
}

/// Decider events and failures the test sends.
class FakeRecognitionFeed implements RecognitionFeed {
  final _events = StreamController<RecognitionEvent>.broadcast(sync: true);
  final _errors = StreamController<Failure>.broadcast(sync: true);

  @override
  Stream<RecognitionEvent> get events => _events.stream;

  @override
  Stream<Failure> get errors => _errors.stream;

  void send(DeciderEventKind kind, String label, {double probability = .9}) =>
      _events.add(
        RecognitionEvent(
          kind: kind,
          label: label,
          step: 0,
          probability: probability,
        ),
      );

  void word(String label, {double probability = .9}) =>
      send(DeciderEventKind.word, label, probability: probability);
  void tentative(String label) => send(DeciderEventKind.tentative, label);
  void confirm(String label, {double probability = .9}) =>
      send(DeciderEventKind.confirm, label, probability: probability);
  void cancel(String label) => send(DeciderEventKind.cancel, label);

  void fail() => _errors.add(const UnexpectedFailure('engine stopped'));

  Future<void> dispose() async {
    await _events.close();
    await _errors.close();
  }
}

/// Records the screen-on calls.
class FakeKeepScreenOn implements KeepScreenOn {
  final calls = <bool>[];
  bool get on => calls.isNotEmpty && calls.last;

  @override
  Future<void> set({required bool on}) async => calls.add(on);
}

/// The overrides a Talk screen needs for glove → text without a model.
class TalkFakes {
  final feed = FakeRecognitionFeed();
  final tts = FakeTextToSpeech();
  final screen = FakeKeepScreenOn();
  Duration timeout = const Duration(seconds: 3);

  List<Override> get overrides => [
    appRulesProvider.overrideWithValue(AsyncData(testAppRules)),
    recognitionFeedProvider.overrideWithValue(AsyncData(feed)),
    conversationTimeoutProvider.overrideWithValue(AsyncData(timeout)),
    textToSpeechProvider.overrideWithValue(tts),
    keepScreenOnProvider.overrideWithValue(screen),
  ];
}

/// `assets/config/app_rules.json`, read from disk (tests can't wait for the
/// asset bundle before the first message).
final AppRules testAppRules = AppRules.parse(
  File(appRulesAsset).readAsStringSync(),
);
