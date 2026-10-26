import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_sequencer.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/device/haptics.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/profile/onboarding_store.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/speech/mic_permissions.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/core/speech/speech_to_text.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'talk_speech_controller.g.dart';

/// The mic card's state.
enum MicState {
  idle,

  /// Checking the permission and getting the recognizer ready.
  preparing,

  /// Recording: the mic is held (or, in tap mode, was tapped on).
  listening,

  /// Released: waiting for the recognizer's last words.
  finishing,

  /// The microphone was refused this time (D4: "Allow").
  permissionNeeded,

  /// Refused for good (D5: "Open settings").
  permissionBlocked,

  /// The phone has no speech recognizer (D6).
  unavailable,

  /// The recognizer can't do the spoken language (D7 / D8).
  languageMissing,
}

/// A one-off result the mic card shows until the next tap.
enum MicNotice {
  none,

  /// D9: nothing was heard.
  nothingHeard,

  /// The recognizer failed for another reason (network, busy…).
  failed,

  /// Released before recording really started (under [TalkSpeech.minHold]):
  /// nothing was sent; hold the mic while speaking.
  tooShort,
}

/// Speech → sign on Talk (sign rule 7, Q-T3).
@immutable
class TalkSpeechState {
  const new({
    this.mic = MicState.idle,
    this.notice = MicNotice.none,
    this.sentence = const [],
    this.active,
    this.signing = false,
    this.faceToFace = false,
    this.privacyNotice = false,
    this.recordingSince,
  });

  /// When recording started (the timer on the mic card), while listening.
  final DateTime? recordingSince;

  final MicState mic;
  final MicNotice notice;

  /// The last heard sentence, as the avatar signs it (the caption).
  final List<SignSegment> sentence;

  /// The segment of [sentence] being signed now.
  final int? active;
  final bool signing;

  /// Face to face: the mic card turns toward the person opposite.
  final bool faceToFace;

  /// D19 (Q-T3): shown once, from the first use of the mic until dismissed.
  final bool privacyNotice;

  TalkSpeechState copyWith({
    MicState? mic,
    MicNotice? notice,
    List<SignSegment>? sentence,
    int? Function()? active,
    bool? signing,
    bool? faceToFace,
    bool? privacyNotice,
    DateTime? Function()? recordingSince,
  }) => TalkSpeechState(
    mic: mic ?? this.mic,
    notice: notice ?? this.notice,
    sentence: sentence ?? this.sentence,
    active: active == null ? this.active : active(),
    signing: signing ?? this.signing,
    faceToFace: faceToFace ?? this.faceToFace,
    privacyNotice: privacyNotice ?? this.privacyNotice,
    recordingSince: recordingSince == null
        ? this.recordingSince
        : recordingSince(),
  );
}

/// Mic → the phone's recognizer → [SpeechToSign] (exact matches only) →
/// the avatar, segment by segment → the feed ("them").
@Riverpod(keepAlive: true)
class TalkSpeech extends _$TalkSpeech {
  /// The phone store key of "the privacy line was shown" (D19).
  static const kPrivacySeen = 'talk.privacySeen';

  static final _log = Log('talk');

  SignSequencer? _sequencer;
  StreamSubscription<SpeechEvent>? _listen;
  DateTime Function() _now = clock.now;

  /// Tests fix the clock.
  @visibleForTesting
  // A setter would hide that this is a test hook.
  // ignore: use_setters_to_change_properties
  void setClock(DateTime Function() now) => _now = now;

  @override
  TalkSpeechState build() {
    ref.onDispose(() {
      _maxTimer?.cancel();
      _level.dispose();
      unawaited(_listen?.cancel());
      unawaited(_sequencer?.dispose());
    });
    // Q-D4: "I speak" opens Talk face to face.
    return TalkSpeechState(
      faceToFace: ref.read(profileControllerProvider).role == UserRole.speak,
    );
  }

  SpokenLanguage get _language => ref.read(profileControllerProvider).spoken;

  /// Recording shorter than this is thrown away ([MicNotice.tooShort]).
  static const minHold = Duration(milliseconds: 400);

