import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/catalogue/sign_catalogue.dart';
import 'package:ishara_app/core/conversation/conversation_providers.dart';
import 'package:ishara_app/core/conversation/conversation_repository.dart';
import 'package:ishara_app/core/device/haptics.dart';
import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/packs/pack_providers.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/recognition/decider.dart';
import 'package:ishara_app/core/recognition/recognition_providers.dart';
import 'package:ishara_app/core/recognition/recognition_service.dart';
import 'package:ishara_app/core/speech/speech_providers.dart';
import 'package:ishara_app/features/pair/application/reconnect.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'talk_glove_controller.g.dart';

/// Where a live word is (AI-SPEC §7).
enum LiveWordState {
  /// Faded with "…", not spoken.
  tentative,

  /// Normal, spoken.
  confirmed,

  /// Fading out (`cancel`); removed after [TalkGlove.fadeOut].
  cancelled,
}

/// A word in the live box.
@immutable
class LiveWord {
  const new({
    required this.id,
    required this.text,
    required this.spoken,
    required this.state,
    this.label,
    this.byUser = false,
  });

  final int id;

  /// The model label, or null for a typed word.
  final String? label;

  /// What the box shows: the words the voice says, in the voice language
  /// (S7-17), so a sentence reads as it sounds ("me hungry", "I love you").
  final String text;

  /// What the voice says.
  final String spoken;
  final LiveWordState state;

  /// Confirmed by the user's tap (Q-T1), not by the Decider: a later
  /// `cancel` keeps it and a later `confirm` isn't spoken again (S7-9).
  final bool byUser;

  LiveWord copyWith({LiveWordState? state, bool? byUser}) => LiveWord(
    id: id,
    label: label,
    text: text,
    spoken: spoken,
    state: state ?? this.state,
    byUser: byUser ?? this.byUser,
  );
}

/// Glove → text on Talk, and the user's own words (Q-T1, Q-T2, Q-T4).
@immutable
class TalkGloveState {
  const new({
    this.words = const [],
    this.speaking = false,
    this.voiceMissing = false,
    this.recognitionFailed = false,
    this.reconnecting = false,
  });

  final List<LiveWord> words;

  /// Speak is reading the sentence out ("Speaking…").
  final bool speaking;

  /// The phone has no voice for the spoken language (S7-11, D16).
  final bool voiceMissing;

  /// The recognizer failed (D15) until the glove connects again.
  final bool recognitionFailed;

  /// One background reconnect after a drop is running (S7-19, D11).
  final bool reconnecting;

  /// The words that count: confirmed ones (tentative words never do).
  List<LiveWord> get sentence => [
    for (final w in words)
      if (w.state == LiveWordState.confirmed) w,
  ];

  TalkGloveState copyWith({
    List<LiveWord>? words,
    bool? speaking,
    bool? voiceMissing,
    bool? recognitionFailed,
    bool? reconnecting,
  }) => TalkGloveState(
    words: words ?? this.words,
    speaking: speaking ?? this.speaking,
    voiceMissing: voiceMissing ?? this.voiceMissing,
    recognitionFailed: recognitionFailed ?? this.recognitionFailed,
    reconnecting: reconnecting ?? this.reconnecting,
  );
}

@Riverpod(keepAlive: true)
class TalkGlove extends _$TalkGlove {
  /// How long a cancelled word fades before it goes.
  static const fadeOut = Duration(milliseconds: 300);

  static final _log = Log('talk_glove');

  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _end;
  int _nextId = 1;

  /// Labels of tentative words the user tapped (Q-T1) whose Decider
  /// `confirm` hasn't come yet: that confirm is the same word, already
  /// spoken (S7-9). A new `tentative` of the label means the Decider moved on.
  final Set<String> _tappedAwaitingConfirm = {};
  int _speakGen = 0;
  SignCatalogue? _catalogue;
  Duration? _timeout;
  bool _wasReady = false;
  bool _active = true;
  DateTime Function() _now = DateTime.now;

  /// Talk is visible (the screen says so). Hidden (another tab, Learn's
  /// practice), the glove's words are not Talk's: not shown, not spoken.
  void setActive({required bool active}) {
    if (active == _active) return;
    _active = active;
    if (!active) {
      // Their confirm / cancel won't be seen now: a faded word left behind
      // could later be tapped and spoken although the Decider rejected it.
      // The screen calls this while building (visibility, dispose), so the
      // state changes right after.
      scheduleMicrotask(() {
        if (!ref.mounted || _active) return;
        state = state.copyWith(
          words: [
            for (final w in state.words)
              if (w.state == LiveWordState.confirmed) w,
          ],
        );
      });
    }
  }

