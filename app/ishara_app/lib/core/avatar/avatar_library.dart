import 'dart:convert';

import 'package:ishara_app/core/errors/failure.dart';
import 'package:ishara_app/core/packs/sign_language.dart';
import 'package:meta/meta.dart';

/// A language pack's avatar sign library
/// (`assets/packs/<lang>/avatar/library.json`), the data the ported engine
/// (`assets/avatar/engine.js`) plays.
///
/// The app reads it to know which labels the engine can perform and how
/// long each one lasts (the engine's own timing rule), and checks every
/// frame so a broken library fails at load, not on screen.
@immutable
class AvatarLibrary {
  const new _(
    this.language,
    this.shapes,
    this._lastFrame,
    this.previewPairs,
    this.greeting,
  );

  /// Parses and checks [json]; throws [ParseFailure] if anything is off.
  factory parse(String json, {required SignLanguage language}) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException catch (e) {
      throw ParseFailure('not JSON', source: _src, cause: e);
    }
    if (root is! Map<String, Object?>) _fail('the root is not an object');
    if (root['language'] != language.id) {
      _fail('the library is for ${root['language']}, not ${language.id}');
    }
    final rawShapes = root['shapes'];
    if (rawShapes is! Map<String, Object?> || rawShapes.isEmpty) {
      _fail('no shapes');
    }
    final shapes = <String>{};
    for (final MapEntry(:key, :value) in rawShapes.entries) {
      _checkShape(key, value);
      shapes.add(key);
    }
    if (!shapes.contains('relax')) _fail('the ready pose needs shape "relax"');
    final rawSigns = root['signs'];
    if (rawSigns is! Map<String, Object?> || rawSigns.isEmpty) {
      _fail('no signs');
    }
    final last = <String, double>{};
    for (final MapEntry(:key, :value) in rawSigns.entries) {
      if (key == readyPose || key.trim().isEmpty) {
        _fail('"$key" is not a sign label (rest is the ready pose)');
      }
      last[key] = _checkSign(key, value, shapes);
    }
    final pairs = <(String, String)>[];
    final rawPairs = root['previewPairs'] ?? const <Object?>[];
    if (rawPairs is! List<Object?>) _fail('previewPairs must be a list');
    for (final p in rawPairs) {
      if (p is! List<Object?> ||
          p.length != 2 ||
          !last.containsKey(p[0]) ||
          !last.containsKey(p[1])) {
        _fail('previewPairs: $p must name two signs of the library');
      }
      pairs.add((p[0]! as String, p[1]! as String));
    }
    final greeting = root['greeting'];
    if (greeting != null &&
        (greeting is! String || !last.containsKey(greeting))) {
      _fail('greeting must name a sign of the library');
    }
    return AvatarLibrary._(
      language,
      Set.unmodifiable(shapes),
      Map.unmodifiable(last),
      List.unmodifiable(pairs),
      greeting as String?,
    );
  }

  static const _src = 'avatar library';

  /// The engine's lead-in (`LEAD`) and tail: a sign lasts
  /// `(lead + last frame t + tail) / speed` seconds (prototype `signLength`).
  static const double lead = .32;
  static const double tail = .25;

  /// The engine clamps the speed to this range.
  static const double minSpeed = .4;
  static const double maxSpeed = 2;

  /// The engine's name for its ready pose (`SIGNS.rest`): never a sign.
  static const readyPose = 'rest';

  /// Fingers a shape's contact `tip` may name.
  static const fingers = {'thumb', 'index', 'middle', 'ring', 'pinky'};

  /// Landmarks a point may be measured from (engine `measure`).
  /// `ear` is beside the head, its depth from the head bone (not the skin).
  static const landmarks = {
    'chin',
    'mouth',
    'cheek',
    'forehead',
    'chest',
    'ear',
  };

  final SignLanguage language;
  final Set<String> shapes;
  final Map<String, double> _lastFrame;

  /// Signs the preview screen offers side by side (similar hands).
  final List<(String, String)> previewPairs;

  /// The sign the engine waves after a character loads (null = none).
  final String? greeting;

  /// The labels the engine can perform.
  Set<String> get labels => _lastFrame.keys.toSet();

  bool has(String label) => _lastFrame.containsKey(label);

  /// The time of [label]'s last keyframe (seconds, at speed 1).
  double lastFrameTime(String label) =>
      _lastFrame[label] ??
      (throw ArgumentError.value(label, 'label', 'not in the library'));

  /// How long [label] plays at [speed], as the engine times it.
  Duration duration(String label, {double speed = 1}) {
    final last = _lastFrame[label];
    if (last == null) {
      throw ArgumentError.value(label, 'label', 'not in the library');
    }
    final s = clampSpeed(speed);
    return Duration(microseconds: ((lead + last + tail) / s * 1e6).round());
  }

  static double clampSpeed(double speed) =>
      speed.isNaN ? 1 : speed.clamp(minSpeed, maxSpeed);

  static Never _fail(String m) => throw ParseFailure(m, source: _src);

  static void _checkShape(String name, Object? v) {
    if (v is! Map<String, Object?>) _fail('shape $name is not an object');
    final curl = v['curl'];
    if (!_nums(curl, 5) ||
        (curl! as List).cast<num>().any((c) => c < 0 || c > 100)) {
      _fail('shape $name: curl must be 5 numbers 0-100');
    }
    final reach = v['reach'];
    if (reach is! num || reach <= 0 || reach > 2) {
      _fail('shape $name: reach must be a number in (0, 2]');
    }
    final spread = v['spread'];
    if (spread != null &&
        (!_nums(spread, 5) ||
            (spread as List).cast<num>().any((d) => d.abs() > 30))) {
      _fail('shape $name: spread must be 5 angles within ±30°');
    }
    final tip = v['tip'];
    if (tip != null && !fingers.contains(tip)) {
      _fail('shape $name: tip must be one of $fingers');
    }
  }

  /// Checks a sign's frames; returns the time of the last frame.
  static double _checkSign(String label, Object? v, Set<String> shapes) {
    if (v is! Map<String, Object?>) _fail('sign $label is not an object');
    final frames = v['frames'];
    if (frames is! List<Object?> || frames.isEmpty) {
      _fail('sign $label has no frames');
    }
    var prev = -1.0;
    for (final (i, f) in frames.indexed) {
      if (f is! Map<String, Object?>) _fail('sign $label frame $i');
      final t = f['t'];
      if (t is! num || !t.isFinite || t <= prev || (i == 0 && t != 0)) {
        _fail('sign $label frame $i: t must start at 0 and increase');
      }
      prev = t.toDouble();
      if (i == 0 && f['R'] == null) {
        _fail('sign $label: the first frame needs the right hand (R)');
      }
      for (final hand in const ['R', 'L']) {
        if (f[hand] != null) {
          _checkKey('$label frame $i $hand', f[hand], shapes);
        }
      }
      final head = f['head'];
      if (head != null && !_nums(head, 2)) {
        _fail('sign $label frame $i: head must be [turn, nod]');
      }
      final extra = f.keys.toSet().difference(const {'t', 'R', 'L', 'head'});
      if (extra.isNotEmpty) _fail('sign $label frame $i: unknown $extra');
    }
    return prev;
  }

  static void _checkKey(String where, Object? k, Set<String> shapes) {
    if (k is! Map<String, Object?>) _fail('$where is not an object');
    final p = k['P'];
    final landmarkPoint =
        p is List<Object?> &&
        p.length == 4 &&
        landmarks.contains(p.first) &&
        _nums(p.sublist(1), 3);
    if (!landmarkPoint && !_nums(p, 3)) {
      _fail('$where: P must be [x, y, z] or [landmark, dx, dy, dz]');
    }
    for (final d in const ['H', 'N']) {
      final v = k[d];
      if (!_nums(v, 3) || (v! as List).cast<num>().every((x) => x == 0)) {
        _fail('$where: $d must be a non-zero direction');
      }
    }
    final at = k['at'];
    if (at != null && !const {'wrist', 'tip', 'palm'}.contains(at)) {
      _fail('$where: at must be wrist, tip or palm');
    }
    if (!shapes.contains(k['c'])) _fail('$where: unknown shape ${k['c']}');
    final e = k['E'];
    if (e != null &&
        (!_nums(e, 3) || (e as List).cast<num>().every((x) => x == 0))) {
      _fail('$where: E (elbow direction) must be a non-zero direction');
    }
    final extra = k.keys.toSet().difference(const {
      'P',
      'H',
      'N',
      'c',
      'at',
      'E',
    });
    if (extra.isNotEmpty) _fail('$where: unknown $extra');
  }

  static bool _nums(Object? v, int n) =>
      v is List<Object?> &&
      v.length == n &&
      v.every((x) => x is num && x.isFinite);
}
