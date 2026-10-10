import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ishara_app/core/avatar/avatar_cast.dart';
import 'package:ishara_app/core/avatar/avatar_events.dart';
import 'package:ishara_app/core/avatar/avatar_library.dart';
import 'package:ishara_app/core/logging/log.dart';

/// The avatar page as the controller sees it: messages out of the page and
/// a way to hand it a command. The app implements it with a WebView
/// (`WebViewAvatarPage`); tests use a fake.
abstract interface class AvatarPage {
  /// JSON messages the page posted (`IsharaBridge.postMessage`).
  Stream<String> get messages;

  /// Runs `window.__ishara.receive(command)` in the page.
  Future<void> send(Map<String, Object?> command);
}

/// Where the avatar is.
enum AvatarStatus {
  /// The page or the first character is still loading.
  loading,

  /// The character is on screen and plays signs.
  ready,

  /// The avatar can't run (no WebGL, missing files). The app keeps the
  /// placeholder; captions still work.
  failed,
}

/// The one typed way to drive the avatar (prompt › Avatar).
///
/// Calls: [play], [noSign], [stop], [setCharacter], [customize], plus
/// framing and preview helpers. Events: [events] (ready, signStarted,
/// signEnded, error, …). Commands made before the page is up are queued and
/// sent in order once it is.
class AvatarController {
  new({
    required AvatarPage page,
    required this._library,
    required this.libraryUrl,
    required this.castUrl,
    String? character,
    this._cast,
    this._reduceMotion = false,
  }) : _page = page {
    _character = character == null ? null : _resolve(character);
    _sub = page.messages.listen(_onMessage);
  }

  static final _log = Log('avatar');

  /// Errors after which the avatar can't show anything.
  static const _fatal = {
    'webgl',
    'three_load',
    'init',
    'data',
    'character',
    'unsupported',
    'page',
  };

  final AvatarPage _page;
  final AvatarLibrary _library;

  /// Page-relative URLs of the pack's library and of the cast list.
  final String libraryUrl;
  final String castUrl;

  String? _character;

  /// When given, ids go through it: a hidden character (RB-1) becomes the
  /// default, so [character] never names one.
  final AvatarCast? _cast;

  String _resolve(String id) => _cast?.byId(id).id ?? id;
  bool _reduceMotion;
  bool _pageUp = false;
  bool _disposed = false;
  int _nextId = 1;
  final List<Map<String, Object?>> _queue = [];

  /// Signs sent to the page and not ended yet (id → label, null = no sign).
  final Map<int, String?> _open = {};

  // State a reloaded page must get back (it starts from scratch).
  bool _paused = false;
  bool _statsOn = false;
  double _captionHeight = 0;
  Map<String, Object?>? _tint;
  late final StreamSubscription<String> _sub;
  final _events = StreamController<AvatarEvent>.broadcast();

  /// Ready / loading / failed. Listenable for widgets (the placeholder).
  final ValueNotifier<AvatarStatus> status = ValueNotifier(
    AvatarStatus.loading,
  );

  Stream<AvatarEvent> get events => _events.stream;

  /// The labels this avatar can perform (the pack's library).
  AvatarLibrary get library => _library;

  /// The character asked for last (null = the cast default).
  String? get character => _character;

  /// Plays [label] at [speed] (clamped 0.4–2), looping if [loop] (0.8 s
  /// pause between plays, as the prototype). Returns the id its
  /// [SignStarted] / [SignEnded] events carry.
  ///
  /// [label] must be in [library]: mapping words to labels is the
  /// catalogue's job, and an unknown label is a bug, never a guess.
  int play(String label, {double speed = 1, bool loop = false}) {
    if (!_library.has(label)) {
      throw ArgumentError.value(label, 'label', 'not in the avatar library');
    }
    final id = _nextId++;
    _send({
      'cmd': 'play',
      'id': id,
      'label': label,
      'speed': AvatarLibrary.clampSpeed(speed),
      'loop': loop,
    });
    return id;
  }

  /// A word with no sign: the avatar stays in the ready pose and its mouth
  /// moves briefly (prototype); the caption carries the word.
  int noSign({double speed = 1}) {
    final id = _nextId++;
    _send({
      'cmd': 'noSign',
      'id': id,
      'speed': AvatarLibrary.clampSpeed(speed),
    });
    return id;
  }

  /// Ends the current sign (and its loop); back to the ready pose.
  void stop() => _send({'cmd': 'stop'});

  /// Shows [id] (an `AvatarCast` id). With [greet] it then waves the pack's
  /// greeting at 0.8x if the avatar is idle (prototype); that sign has no
  /// id (its events carry id null).
  void setCharacter(String id, {bool greet = true}) {
    final shown = _character = _resolve(id);
    _send({'cmd': 'setCharacter', 'character': shown, 'greet': greet});
  }