  /// Tests fix the clock.
  @visibleForTesting
  // A setter would hide that this is a test hook.
  // ignore: use_setters_to_change_properties
  void setClock(DateTime Function() now) => _now = now;

  @override
  TalkGloveState build() {
    ref
      ..onDispose(() {
        _end?.cancel();
        for (final s in _subs) {
          unawaited(s.cancel());
        }
      })
      // S7-17: the voice follows the spoken-language setting.
      ..listen(profileControllerProvider, (before, now) {
        if (before?.spoken != now.spoken) unawaited(_setVoice(now.spoken));
      })
      ..listen(gloveStatusProvider, (_, next) {
        if (next.value case final s?) _onGlove(s);
      })
      // The recognizer is rebuilt when the glove source changes (developer
      // switch): follow the new one.
      ..listen(recognitionFeedProvider, (_, next) {
        if (next.value case final feed?) _subscribe(feed);
      }, fireImmediately: true);
    // A glove already connected when Talk starts counts (else the
    // reconnect after its first drop would be missed). Read, not listened
    // with fireImmediately: that would change the state inside build.
    _wasReady = ref.read(gloveSourceProvider).status.phase == GlovePhase.ready;
    unawaited(_start());
    return const TalkGloveState();
  }

  void _subscribe(RecognitionFeed feed) {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs
      ..clear()
      ..add(feed.events.listen(_onEvent))
      ..add(
        feed.errors.listen((f) {
          _log.failure('recognition_failed', f);
          state = state.copyWith(recognitionFailed: true);
        }),
      );
  }

  SpokenLanguage get _language => ref.read(profileControllerProvider).spoken;

  Future<void> _start() async {
    try {
      _catalogue = await ref.read(signCatalogueProvider.future);
      _timeout = await ref.read(conversationTimeoutProvider.future);
      await ref.read(recognitionFeedProvider.future);
    } on Object catch (e, st) {
      _log.warn('start_failed', {'error': '$e', 'stack': '$st'});
      // Talk may be gone by now (the loads take a while on a device)
      if (!ref.mounted) return;
      state = state.copyWith(recognitionFailed: true);
    }
    if (!ref.mounted) return;
    await _setVoice(_language);
  }

  Future<void> _setVoice(SpokenLanguage language) async {
    final ok = await ref.read(textToSpeechProvider).setLanguage(language);
    if (!ref.mounted) return;
    state = state.copyWith(voiceMissing: !ok);
  }

  // ---- the glove (S7-19) ----

  void _onGlove(GloveStatus s) {
    final ready = s.phase == GlovePhase.ready;
    if (ready) {
      // A new connection: recognition starts again (D15 clears).
      if (!_wasReady) state = state.copyWith(recognitionFailed: false);
    } else if (_wasReady &&
        s.phase == GlovePhase.idle &&
        s.failure != null &&
        !state.reconnecting) {
      // The link dropped (not a disconnect the user asked for): one try.
      unawaited(_reconnect());
    }
    _wasReady = ready;
  }

  Future<void> _reconnect() async {
    state = state.copyWith(reconnecting: true);
    try {
      final ok = await reconnectToPairedGlove(ref);
      _log.info('reconnect_after_drop', {'connected': ok});
    } finally {
      if (ref.mounted) state = state.copyWith(reconnecting: false);
    }
  }

  // ---- Decider events (AI-SPEC §5, §7) ----

  void _onEvent(RecognitionEvent e) {
    if (!_active) return;
    final cat = _catalogue;
    final sign = cat?.byLabel(e.label);
    if (sign == null) {
      // A model label without a catalogue entry can't happen (the
      // catalogue is checked against labels.txt); never show a guess.
      _log.warn('unknown_label', {'label': e.label});
      return;
    }
    final words = sign.wordsIn(_language);
    switch (e.kind) {
      case DeciderEventKind.tentative:
        _tappedAwaitingConfirm.remove(e.label);
        _add(e.label, words.spoken, words.spoken, LiveWordState.tentative);
      case DeciderEventKind.word:
        _add(e.label, words.spoken, words.spoken, LiveWordState.confirmed);
        _say(words.spoken);
        ref.read(vibrateProvider).short(); // S9-1: a glove word
      case DeciderEventKind.confirm:
        final i = _lastPending(e.label);
        if (i == null) {
          // Already confirmed by the user's tap (S7-9): not spoken again.
          if (_tappedAwaitingConfirm.remove(e.label)) return;
          // The tentative word was cleared away, but the Decider says it
          // was a real sign: it starts the new sentence.
          _add(e.label, words.spoken, words.spoken, LiveWordState.confirmed);
        } else {
          _replace(i, state.words[i].copyWith(state: LiveWordState.confirmed));
        }
        _say(words.spoken);
        ref.read(vibrateProvider).short(); // S9-1: a glove word
      case DeciderEventKind.cancel:
        final i = _lastPending(e.label);
        if (i == null) return; // confirmed by the user's tap: kept (S7-9)
        final id = state.words[i].id;
        _replace(i, state.words[i].copyWith(state: LiveWordState.cancelled));
        Timer(fadeOut, () {
          if (!ref.mounted) return;
          state = state.copyWith(
            words: [
              for (final w in state.words)
                if (w.id != id) w,
            ],
          );
        });
    }
  }