  /// Recording stops by itself after this, as if released.
  static const maxRecording = Duration(seconds: 60);

  /// Tests shorten [maxRecording].
  @visibleForTesting
  Duration maxRecordingForTest = maxRecording;

  /// The microphone's loudness while recording, 0..1 (the live level
  /// indicator; kept out of [state] so the screen doesn't rebuild with it).
  ValueListenable<double> get level => _level;
  final _level = ValueNotifier<double>(0);

  /// Goldens show a fixed level.
  @visibleForTesting
  // A setter would need a getter; this is a test hook.
  // ignore: use_setters_to_change_properties
  void setLevelForTest(double v) => _level.value = v;

  /// The segments of the sentences heard this session, by message (text
  /// and time), so the feed can grey the words that had no sign. Not
  /// stored: older messages show plain (never a wrong mark).
  final _heard = <(String, DateTime), List<SignSegment>>{};
  static const _heardKept = 200;

  /// How [message] was signed, if it was heard this session.
  List<SignSegment>? segmentsFor(TalkMessage message) =>
      _heard[(message.text, message.at)];

  /// The mic is held down (or, in tap mode, recording was asked for).
  bool _held = false;

  /// Slid away to cancel before recording started.
  bool _cancelledEarly = false;
  Timer? _maxTimer;

  /// Hold to talk (2026-10-26): the mic is pressed. Recording starts as
  /// soon as the permission and the recognizer are ready, if the mic is
  /// still held then.
  Future<void> pressMic() async {
    if (state.mic == MicState.preparing) {
      // pressed again while still getting ready: it is held now
      _held = true;
      _cancelledEarly = false;
      return;
    }
    if (state.mic == MicState.listening || state.mic == MicState.finishing) {
      return;
    }
    _held = true;
    _cancelledEarly = false;
    _sequencer?.cancel();
    state = state.copyWith(mic: MicState.preparing, notice: MicNotice.none);
    if (!await _ensurePermission()) {
      _held = false;
      return;
    }
    _showPrivacyOnce();
    final stt = ref.read(speechToTextProvider);
    final support = await stt.prepare(_language);
    if (!ref.mounted) return;
    if (support == SpeechSupport.busy) {
      _held = false;
      state = state.copyWith(mic: MicState.idle, notice: MicNotice.failed);
      return;
    }
    if (support != SpeechSupport.ready) {
      _held = false;
      state = state.copyWith(
        mic: support == SpeechSupport.unavailable
            ? MicState.unavailable
            : MicState.languageMissing,
      );
      return;
    }
    final phrases = await _phrases();
    if (!ref.mounted) return;
    // the last listen's subscription goes before the new one (no await
    // between the checks below and the listen)
    await _listen?.cancel();
    _listen = null;
    if (!ref.mounted) return;
    if (!_held) {
      // let go (or cancelled) before recording started: nothing recorded
      state = state.copyWith(
        mic: MicState.idle,
        notice: _cancelledEarly ? MicNotice.none : MicNotice.tooShort,
      );
      return;
    }
    _level.value = 0;
    state = state.copyWith(
      mic: MicState.listening,
      recordingSince: () => _now(),
    );
    ref.read(hapticsProvider).tap().ignore();
    _maxTimer?.cancel();
    _maxTimer = Timer(maxRecordingForTest, () => unawaited(releaseMic()));
    _listen = stt
        .listen(_language, phrases: phrases)
        .listen(_onSpeech, onDone: _onListenDone);
  }

  /// The mic is let go: under [minHold] the recording is thrown away,
  /// otherwise the recognizer's last words are the sentence.
  Future<void> releaseMic({bool checkLength = true}) async {
    _held = false;
    if (state.mic != MicState.listening) return;
    _maxTimer?.cancel();
    final since = state.recordingSince;
    if (checkLength && since != null && _now().difference(since) < minHold) {
      await _discard(MicNotice.tooShort);
      return;
    }
    state = state.copyWith(mic: MicState.finishing, recordingSince: () => null);
    await ref.read(speechToTextProvider).stop();
  }

