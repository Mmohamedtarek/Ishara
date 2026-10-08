import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/glove_transport.dart';
import 'package:ishara_app/core/logging/log.dart';
import 'package:ishara_app/core/recognition/calibration.dart';

/// Optional capability of a transport: react to Learn's "Sign now" (the mock
/// glove plays a practice recording; real radios don't implement it).
abstract interface class PracticeCueSink {
  void cuePractice(String label);
}

/// The app side of BLE-CONTRACT v1 over any [GloveTransport]: connection
/// setup, command / reply matching, EVENT lines and DATA frames. The mock
/// glove and the real glove both go through this class.
class GloveClient implements GloveSource {
  new(
    this._transport, {
    this.replyTimeout = const Duration(milliseconds: 1500),
    this.firstBatteryWait = const Duration(seconds: 2),
  });

  final GloveTransport _transport;

  /// How long to wait for a command reply. The contract promises 500 ms; the
  /// margin covers radio jitter and multi-notification replies (`#CAL`).
  final Duration replyTimeout;

  /// How long to wait for the `#BAT` sent when EVENT is subscribed.
  final Duration firstBatteryWait;

  final _log = Log('glove');
  final _statusCtl = StreamController<GloveStatus>.broadcast(sync: true);
  final _samplesCtl = StreamController<List<GloveSample>>.broadcast(sync: true);
  final _eventsCtl = StreamController<GloveEvent>.broadcast(sync: true);
  final _lines = LineAssembler();

  GloveStatus _status = const GloveStatus();
  GloveLink? _link;
  final List<StreamSubscription<Object?>> _subs = [];
  Completer<void>? _firstBattery;

  /// Commands waiting for their reply, in send order. Normally one; `CAL
  /// CANCEL` is sent while a calibration step is still waiting (BLE §5, §7).
  final List<_Pending> _pendings = [];
  Future<void> _queue = Future.value();
  bool _closing = false;
  bool _disposed = false;
  int _badFrames = 0;

  /// DATA notifications that weren't valid frames since connecting.
  int get badFrames => _badFrames;

  @override
  GloveStatus get status => _status;

  @override
  Stream<GloveStatus> get statusChanges => _statusCtl.stream;

  @override
  Stream<List<GloveSample>> get samples => _samplesCtl.stream;

  @override
  Stream<GloveEvent> get events => _eventsCtl.stream;

  void _set(GloveStatus s) {
    _status = s;
    if (!_statusCtl.isClosed) _statusCtl.add(s);
  }

  // ---------------------------------------------------------------- scanning

