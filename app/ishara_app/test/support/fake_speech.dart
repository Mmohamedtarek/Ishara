import 'dart:async';

import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';

/// A recognizer the test scripts: [support] is what [prepare] answers; each
/// [listen] plays the next entry of [heard] (a sentence, or a [SpeechEvent]
/// such as [SpeechFailed]). With nothing scripted, the listen stays open
/// until [stop] (which reports [onStop]) or [cancel].
///
/// With [untilStop] (hold to talk), the listen stays open and [stop] plays
/// the next scripted entry instead (or [onStop]).
class FakeSpeechToText implements SpeechToText {
  new({
    this.support = SpeechSupport.ready,
    List<Object>? heard,
    this.untilStop = false,
  }) : heard = heard ?? [];

  /// Scripted words come when the mic is released, not at once.
  final bool untilStop;

  SpeechSupport support;
  final List<Object> heard;

  /// What [stop] reports when nothing was scripted.
  SpeechEvent onStop = const SpeechFailed(SpeechError.noSpeech);

  /// [stop] is noted but the recognizer doesn't answer (yet).
  bool stopHangs = false;

  final calls = <String>[];
  StreamController<SpeechEvent>? _open;

  /// Holds [prepare] until completed (a slow recognizer).
  Completer<void>? prepareGate;

  @override
  Future<SpeechSupport> prepare(SpokenLanguage language) async {
    calls.add('prepare ${language.name}');
    await prepareGate?.future;
    return support;
  }

  /// The phrases of the last listen.
  List<String> phrases = const [];

  @override
  Stream<SpeechEvent> listen(
    SpokenLanguage language, {
    List<String> phrases = const [],
  }) {
    calls.add('listen ${language.name}');
    this.phrases = phrases;
    final out = _open = StreamController<SpeechEvent>();
    if (heard.isNotEmpty && !untilStop) {
      final next = heard.removeAt(0);
      scheduleMicrotask(() {
        out
          ..add(const SpeechPartial('…'))
          ..add(next is SpeechEvent ? next : SpeechFinal(next as String));
        unawaited(out.close());
      });
    }
    return out.stream;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    final out = _open;
    if (out == null || out.isClosed) return;
    if (stopHangs) return;
    if (untilStop && heard.isNotEmpty) {
      final next = heard.removeAt(0);
      out.add(next is SpeechEvent ? next : SpeechFinal(next as String));
    } else {
      out.add(onStop);
    }
    await out.close();
  }

  /// The microphone's loudness during the open listen (0..1).
  void level(double v) {
    final out = _open;
    if (out != null && !out.isClosed) out.add(SpeechLevel(v));
  }

  /// Whether a listen is open now.
  bool get listening => !(_open?.isClosed ?? true);

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    await _open?.close();
  }
}

/// Answers [answer] to [request]; [check] answers [current] (what the
/// phone settings say), which [request] updates.
class FakeMicPermissions implements MicPermissions {
  new({
    this.answer = MicPermission.granted,
    this.current = MicPermission.denied,
  });

  MicPermission answer;
  MicPermission current;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<MicPermission> request() async {
    requests++;
    return current = answer;
  }

  @override
  Future<MicPermission> check() async => current;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}
