import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ishara_app/core/glove/glove_events.dart';
import 'package:ishara_app/core/glove/mock/recording.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:ishara_app/core/recognition/model_bundle.dart';
import 'package:ishara_app/core/recognition/recognition_config.dart';
import 'package:meta/meta.dart';

/// The two simulated people of the kit (`mock/A`, `mock/B`).
enum MockPerson { a, b }

extension MockPersonDir on MockPerson {
  String get dir => name.toUpperCase();
}

/// Loads (and caches) the kit's mock recordings.
class MockLibrary {
  /// [root] defaults to the default pack's mock folder (the app passes the
  /// active pack's `mockDir`).
  new(this._read, {String? root})
    : root = root ?? PackRegistry.packs[PackRegistry.defaultLanguage]!.mockDir;

  final AssetReader _read;
  final String root;
  final Map<String, Recording> _cache = {};

  /// [file] is relative to the mock folder, e.g. `A/hello.csv`.
  Future<Recording> load(String file) async {
    final hit = _cache[file];
    if (hit != null) return hit;
    final rec = Recording.parse(
      utf8.decode(await _read('$root/$file')),
      name: file,
    );
    return _cache[file] = rec;
  }

  /// Adds an already parsed recording (tests preload files this way).
  void seed(String file, Recording recording) => _cache[file] = recording;

  /// One sign held like a learner does (`practice/`, Q-L5): it confirms
  /// that sign exactly once.
  static String practiceFile(MockPerson p, String label) =>
      '${p.dir}/practice/$label.csv';

  /// Hand at rest (used between clips, so the glove keeps streaming).
  static String restFile(MockPerson p) => '${p.dir}/rest.csv';

  /// What every feed of person [p] loads up front: rest and the three
  /// calibration recordings.
  static List<String> baseFiles(MockPerson p) => [
    restFile(p),
    for (final step in CalStep.values) calibrationFile(p, step),
  ];

  /// What the sensors read during a calibration step (kit v3.2.3:
  /// `calibration/open.csv`, `fist.csv`, `turn.csv`). Their first line is
  /// the person's `#CAL`.
  static String calibrationFile(MockPerson p, CalStep step) =>
      '${p.dir}/calibration/${step.wire.toLowerCase()}.csv';
}

/// A piece of mock glove data to play.
@immutable
class MockClip {
  const new(this.file, {this.idleBefore = Duration.zero});

  /// Mock file relative to the mock folder.
  final String file;

  /// Hand at rest before the clip.
  final Duration idleBefore;
}

/// What the feed is playing.
@immutable
class MockFeedState {
  const new({this.clip, this.queued = 0});

  /// The clip being played (null = idle, hand at rest).
  final MockClip? clip;
  final int queued;
}

/// Produces raw samples in real time order: during a calibration step that
/// step's recording (looped); otherwise the queued clips, and the person's
/// rest recording (looped) whenever nothing is queued. It only produces raw
/// sensor values; words come from the real recognizer.
class MockFeed {
  new(this.library, {this._person = MockPerson.a});

  final MockLibrary library;
  MockPerson _person;
  Recording? _rest;
  final List<_Queued> _queue = [];
  _Queued? _current;
  int _restPos = 0;
  Map<CalStep, Recording> _calibrationFiles = const {};
  Recording? _calibration;
  int _calibrationPos = 0;
  final _stateCtl = StreamController<MockFeedState>.broadcast(sync: true);

  MockPerson get person => _person;

  /// Changes person. Their calibration differs, so the mock glove reports a
  /// new `#CAL` (see `MockGlove`).
  Future<void> setPerson(MockPerson p) async {
    // Load first, then switch: the glove keeps streaming meanwhile and must
    // always have a rest recording to play.
    final rest = await library.load(MockLibrary.restFile(p));
    final calibration = await _loadCalibration(p);
    _person = p;
    _rest = rest;
    _calibrationFiles = calibration;
    _restPos = 0;
    stopCalibrationStep();
    await clear();
  }

  Stream<MockFeedState> get states => _stateCtl.stream;

  MockFeedState get state =>
      MockFeedState(clip: _current?.clip, queued: _queue.length);

  /// Loads what the feed needs before streaming starts.
  Future<void> prepare() async {
    _rest ??= await library.load(MockLibrary.restFile(_person));
    if (_calibrationFiles.isEmpty) {
      _calibrationFiles = await _loadCalibration(_person);
    }
  }

  Future<Map<CalStep, Recording>> _loadCalibration(MockPerson p) async => {
    for (final step in CalStep.values)
      step: await library.load(MockLibrary.calibrationFile(p, step)),
  };

  /// Calibration JSON of the current person: the `#CAL` line of their
  /// calibration recordings (kit README: the reply to `CAL SAVE` / `GETCAL`).
  Future<String> calibrationJson() async {
    await prepare();
    final json = _calibrationFiles[CalStep.open]!.calibrationJson;
    if (json == null) {
      throw StateError(
        '${MockLibrary.calibrationFile(_person, CalStep.open)} has no #CAL',
      );
    }
    return json;
  }

  /// A calibration step runs: play its recording from the start, looped,
  /// instead of anything else (never rest: it isn't still). After
  /// [prepare].
  void startCalibrationStep(CalStep step) {
    final rec = _calibrationFiles[step];
    if (rec == null) throw StateError('call prepare() first');
    _calibration = rec;
    _calibrationPos = 0;
  }

  /// The step ended (done, failed, cancelled, link lost).
  void stopCalibrationStep() => _calibration = null;

  /// Adds clips after the ones already queued.
  Future<void> play(List<MockClip> clips) async {
    for (final c in clips) {
      _queue.add(_Queued(c, await library.load(c.file)));
    }
    _emit();
  }

  /// Stops what's queued; the hand goes back to rest.
  Future<void> clear() async {
    _queue.clear();
    _current = null;
    _emit();
  }

  /// The next [n] samples, 11 raw values each.
  List<Int16List> take(int n) {
    final rest = _rest;
    if (rest == null) throw StateError('call prepare() first');
    final out = <Int16List>[];
    final cal = _calibration;
    if (cal != null) {
      while (out.length < n) {
        out.add(Int16List.fromList(cal.sample(_calibrationPos)));
        _calibrationPos = (_calibrationPos + 1) % cal.length;
      }
      return out;
    }
    while (out.length < n) {
      final cur = _current;
      if (cur == null) {
        if (_queue.isNotEmpty) {
          _current = _queue.removeAt(0);
          _emit();
          continue;
        }
        out.add(_restSample(rest));
        continue;
      }
      if (cur.idleLeft > 0) {
        cur.idleLeft--;
        out.add(_restSample(rest));
        continue;
      }
      if (cur.pos < cur.recording.length) {
        out.add(Int16List.fromList(cur.recording.sample(cur.pos++)));
        continue;
      }
      _current = null;
      _emit();
    }
    return out;
  }

  Int16List _restSample(Recording rest) {
    final s = Int16List.fromList(rest.sample(_restPos));
    _restPos = (_restPos + 1) % rest.length;
    return s;
  }

  void _emit() {
    if (!_stateCtl.isClosed) _stateCtl.add(state);
  }

  Future<void> dispose() => _stateCtl.close();
}

class _Queued {
  new(this.clip, this.recording)
    : idleLeft = clip.idleBefore.inMilliseconds * AiSpec.sampleRateHz ~/ 1000;

  final MockClip clip;
  final Recording recording;
  int idleLeft;
  int pos = 0;
}
