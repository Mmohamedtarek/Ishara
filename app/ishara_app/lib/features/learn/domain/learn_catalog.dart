import 'package:meta/meta.dart';

/// What Learn needs to know about a sign (from the pack's `signs.json`).
@immutable
class LearnSign {
  const new({required this.label, required this.glove, required this.avatar});

  final String label;

  /// The glove model recognizes it: the only signs a practice step may ask
  /// for (sign rule 3).
  final bool glove;

  /// The avatar can perform it (approved animation).
  final bool avatar;
}

/// A Learn module (Q-L1).
@immutable
class LearnModule {
  const new({required this.id, required this.signs, this.watchOnly = false});

  final String id;

  /// Labels, in order.
  final List<String> signs;

  /// Pick-the-meaning steps only.
  final bool watchOnly;
}

/// The signs and modules of the active pack.
class LearnCatalog {
  /// Throws [ArgumentError] if a module names an unknown sign or uses the
  /// daily challenge's id.
  new({required List<LearnSign> signs, required List<LearnModule> modules})
    : signs = List.unmodifiable(signs),
      modules = List.unmodifiable(modules),
      _byLabel = {for (final s in signs) s.label: s} {
    for (final m in modules) {
      if (m.id == dailyId) throw ArgumentError('module id "$dailyId"');
      for (final l in m.signs) {
        if (!_byLabel.containsKey(l)) {
          throw ArgumentError('module "${m.id}": unknown sign "$l"');
        }
      }
    }
  }

  /// The daily challenge's `moduleId` in the activity log.
  static const dailyId = 'daily';

  final List<LearnSign> signs;
  final List<LearnModule> modules;
  final Map<String, LearnSign> _byLabel;

  LearnSign? sign(String label) => _byLabel[label];

  LearnModule? module(String id) {
    for (final m in modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The module a sign belongs to (null if none).
  LearnModule? moduleOf(String label) {
    for (final m in modules) {
      if (m.signs.contains(label)) return m;
    }
    return null;
  }

  /// Q-L1: a module with an unapproved animation (`avatar: false`) stays
  /// locked.
  bool available(LearnModule m) => m.signs.every((l) => sign(l)!.avatar);
}
