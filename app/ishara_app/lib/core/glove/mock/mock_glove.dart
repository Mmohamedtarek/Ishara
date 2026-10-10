import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:ishara_app/core/glove/frame_decoder.dart';
import 'package:ishara_app/core/glove/glove_client.dart';
import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/glove_failures.dart';
import 'package:ishara_app/core/glove/glove_source.dart';
import 'package:ishara_app/core/glove/glove_transport.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';

/// A simulated glove that follows BLE-CONTRACT v1 like firmware 0.3.0:
/// it advertises, answers every command on EVENT (BLE §5-7), and streams the
/// [feed] as real DATA frames at 50 Hz (5 samples every 100 ms). The app
/// talks to it through the same [GloveClient], frame decoder and line
/// parser as the real glove.
///
/// Mock-only: when the person changes, it sends their `#CAL` unsolicited
/// (the kit's recordings were made with each person's own calibration).
class MockGlove implements GloveTransport, PracticeCueSink {
  new(
    this.feed, {
    this.name = 'Ishara-M0CK',
    this.rssi = -52,
    this.scanDelay = const Duration(milliseconds: 1200),
    this.connectDelay = const Duration(milliseconds: 600),
    this.mtu = 247,
    this.calibrated = true,
  });

  final MockFeed feed;
  final String name;
  final int rssi;
  final Duration scanDelay;
  final Duration connectDelay;
  int mtu;

  /// Whether the glove has a stored calibration (`GETCAL` → `#CAL {…}`).
  bool calibrated;

  // ---- fault injection (tests, developer menu) ----

  /// The glove is switched on and advertising.
  bool advertising = true;

  /// The MPU-6050 doesn't answer (`#MPU FAIL`).
  bool mpuFail = false;

  /// The `#BAT` line the glove reports.
  String batteryLine = '#BAT OK 3.92V 78%';

  /// The next time this step runs, it fails with this reason (`MOVED`…).
  final Map<CalStep, String> failNextStep = {};

  /// `#FLEX WEAK` fingers reported after OPEN and FIST are both done.
  List<int> weakFingers = const [];

  _MockLink? _link;

  static const _id = 'mock:ishara';

  DiscoveredGlove get device =>
      DiscoveredGlove(id: _id, name: name, rssi: rssi);

  @override
  Stream<List<DiscoveredGlove>> scan({required Duration timeout}) async* {
    yield const [];
    final found = scanDelay < timeout && advertising && _link == null;
    await Future<void>.delayed(found ? scanDelay : timeout);
    if (found) {
      yield [device];
      await Future<void>.delayed(timeout - scanDelay);
    }
  }

  @override
  Future<GloveLink> open(DiscoveredGlove glove) async {
    await Future<void>.delayed(connectDelay);
    if (glove.id != _id || !advertising) {
      throw const GloveConnectFailure('glove not reachable');
    }
    if (_link != null) {
      throw const GloveConnectFailure(
        'glove already connected (one central at a time)',
      );
    }
    await feed.prepare();
    return _link = _MockLink(this);
  }

  /// Simulates the link dropping (out of range, glove switched off).
  void dropLink() => _link?._drop();

  /// Skips the next [samples] samples (a BLE gap of that size).
  void dropSamples(int samples) => _link?._skip += samples;

  /// Changes the simulated person; their calibration is sent as `#CAL`.
  Future<void> setPerson(MockPerson p) async {
    await feed.setPerson(p);
    final link = _link;
    if (link != null) link._line('#CAL ${await feed.calibrationJson()}');
  }

  /// Sends a `#BAT` state change, like the firmware does.
  void setBattery(String line) {
    batteryLine = line;
    _link?._line(line);
  }

  @override
  void cuePractice(String label) {
    unawaited(
      feed.clear().then(
        (_) =>
            feed.play([MockClip(MockLibrary.practiceFile(feed.person, label))]),
      ),
    );
  }

  void _closed(_MockLink link) {
    if (identical(_link, link)) _link = null;
  }
}

class _MockLink implements GloveLink {
  new(this.glove);

  final MockGlove glove;
  final _events = StreamController<Uint8List>.broadcast(sync: true);
  final _data = StreamController<Uint8List>.broadcast(sync: true);
  final _closed = Completer<void>();
  bool _eventsOn = false;
  Timer? _ticker;
  late DateTime _streamStart;
  int _sent = 0;
  int _seq = 0;
  int _skip = 0;

  final Set<CalStep> _done = {};
  CalStep? _running;
  Timer? _stepTimer;

  @override
  int get mtu => glove.mtu;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<Uint8List> readInfo() async => Uint8List.fromList(
    utf8.encode(
      '{"proto":1,"fw":"0.3.0","board":"mock","rate_hz":50,"channels":11,'
      '"acc_lsb_per_g":8192,"gyro_lsb_per_dps":65.5,"flex_max":4095,'
      '"samples_per_frame":5}',
    ),
  );

  @override
  Stream<Uint8List> get eventNotifications => _events.stream;

  @override
  Stream<Uint8List> get dataNotifications => _data.stream;

  @override
  Future<void> subscribeEvents() async {
    _eventsOn = true;
    // Sent when EVENT is subscribed (BLE §6).
    _line(glove.batteryLine);
    if (glove.mpuFail) _line('#MPU FAIL');
  }

  @override
  Future<void> subscribeData() async {}