  @override
  Stream<List<DiscoveredGlove>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    if (_status.isConnected) await disconnect();
    _set(_status.copyWith(phase: GlovePhase.scanning, clearFailure: true));
    try {
      yield* _transport.scan(timeout: timeout);
    } finally {
      if (_status.phase == GlovePhase.scanning) {
        _set(_status.copyWith(phase: GlovePhase.idle));
      }
    }
  }

  // -------------------------------------------------------------- connecting

  /// Bumped by every connect and disconnect: a connect whose number is no
  /// longer current was superseded (or the client disposed) and must not
  /// touch the state or keep its link.
  int _generation = 0;

  @override
  Future<void> connect(DiscoveredGlove glove) async {
    if (_disposed) throw StateError('disposed');
    await disconnect(); // closes a link, or cancels a connect in progress
    final gen = ++_generation;
    bool current() => gen == _generation && !_disposed;
    _badFrames = 0;
    _set(GloveStatus(phase: GlovePhase.linking, device: glove));
    _log.info('connect', {'name': glove.name, 'rssi': glove.rssi});
    GloveLink? opened;
    try {
      // Check 1: link, MTU, services (BLE §3 steps 1-3).
      opened = await _transport.open(glove);
      if (!current()) throw const GloveDisconnectedFailure();
      final link = opened;
      _link = link;
      _closing = false;
      unawaited(link.closed.then((_) => _onClosed(link)));

      // Check 2: INFO + proto, EVENT then DATA (steps 3-4).
      _set(_status.copyWith(phase: GlovePhase.checkingSensors));
      final info = _parseInfo(await link.readInfo());
      if (!current()) throw const GloveDisconnectedFailure();
      _set(_status.copyWith(info: info));
      _firstBattery = Completer<void>();
      _subs.add(link.eventNotifications.listen(_onEventBytes));
      await link.subscribeEvents();
      await _firstBattery!.future.timeout(
        firstBatteryWait,
        onTimeout: () => _log.warn('no_battery_line'),
      );
      if (!current()) throw const GloveDisconnectedFailure();
      _subs.add(link.dataNotifications.listen(_onDataBytes));
      await link.subscribeData();

      // Check 3: GETCAL (step 5), then STREAM 1 (step 6).
      _set(_status.copyWith(phase: GlovePhase.readingCalibration));
      await readCalibration();
      await _send('STREAM 1');
      if (!current()) throw const GloveDisconnectedFailure();
      _set(_status.copyWith(phase: GlovePhase.ready));
      _log.info('ready', {'fw': info.firmware, 'mtu': link.mtu});
    } on Object catch (e, st) {
      if (!current()) {
        // Superseded or disposed: whoever bumped the generation owns the
        // state; only make sure this attempt's link is closed.
        if (opened != null && !identical(opened, _link)) await opened.close();
        throw const GloveDisconnectedFailure();
      }
      final f = e is GloveFailure
          ? e
          : GloveConnectFailure('setup failed', cause: e, stackTrace: st);
      await _abort(f);
      if (e is Error) rethrow; // a bug: keep it visible to the crash report
      throw f;
    }
  }

  GloveInfo _parseInfo(Uint8List bytes) {
    Object? j;
    try {
      j = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (e) {
      throw GloveConnectFailure('INFO is not JSON', cause: e);
    }
    if (j is! Map<String, Object?>) {
      throw const GloveConnectFailure('INFO is not an object');
    }
    final m = j;
    final proto = m['proto'];
    if (proto != 1) throw GloveProtocolMismatchFailure(proto);
    int intOr(String k, int d) => switch (m[k]) {
      final int v => v,
      _ => d,
    };
    return GloveInfo(
      proto: 1,
      firmware: switch (m['fw']) {
        final String s => s,
        _ => '',
      },
      board: switch (m['board']) {
        final String s => s,
        _ => '',
      },
      rateHz: intOr('rate_hz', 50),
      channels: intOr('channels', 11),
    );
  }

  Future<void> _abort(GloveFailure f) async {
    _log.failure('connect_failed', f, {'phase': _status.phase.name});
    final link = _link;
    _closing = true;
    _tearDown(f);
    _set(_status.copyWith(phase: GlovePhase.idle, failure: f));
    if (link != null) await link.close();
  }

  @override
  Future<void> disconnect() async {
    _generation++; // cancels a connect in progress
    final link = _link;
    if (link == null) {
      if (_status.isConnected) _set(GloveStatus(device: _status.device));
      return;
    }
    _closing = true;
    try {
      await _send('STREAM 0').timeout(replyTimeout);
    } on Object catch (_) {
      // Best effort: the link is closed next anyway.
    }
    _tearDown(const GloveDisconnectedFailure());
    _set(GloveStatus(device: _status.device));
    await link.close();
  }

  /// Ends the session from the glove side (e.g. it stopped streaming).
  void _endSession(GloveFailure reason) {
    final link = _link;
    if (link == null) return;
    _generation++;
    _closing = true;
    _log.failure('session_ended', reason);
    _tearDown(reason);
    _set(_status.copyWith(phase: GlovePhase.idle, failure: reason));
    unawaited(link.close());
  }

  void _onClosed(GloveLink link) {
    if (!identical(link, _link)) return;
    if (_closing) return;
    _log.warn('link_lost', {'phase': _status.phase.name});
    _generation++; // a connect in progress on this link must stop
    const f = GloveDisconnectedFailure();
    _tearDown(f);
    _set(_status.copyWith(phase: GlovePhase.idle, failure: f));
    // Make sure the radio side lets go too (idempotent).
    unawaited(link.close());
  }

  void _tearDown(GloveFailure reason) {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _lines.clear();
    _link = null;
    final waiting = List.of(_pendings);
    _pendings.clear();
    for (final p in waiting) {
      if (!p.done.isCompleted) p.done.completeError(reason);
    }
    final b = _firstBattery;
    if (b != null && !b.isCompleted) b.complete();
  }

  // ------------------------------------------------------------ EVENT / DATA

  void _onEventBytes(Uint8List bytes) {
    for (final line in _lines.add(bytes)) {
      GloveEvent? e;
      try {
        e = GloveEventParser.parse(line);
      } on ParseFailure catch (f) {
        _log.failure('bad_event_line', f);
        if (line.startsWith('#CAL')) {
          // The reply to GETCAL / CAL SAVE is broken: fail that command now
          // instead of letting it time out.
          for (final p in List.of(_pendings)) {
            if (p.expectsCalibration) {
              _pendings.remove(p);
              p.done.completeError(GloveBadCalibrationFailure(f));
            }
          }
        }
        continue;
      }
      if (e == null) {
        _log.debug('unknown_event_line');
        continue;
      }
      _onEvent(e);
    }
  }

  void _onEvent(GloveEvent e) {
    switch (e) {
      case BatteryEvent():
        _set(_status.copyWith(battery: e));
        final b = _firstBattery;
        if (b != null && !b.isCompleted) b.complete();
      case MpuFailEvent():
        _set(_status.copyWith(mpuFail: true));
      case CalibrationEvent(:final calibration):
        _set(
          _status.copyWith(
            calibration: calibration,
            storedCalibration: StoredCalibration.present,
          ),
        );
      case NoCalibrationEvent():
        _set(_status.copyWith(storedCalibration: StoredCalibration.none));
      case ErrorEvent(command: 'STREAM', reason: 'MTU')
          when !_pendings.any((p) => p.command.startsWith('STREAM')):
        // Unsolicited: the MTU dropped and the glove stopped streaming
        // (BLE §4). This link can't stream any more: end the session so the
        // UI offers to reconnect.
        scheduleMicrotask(() => _endSession(GloveCommandRejectedFailure(e)));
      default:
        break;
    }
    for (final p in _pendings) {
      if (e is FlexWeakEvent && p.isCalStep) p.weakFingers.add(e.finger);
    }
    for (final p in _pendings) {
      if (p.matches(e)) {
        _pendings.remove(p);
        p.done.complete(e);
        break;
      }
    }
    if (!_eventsCtl.isClosed) _eventsCtl.add(e);
  }

  void _onDataBytes(Uint8List bytes) {
    try {
      final samples = FrameCodec.decode(bytes);
      if (!_samplesCtl.isClosed) _samplesCtl.add(samples);
    } on ParseFailure catch (f) {
      _badFrames++;
      _log.failure('bad_frame', f, {'bytes': bytes.length});
    }
  }

  // ---------------------------------------------------------------- commands

  /// Sends [command] and waits for its single reply (BLE §5). Commands are
  /// sent one at a time.
  Future<_Reply> _send(
    String command, {
    Duration? timeout,
    bool skipQueue = false,
  }) {
    if (skipQueue) return _sendNow(command, timeout ?? replyTimeout);
    final run = _queue.then((_) => _sendNow(command, timeout ?? replyTimeout));
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<_Reply> _sendNow(String command, Duration timeout) async {
    final link = _link;
    if (link == null) throw const GloveDisconnectedFailure();
    final p = _Pending(command);
    _pendings.add(p);
    // Listen before writing: a reply (or its error) can arrive while the
    // write is still completing.
    final reply$ = p.done.future.timeout(timeout)
      // Marked as handled now; awaiting it below still gets its error.
      ..ignore();
    try {
      await link.writeCommand(Uint8List.fromList(utf8.encode(command)));
    } on Object {
      _pendings.remove(p); // no reply can come for a command never sent
      rethrow;
    }
    final GloveEvent reply;
    try {
      reply = await reply$;
    } on TimeoutException {
      _pendings.remove(p);
      throw GloveCommandTimeoutFailure(command);
    }
    if (reply is ErrorEvent) throw GloveCommandRejectedFailure(reply);
    return _Reply(reply, List.unmodifiable(p.weakFingers));
  }

  @override
  Future<GloveCalibration?> readCalibration() async {
    final r = (await _send('GETCAL')).event;
    return r is CalibrationEvent ? r.calibration : null;
  }

  @override
  Future<CalStepResult> calibrate(CalStep step) async {
    // 2 s (OPEN, FIST) or 3 s (TURN) of capture on the glove, then the reply.
    final capture = Duration(seconds: step == CalStep.turn ? 3 : 2);
    final r = await _send('CAL ${step.wire}', timeout: capture + replyTimeout);
    final e = r.event as CalStepEvent;
    return CalStepResult(
      e.step,
      ok: e.ok,
      reason: e.reason,
      weakFingers: r.weakFingers,
    );
  }

  @override
  Future<GloveCalibration> saveCalibration() async {
    final r = await _send('CAL SAVE');
    return (r.event as CalibrationEvent).calibration;
  }

  /// Sent at once, even while a step is waiting: the step then ends with
  /// `#CALSTEP <step> FAIL CANCELLED` (BLE §7).
  @override
  Future<void> cancelCalibration() => _send('CAL CANCEL', skipQueue: true);

  @override
  Future<BatteryEvent> readBattery() async =>
      (await _send('BAT')).event as BatteryEvent;

  /// `PING` → `#PONG` (link check).
  Future<void> ping() => _send('PING');

  @override
  void cuePractice(String label) {
    final t = _transport;
    if (t is PracticeCueSink) (t as PracticeCueSink).cuePractice(label);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _statusCtl.close();
    await _samplesCtl.close();
    await _eventsCtl.close();
  }
}

/// A command's reply, with the `#FLEX WEAK` fingers reported before it.
class _Reply {
  const new(this.event, this.weakFingers);
  final GloveEvent event;
  final List<int> weakFingers;
}

/// A command waiting for its reply.
class _Pending {
  new(this.command) : _word = command.split(' ').first;

  final String command;
  final String _word;
  final done = Completer<GloveEvent>();
  final weakFingers = <int>[];

  /// GETCAL and CAL SAVE are answered with `#CAL`.
  bool get expectsCalibration => _word == 'GETCAL' || command == 'CAL SAVE';

  bool get isCalStep =>
      _word == 'CAL' && CalStep.fromWire(command.split(' ').last) != null;

  /// Which EVENT line answers [command] (BLE §5).
  bool matches(GloveEvent e) {
    if (e is ErrorEvent) return e.command == _word;
    return switch (_word) {
      'STREAM' => e is OkEvent && e.command == 'STREAM',
      'GETCAL' => e is CalibrationEvent || e is NoCalibrationEvent,
      'BAT' => e is BatteryEvent,
      'PING' => e is PongEvent,
      'CAL' => switch (command.split(' ').elementAtOrNull(1)) {
        'SAVE' => e is CalibrationEvent,
        'CANCEL' => e is OkEvent && e.command == 'CAL',
        final String step =>
          e is CalStepEvent && e.step == CalStep.fromWire(step),
        null => false,
      },
      _ => e is OkEvent && e.command == _word,
    };
  }
}