  /// Tints skin / outfit (prototype `customize`; Avatar studio v1 doesn't
  /// offer it, Q-A2).
  void customize({int? skin, int? outfit}) {
    _tint = {'cmd': 'customize', 'skin': skin, 'outfit': outfit};
    _send(_tint!);
  }

  /// The caption strip's height in logical pixels (0 = none): the camera
  /// keeps the signing space above it.
  void reframe({double captionHeight = 0}) {
    _captionHeight = captionHeight;
    _send({'cmd': 'reframe', 'captionPx': captionHeight});
  }

  /// Stops / restarts rendering (no slot on screen, app in background).
  /// Pausing also ends the current sign (interrupted): nobody saw it.
  void pause() {
    _paused = true;
    _send({'cmd': 'pause'});
  }

  void resume() {
    _paused = false;
    _send({'cmd': 'resume'});
  }

  /// The OS "reduce motion" setting: no idle sway, no talking mouth.
  void setReduceMotion({required bool on}) {
    if (on == _reduceMotion) return;
    _reduceMotion = on;
    _send({'cmd': 'setReduceMotion', 'on': on});
  }

  /// Frame-rate reports ([AvatarStats]) every 2 s while on.
  void setStats({required bool on}) {
    _statsOn = on;
    _send({'cmd': 'stats', 'on': on});
  }

  /// Preview screen: freezes [label] at [t] seconds (speed 1), seen from
  /// [view] degrees (0 = front, -90 = from the signer's right). [label]
  /// null only moves the camera. With [frozen] false the sign plays on.
  void preview({
    String? label,
    double t = 0,
    double view = 0,
    bool frozen = true,
  }) {
    if (label != null && !_library.has(label)) {
      throw ArgumentError.value(label, 'label', 'not in the avatar library');
    }
    _send({
      'cmd': 'preview',
      'label': label,
      't': t,
      'view': view,
      'frozen': frozen,
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    await _sub.cancel();
    await _events.close();
    status.dispose();
  }

  void _send(Map<String, Object?> cmd) {
    if (_disposed) return;
    if (!_pageUp) {
      _queue.add(cmd);
      return;
    }
    _deliver(cmd);
  }

  void _deliver(Map<String, Object?> cmd) {
    if (cmd['cmd'] case 'play' || 'noSign') {
      _open[cmd['id']! as int] = cmd['label'] as String?;
    }
    unawaited(
      _page.send(cmd).catchError((Object e) {
        _emit(AvatarError('page', e.toString()));
      }),
    );
  }

  void _onMessage(String message) {
    if (_disposed) return;
    final e = AvatarEvent.parse(message);
    switch (e) {
      case AvatarPageStarted():
        // The page is (re)loading: commands wait for it, and signs sent to
        // the old page will never end there.
        _pageUp = false;
        status.value = AvatarStatus.loading;
        _endOpenSigns();
      case AvatarLoaded():
        // A fresh page (first load or a reload): it knows nothing yet.
        _pageUp = true;
        status.value = AvatarStatus.loading;
        _endOpenSigns();
        _deliver({
          'cmd': 'init',
          'cast': castUrl,
          'library': libraryUrl,
          'character': ?_character,
          'reduceMotion': _reduceMotion,
        });
        // Replay the state the new page lacks, then the queued commands.
        if (_paused) _deliver({'cmd': 'pause'});
        if (_statsOn) _deliver({'cmd': 'stats', 'on': true});
        if (_captionHeight > 0) {
          _deliver({'cmd': 'reframe', 'captionPx': _captionHeight});
        }
        if (_tint != null) _deliver(_tint!);
        final queued = List.of(_queue);
        _queue.clear();
        queued.forEach(_deliver);
      case SignEnded(:final id):
        _open.remove(id);
      case AvatarReady(:final signs):
        if (!setEquals(signs, _library.labels)) {
          _log.warn('library_mismatch', {
            'page': signs.length,
            'app': _library.labels.length,
          });
          status.value = AvatarStatus.failed;
          _emit(const AvatarError('data', 'the page and app libraries differ'));
          return;
        }
        status.value = AvatarStatus.ready;
      case AvatarError(:final code):
        _log.warn('avatar_error', {'code': code, 'message': e.message});
        if (status.value != AvatarStatus.ready && _fatal.contains(code)) {
          status.value = AvatarStatus.failed;
        }
      case AvatarContextRestored():
        _log.info('context_restored');
      default:
        break;
    }
    _emit(e);
  }

  void _endOpenSigns() {
    final open = Map.of(_open);
    _open.clear();
    for (final MapEntry(:key, :value) in open.entries) {
      _emit(SignEnded(id: key, label: value, interrupted: true));
    }
  }

  void _emit(AvatarEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