  /// Slide to cancel (or the screen reader's "Cancel recording"): the
  /// recording is thrown away.
  Future<void> cancelMic() async {
    _held = false;
    if (state.mic == MicState.preparing) _cancelledEarly = true;
    if (state.mic != MicState.listening) return;
    await _discard(MicNotice.none);
  }

  Future<void> _discard(MicNotice notice) async {
    _maxTimer?.cancel();
    await _listen?.cancel();
    _listen = null;
    state = state.copyWith(
      mic: MicState.idle,
      notice: notice,
      recordingSince: () => null,
    );
    _level.value = 0;
    await ref.read(speechToTextProvider).cancel();
  }

  /// Tap mode (screen reader, Switch Access, or Settings › Tap to start and
  /// stop): a tap starts recording, the next one sends it.
  Future<void> tapMic() async {
    if (state.mic == MicState.listening) {
      await releaseMic(checkLength: false);
      return;
    }
    await pressMic();
  }

  /// D4's "Allow": asks again. Recording then needs a new press.
  Future<void> allowMic() async {
    if (await _ensurePermission()) {
      state = state.copyWith(mic: MicState.idle, notice: MicNotice.none);
    }
  }

  /// D5's "Open settings".
  Future<void> openSettings() =>
      ref.read(micPermissionsProvider).openSettings();

  /// Back from the phone's settings (app resumed): a permission given there
  /// clears the card.
  Future<void> recheck() async {
    if (state.mic != MicState.permissionNeeded &&
        state.mic != MicState.permissionBlocked) {
      return;
    }
    if (await ref.read(micPermissionsProvider).check() ==
        MicPermission.granted) {
      state = state.copyWith(mic: MicState.idle);
    }
  }

  Future<bool> _ensurePermission() async {
    final perms = ref.read(micPermissionsProvider);
    var p = await perms.check();
    if (p != MicPermission.granted) p = await perms.request();
    switch (p) {
      case MicPermission.granted:
        return true;
      case MicPermission.denied:
        state = state.copyWith(mic: MicState.permissionNeeded);
      case MicPermission.permanentlyDenied:
        state = state.copyWith(mic: MicState.permissionBlocked);
    }
    return false;
  }

  void _showPrivacyOnce() {
    final kv = ref.read(keyValueStoreProvider);
    if (kv.getBool(kPrivacySeen) ?? false) return;
    state = state.copyWith(privacyNotice: true);
    kv.setBool(kPrivacySeen, value: true).ignore();
  }

  void dismissPrivacy() => state = state.copyWith(privacyNotice: false);

  /// S7-27: every word and phrase of the signs the avatar can perform, in
  /// the spoken language, to bias the recognizer. A catalogue that can't
  /// load means no biasing (the listen still works).
  Future<List<String>> _phrases() async {
    try {
      final catalogue = await ref.read(signCatalogueProvider.future);
      return {
        for (final s in catalogue.signs)
          if (s.avatar) ...s.wordsIn(_language).variants,
      }.toList();
    } on Object catch (e) {
      _log.warn('phrases_failed', {'error': '$e'});
      return const [];
    }
  }

  /// The listen closed without a final result or a failure (never
  /// expected from [PlatformSpeechToText]): never stay stuck recording.
  void _onListenDone() {
    if (!ref.mounted) return;
    if (state.mic != MicState.listening && state.mic != MicState.finishing) {
      return;
    }
    _held = false;
    _maxTimer?.cancel();
    _level.value = 0;
    state = state.copyWith(
      mic: MicState.idle,
      notice: MicNotice.nothingHeard,
      recordingSince: () => null,
    );
  }