  int? _lastPending(String label) {
    for (var i = state.words.length - 1; i >= 0; i--) {
      final w = state.words[i];
      if (w.label == label && w.state == LiveWordState.tentative) return i;
    }
    return null;
  }

  void _add(String? label, String text, String spoken, LiveWordState s) =>
      state = state.copyWith(
        words: [
          ...state.words,
          LiveWord(
            id: _nextId++,
            label: label,
            text: text,
            spoken: spoken,
            state: s,
          ),
        ],
      );

  void _replace(int i, LiveWord w) =>
      state = state.copyWith(words: [...state.words]..[i] = w);

  /// Speaks [text] and restarts the end-of-conversation clock (S7-21).
  void _say(String text) {
    unawaited(_speak(text));
    _restartEnd();
  }

  /// S7-11: with no voice for the spoken language nothing is spoken (the
  /// engine would read it with another language's voice).
  Future<void> _speak(String text) async {
    if (state.voiceMissing) return;
    await ref.read(textToSpeechProvider).speak(text);
  }

  void _restartEnd() {
    _end?.cancel();
    final t = _timeout;
    if (t != null) _end = Timer(t, endSentence);
  }

  // ---- the user ----

  /// Q-T1: tapping a tentative word confirms it and speaks it; logged as a
  /// user confirmation, not a Decider event.
  void confirmByTap(int id) {
    final i = state.words.indexWhere(
      (w) => w.id == id && w.state == LiveWordState.tentative,
    );
    if (i < 0) return;
    final w = state.words[i];
    _replace(i, w.copyWith(state: LiveWordState.confirmed, byUser: true));
    final label = w.label;
    if (label != null) _tappedAwaitingConfirm.add(label);
    _log.info('user_confirm', {'label': w.label});
    _say(w.spoken);
    ref.read(vibrateProvider).short(); // S9-1: a glove word
  }

  /// Q-T2: typed words join the sentence and are spoken when sent.
  void sendTyped(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    for (final w in t.split(RegExp(r'\s+'))) {
      _add(null, w, w, LiveWordState.confirmed);
    }
    _say(t);
  }

  /// Q-T2: Speak repeats the current sentence (S7-22: not when empty).
  Future<void> speakSentence() async {
    final text = _spokenText(state.sentence);
    if (text.isEmpty || state.speaking) return;
    if (state.voiceMissing) return;
    final gen = ++_speakGen;
    state = state.copyWith(speaking: true);
    try {
      await _speak(text);
    } finally {
      if (ref.mounted && gen == _speakGen) {
        state = state.copyWith(speaking: false);
      }
    }
  }

  /// Q-T2: the conversation ended (S7-21) or the user tapped Clear: the
  /// confirmed words go to the feed as the user's message; tentative words
  /// are dropped (S7-20).
  Future<void> endSentence() async {
    _end?.cancel();
    final sentence = state.sentence;
    state = state.copyWith(words: const []);
    if (sentence.isEmpty) return;
    await ref
        .read(conversationRepositoryProvider)
        .add(
          TalkMessage(
            side: MessageSide.me,
            text: [for (final w in sentence) w.text].join(' '),
            at: _now(),
          ),
        );
  }

  /// Talk's Clear (Q-T2): the sentence goes to the feed, and the next
  /// message starts a new conversation (S9-4).
  Future<void> clear() async {
    await endSentence();
    await ref.read(conversationRepositoryProvider).startNewConversation();
  }

  /// S7-18: a quick phrase (SOS too: Q-T4): the current sentence goes to
  /// the feed first, then the phrase is spoken and added on its own.
  Future<void> quickPhrase(String text) async {
    await endSentence();
    unawaited(_speak(text));
    await ref
        .read(conversationRepositoryProvider)
        .add(TalkMessage(side: MessageSide.me, text: text, at: _now()));
  }

  static String _spokenText(List<LiveWord> words) =>
      [for (final w in words) w.spoken].join(' ');
}
