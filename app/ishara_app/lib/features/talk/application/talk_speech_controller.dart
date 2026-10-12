import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/avatar/avatar_providers.dart';
import 'package:ishara_app/core/avatar/sign_sequencer.dart';
import 'package:ishara_app/core/avatar/sign_speed.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/catalogue/speech_to_sign.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
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
  listening,

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
  });

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
  }) => TalkSpeechState(
    mic: mic ?? this.mic,
    notice: notice ?? this.notice,
    sentence: sentence ?? this.sentence,
    active: active == null ? this.active : active(),
    signing: signing ?? this.signing,
    faceToFace: faceToFace ?? this.faceToFace,
    privacyNotice: privacyNotice ?? this.privacyNotice,
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
  DateTime Function() _now = DateTime.now;

  /// Tests fix the clock.
  @visibleForTesting
  // A setter would hide that this is a test hook.
  // ignore: use_setters_to_change_properties
  void setClock(DateTime Function() now) => _now = now;

  @override
  TalkSpeechState build() {
    ref.onDispose(() {
      unawaited(_listen?.cancel());
      unawaited(_sequencer?.dispose());
    });
    // Q-D4: "I speak" opens Talk face to face.
    return TalkSpeechState(
      faceToFace: ref.read(profileControllerProvider).role == UserRole.speak,
    );
  }

  SpokenLanguage get _language => ref.read(profileControllerProvider).spoken;

  /// The mic button: listens, or stops listening (what was heard is used).
  Future<void> tapMic() async {
    if (state.mic == MicState.listening) {
      await ref.read(speechToTextProvider).stop();
      return;
    }
    if (state.mic == MicState.preparing) return;
    _sequencer?.cancel();
    state = state.copyWith(mic: MicState.preparing, notice: MicNotice.none);
    if (!await _ensurePermission()) return;
    _showPrivacyOnce();
    final stt = ref.read(speechToTextProvider);
    final support = await stt.prepare(_language);
    if (support == SpeechSupport.busy) {
      state = state.copyWith(mic: MicState.idle, notice: MicNotice.failed);
      return;
    }
    if (support != SpeechSupport.ready) {
      state = state.copyWith(
        mic: support == SpeechSupport.unavailable
            ? MicState.unavailable
            : MicState.languageMissing,
      );
      return;
    }
    state = state.copyWith(mic: MicState.listening);
    await _listen?.cancel();
    _listen = stt.listen(_language).listen(_onSpeech);
  }

  /// D4's "Allow": asks again.
  Future<void> allowMic() => tapMic();

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

  void _onSpeech(SpeechEvent e) {
    switch (e) {
      case SpeechPartial():
        // The prototype shows "Listening…" only; the sentence is signed
        // when it is complete.
        break;
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
    try {
      final catalogue = await ref.read(signCatalogueProvider.future);
      final segments = SpeechToSign.match(text, catalogue, _language);
      await _play(segments);
      await ref
          .read(conversationRepositoryProvider)
          .add(TalkMessage(side: MessageSide.them, text: text, at: _now()));
    } on Object catch (e, st) {
      // The catalogue or the avatar couldn't load: say so, never guess.
      _log.failure(
        'sign_failed',
        UnexpectedFailure('speech → sign', cause: e, stackTrace: st),
      );
      state = state.copyWith(
        notice: MicNotice.failed,
        active: () => null,
        signing: false,
      );
    }
  }

  /// The avatar card's Replay: the last sentence again (not added twice).
  Future<void> replay() async {
    if (state.sentence.isEmpty || state.mic == MicState.listening) return;
    await _play(state.sentence);
  }

  Future<void> _play(List<SignSegment> segments) async {
    final seq = await _sequencerReady();
    state = state.copyWith(sentence: segments, active: () => null);
    void follow() => state = state.copyWith(
      active: () => seq.current.value,
      signing: seq.current.value != null,
    );
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
      if (seq.current.value == null) {
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
