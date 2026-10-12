import 'package:ishara_app/core/glove/glove_providers.dart';
import 'package:ishara_app/core/glove/mock/mock_feed.dart';
import 'package:ishara_app/core/glove/mock/mock_glove.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mock_controls.g.dart';

/// What the developer panel (S7-24) may do with the mock glove. Only
/// `lib/core/glove/` knows which glove is active: screens ask for these
/// controls and get null with the real glove.
abstract interface class MockControls {
  MockPerson get person;

  /// Switches person (their `#CAL` is sent, as the mock glove does).
  Future<void> setPerson(MockPerson person);

  /// Plays [file] (relative to the person's folder, without `.csv`, e.g.
  /// `sentences`) through the real pipeline.
  Future<void> play(String file);

  /// Stops what's queued; the hand goes back to rest.
  Future<void> stop();
}

class _MockGloveControls implements MockControls {
  new(this._glove);

  final MockGlove _glove;

  @override
  MockPerson get person => _glove.feed.person;

  @override
  Future<void> setPerson(MockPerson person) => _glove.setPerson(person);

  @override
  Future<void> play(String file) =>
      _glove.feed.play([MockClip('${person.dir}/$file.csv')]);

  @override
  Future<void> stop() => _glove.feed.clear();
}

/// The mock glove's controls, or null with the real glove.
@Riverpod(keepAlive: true)
MockControls? mockControls(Ref ref) {
  final glove = ref.watch(mockGloveProvider);
  return glove == null ? null : _MockGloveControls(glove);
}