  void _onSpeech(SpeechEvent e) {
    if (e is! SpeechPartial && e is! SpeechLevel) {
      // the listen is over (a final result, or a failure)
      _held = false;
      _maxTimer?.cancel();
      _level.value = 0;
      state = state.copyWith(recordingSince: () => null);
    }
    switch (e) {
      case SpeechPartial():
        // The prototype shows "Listening…" only; the sentence is signed
        // when it is complete.
        break;
      case SpeechLevel(:final level):
        _level.value = level;
      case SpeechFinal(:final text):
        state = state.copyWith(mic: MicState.idle);
        unawaited(_sign(text));
      case SpeechFailed(:final error):
        _log.info('listen_failed', {'error': error.name});
        state = switch (error) {
          SpeechError.noSpeech => state.copyWith(
            mic: MicState.idle,
            notice: MicNotice.nothingHeard,
          ),
          SpeechError.languageMissing => state.copyWith(
            mic: MicState.languageMissing,
          ),
          SpeechError.permission => state.copyWith(
            mic: MicState.permissionNeeded,
          ),
          SpeechError.other => state.copyWith(
            mic: MicState.idle,
            notice: MicNotice.failed,
          ),
        };
    }
  }

  /// Signs [text] and adds it to the feed when the avatar is done with it
  /// (or stopped: the sentence was still heard).
  Future<void> _sign(String text) async {
    // taken first: the sentence was heard even if Talk closes mid-sign
    final conversation = ref.read(conversationRepositoryProvider);
    try {
      final catalogue = await ref.read(signCatalogueProvider.future);
      final segments = SpeechToSign.match(text, catalogue, _language);
      final trace = ref.read(speechTraceProvider);
      if (trace.enabled) {
        trace('match', {
          'language': _language.name,
          'heard': text,
          'segments': SpeechToSign.explain(segments, catalogue, _language),
        });
      }
      await _play(segments);
      final at = _now();
      _heard[(text, at)] = segments;
      if (_heard.length > _heardKept) _heard.remove(_heard.keys.first);
      await conversation.add(
        TalkMessage(side: MessageSide.them, text: text, at: at),
      );
    } on Object catch (e, st) {
      // The catalogue or the avatar couldn't load: say so, never guess.
      _log.failure(
        'sign_failed',
        UnexpectedFailure('speech → sign', cause: e, stackTrace: st),
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        notice: MicNotice.failed,
        active: () => null,
        signing: false,
      );
    }
  }

  /// The avatar card's Replay: the last sentence again (not added twice).
  Future<void> replay() async {
    if (state.sentence.isEmpty ||
        state.mic == MicState.listening ||
        state.mic == MicState.finishing) {
      return;
    }
    await _play(state.sentence);
  }

  Future<void> _play(List<SignSegment> segments) async {
    final seq = await _sequencerReady();
    // Talk closed meanwhile: nothing to sign (_sign still saves the sentence)
    if (!ref.mounted) return;
    // S9-1: a heard sentence starts signing
    if (segments.isNotEmpty) ref.read(vibrateProvider).short();
    state = state.copyWith(sentence: segments, active: () => null);
    void follow() {
      if (!ref.mounted) return;
      state = state.copyWith(
        active: () => seq.current.value,
        signing: seq.current.value != null,
      );
    }

    seq.current.addListener(follow);
    try {
      final outcome = await seq.play(
        segments,
        speed: ref.read(signSpeedProvider),
      );
      _log.info('signed', {
        'segments': segments.length,
        'signs': segments.where((s) => s.label != null).length,
        'outcome': outcome.name,
      });
    } finally {
      seq.current.removeListener(follow);
      if (ref.mounted && seq.current.value == null) {
        state = state.copyWith(active: () => null, signing: false);
      }
    }
  }

  /// The sequencer for the avatar that exists now: a new one when the
  /// avatar runtime was rebuilt (new cast or pack), none cached after a
  /// failed load (the next sentence tries again).
  Future<SignSequencer> _sequencerReady() async {
    final avatar = (await ref.read(avatarRuntimeProvider.future)).controller;
    final current = _sequencer;
    if (current != null && current.avatar == avatar) return current;
    unawaited(current?.dispose());
    return _sequencer = SignSequencer(avatar);
  }

  /// The face-to-face button.
  void toggleFaceToFace() =>
      state = state.copyWith(faceToFace: !state.faceToFace);
}