  /// Sends one EVENT line, split into notifications of at most MTU - 3 bytes.
  void _line(String line) {
    if (!_eventsOn || _events.isClosed) return;
    final bytes = utf8.encode('$line\n');
    final max = mtu - 3;
    for (var i = 0; i < bytes.length; i += max) {
      _events.add(
        Uint8List.fromList(
          bytes.sublist(i, i + max > bytes.length ? bytes.length : i + max),
        ),
      );
    }
  }

  @override
  Future<void> writeCommand(Uint8List bytes) async {
    if (_closed.isCompleted) throw const GloveDisconnectedFailure();
    final cmd = utf8.decode(bytes).trim().toUpperCase();
    if (cmd.isEmpty || bytes.length > 20) return; // ignored, no reply
    final parts = cmd.split(RegExp(' +'));
    switch (parts) {
      case ['STREAM', '1']:
        if (FrameCodec.samplesForMtu(mtu) == 0) {
          _line('#ERR STREAM MTU');
        } else {
          _startStream();
          _line('#OK STREAM');
        }
      case ['STREAM', '0']:
        _stopStream();
        _line('#OK STREAM');
      case ['STREAM', ...]:
        _line('#ERR STREAM ARG');
      case ['GETCAL']:
        _line(
          glove.calibrated
              ? '#CAL ${await glove.feed.calibrationJson()}'
              : '#CAL NONE',
        );
      case ['CAL', 'OPEN' || 'FIST' || 'TURN']:
        _calStep(CalStep.fromWire(parts[1])!);
      case ['CAL', 'SAVE']:
        final missing = CalStep.values.where((s) => !_done.contains(s));
        if (_running != null) {
          _line('#ERR CAL BUSY');
        } else if (missing.isNotEmpty) {
          _line('#ERR CAL MISSING ${missing.first.wire}');
        } else {
          glove.calibrated = true;
          _done.clear();
          _line('#CAL ${await glove.feed.calibrationJson()}');
        }
      case ['CAL', 'CANCEL']:
        final running = _running;
        _stepTimer?.cancel();
        _running = null;
        glove.feed.stopCalibrationStep();
        _done.clear();
        if (running != null) _line('#CALSTEP ${running.wire} FAIL CANCELLED');
        _line('#OK CAL');
      case ['CAL', ...]:
        _line('#ERR CAL UNKNOWN');
      case ['BAT']:
        _line(glove.batteryLine);
      case ['PING']:
        _line('#PONG');
      default:
        _line('#ERR ${parts.first} UNKNOWN');
    }
  }

  void _calStep(CalStep step) {
    if (_running != null) {
      _line('#ERR CAL BUSY');
      return;
    }
    if (glove.mpuFail && step != CalStep.fist) {
      _line('#MPU FAIL');
      _line('#CALSTEP ${step.wire} FAIL MPU');
      return;
    }
    _running = step;
    glove.feed.startCalibrationStep(step);
    _stepTimer = Timer(Duration(seconds: step == CalStep.turn ? 3 : 2), () {
      _running = null;
      glove.feed.stopCalibrationStep();
      final reason = glove.failNextStep.remove(step);
      if (reason != null) {
        _line('#CALSTEP ${step.wire} FAIL $reason');
        return;
      }
      _done.add(step);
      if (step != CalStep.turn &&
          _done.contains(CalStep.open) &&
          _done.contains(CalStep.fist)) {
        for (final f in glove.weakFingers) {
          _line('#FLEX WEAK $f');
        }
      }
      _line('#CALSTEP ${step.wire} OK');
    });
  }

  void _startStream() {
    if (_ticker != null) return;
    _streamStart = clock.now();
    _sent = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _stopStream() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Sends the frames that are due, so the average rate stays exactly
  /// 50 Hz even if timers fire late.
  void _tick() {
    final elapsedMs = clock.now().difference(_streamStart).inMilliseconds;
    final due = elapsedMs * AiSpec.sampleRateHz ~/ 1000;
    final perFrame = FrameCodec.samplesForMtu(mtu);
    if (perFrame == 0) {
      // The MTU dropped below one sample: stop and say so, unsolicited,
      // like the firmware (BLE §4).
      _stopStream();
      _line('#ERR STREAM MTU');
      return;
    }
    while (_sent + perFrame <= due) {
      final raw = glove.feed.take(perFrame);
      _sent += perFrame;
      final batch = <GloveSample>[];
      for (final v in raw) {
        if (_skip > 0) {
          _skip--;
          _seq = (_seq + 1) & 0xFFFF;
          continue;
        }
        batch.add(GloveSample(_seq, v));
        _seq = (_seq + 1) & 0xFFFF;
      }
      // A frame carries consecutive seq only; a skip splits it.
      var start = 0;
      for (var i = 1; i <= batch.length; i++) {
        if (i == batch.length ||
            batch[i].seq != (batch[i - 1].seq + 1) & 0xFFFF) {
          if (i > start && !_data.isClosed) {
            _data.add(FrameCodec.encode(batch.sublist(start, i)));
          }
          start = i;
        }
      }
    }
  }

  void _drop() {
    if (_closed.isCompleted) return;
    _stopStream();
    _stepTimer?.cancel();
    _running = null;
    glove.feed.stopCalibrationStep();
    _done.clear(); // unsaved steps are dropped on disconnect (BLE §7)
    glove._closed(this);
    _closed.complete();
    unawaited(_events.close());
    unawaited(_data.close());
  }

  @override
  Future<void> close() async => _drop();
}
