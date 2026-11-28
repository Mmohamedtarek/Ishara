import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ishara_app/core/auth/auth_repository.dart';
import 'package:ishara_app/core/errors/failure.dart';
import 'package:meta/meta.dart';

/// One remote document. Times are UTC [DateTime]s on this side of the
/// interface (Firestore timestamps in Firestore).
@immutable
class RemoteDoc {
  const new(this.id, this.data);

  final String id;
  final Map<String, Object?> data;
}

/// Why a remote call failed: offline, refused by the rules, or anything
/// else. The sync retries every kind with backoff.
enum RemoteProblem { network, denied, unknown }

final class RemoteFailure extends Failure {
  const new(this.problem, {super.cause}) : super('remote call failed');

  final RemoteProblem problem;

  @override
  String get kind => 'remote_${problem.name}';
}

/// Every Firestore call goes through this interface (CLAUDE.md): Firestore
/// itself, or [FakeRemoteStore] (tests and the fake backend). Paths are the
/// Phase 0 model's (`users/{uid}/phrases/{id}` …). Throws [RemoteFailure].
abstract interface class RemoteStore {
  Future<void> set(String path, Map<String, Object?> data);
  Future<Map<String, Object?>?> get(String path);
  Future<void> delete(String path);

  /// Every document of a collection.
  Future<List<RemoteDoc>> list(String collection);

  /// The collection's documents as they are added or changed (the first
  /// event holds them all). A removed document isn't reported.
  Stream<List<RemoteDoc>> watch(String collection);

  /// One document as it changes (null while there is none).
  Stream<Map<String, Object?>?> watchDoc(String path);
}

/// Firestore (cloud_firestore). Writes time out after [timeout]: offline,
/// Firestore would keep them waiting; the outbox retries instead.
class FirestoreRemoteStore implements RemoteStore {
  new(this._db, {this.timeout = const Duration(seconds: 20)});

  final FirebaseFirestore _db;
  final Duration timeout;

  static Object? _out(Object? v) => switch (v) {
    final DateTime d => Timestamp.fromMicrosecondsSinceEpoch(
      d.microsecondsSinceEpoch,
    ),
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: _out(e.value),
    },
    _ => v,
  };

  static Object? _in(Object? v) => switch (v) {
    final Timestamp t => DateTime.fromMicrosecondsSinceEpoch(
      t.microsecondsSinceEpoch,
      isUtc: true,
    ),
    final Map<String, Object?> m => {
      for (final e in m.entries) e.key: _in(e.value),
    },
    _ => v,
  };

  static Map<String, Object?> _read(Map<String, dynamic> d) => {
    for (final e in d.entries) e.key: _in(e.value),
  };

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException catch (e) {
      throw RemoteFailure(RemoteProblem.network, cause: e);
    } on FirebaseException catch (e) {
      throw RemoteFailure(switch (e.code) {
        'unavailable' || 'deadline-exceeded' => RemoteProblem.network,
        'permission-denied' || 'unauthenticated' => RemoteProblem.denied,
        _ => RemoteProblem.unknown,
      }, cause: e.code);
    }
  }

  @override
  Future<void> set(String path, Map<String, Object?> data) => _guard(
    () =>
        _db.doc(path).set({for (final e in data.entries) e.key: _out(e.value)}),
  );

  @override
  Future<Map<String, Object?>?> get(String path) => _guard(() async {
    final d = await _db.doc(path).get(const GetOptions(source: Source.server));
    return d.exists ? _read(d.data()!) : null;
  });

  @override
  Future<void> delete(String path) => _guard(() => _db.doc(path).delete());

  @override
  Future<List<RemoteDoc>> list(String collection) => _guard(() async {
    final q = await _db
        .collection(collection)
        .get(const GetOptions(source: Source.server));
    return [for (final d in q.docs) RemoteDoc(d.id, _read(d.data()))];
  });

  @override
  Stream<List<RemoteDoc>> watch(String collection) => _db
      .collection(collection)
      .snapshots()
      .map(
        (s) => [
          for (final c in s.docChanges)
            if (c.type != DocumentChangeType.removed)
              RemoteDoc(c.doc.id, _read(c.doc.data()!)),
        ],
      )
      .where((l) => l.isNotEmpty);

  @override
  Stream<Map<String, Object?>?> watchDoc(String path) =>
      _db.doc(path).snapshots().map((d) => d.exists ? _read(d.data()!) : null);
}

/// The fake backend's "server": documents in memory, shared by every
/// [FakeRemoteStore] on it (two simulated phones on one account).
class FakeRemoteServer {
  final docs = <String, Map<String, Object?>>{};
  final _changes = StreamController<String>.broadcast(sync: true);

  /// Paths written, in order (tests).
  final writes = <String>[];

  void _put(String path, Map<String, Object?> data) {
    docs[path] = Map.unmodifiable(data);
    writes.add(path);
    _changes.add(path);
  }

  void _remove(String path) {
    docs.remove(path);
    _changes.add(path);
  }

  Future<void> dispose() => _changes.close();
}

/// [RemoteStore] on a [FakeRemoteServer], refusing what the security rules
/// refuse (`firebase/firestore.rules`): another user's path, a write before
/// the email is verified, a change to an activity event.
class FakeRemoteStore implements RemoteStore {
  new(this.server, {required this._user});

  final FakeRemoteServer server;
  final AuthUser? Function() _user;

  /// Every call fails with [RemoteProblem.network].
  bool offline = false;

  /// The next calls fail with this problem ([failCount] times).
  RemoteProblem? failNext;
  int failCount = 1;

  /// Called on every call (tests count tries).
  void Function()? onCall;

  /// Paths refused as by the rules (tests).
  bool Function(String path)? refuse;

  /// Awaited before every write (tests make a slow network).
  Future<void> Function()? beforeSet;

  void _check(String path, {required bool write}) {
    onCall?.call();
    if (write && (refuse?.call(path) ?? false)) {
      throw const RemoteFailure(
        RemoteProblem.denied,
        cause: 'permission-denied',
      );
    }
    final f = failNext;
    if (f != null) {
      if (--failCount <= 0) failNext = null;
      throw RemoteFailure(f);
    }
    if (offline) throw const RemoteFailure(RemoteProblem.network);
    final u = _user();
    final parts = path.split('/');
    if (u == null || parts.length < 2 || parts[0] != 'users') {
      throw const RemoteFailure(RemoteProblem.denied);
    }
    if (parts[1] != u.id) throw const RemoteFailure(RemoteProblem.denied);
    if (write && !u.emailVerified) {
      throw const RemoteFailure(RemoteProblem.denied);
    }
  }

  @override
  Future<void> set(String path, Map<String, Object?> data) async {
    await beforeSet?.call();
    _check(path, write: true);
    final p = path.split('/');
    if (p.length == 4 && p[2] == 'activity' && server.docs.containsKey(path)) {
      throw const RemoteFailure(RemoteProblem.denied); // append-only
    }
    server._put(path, data);
  }

  @override
  Future<Map<String, Object?>?> get(String path) async {
    _check(path, write: false);
    return server.docs[path];
  }

  @override
  Future<void> delete(String path) async {
    _check(path, write: true);
    server._remove(path);
  }

  List<RemoteDoc> _in(String collection) => [
    for (final e in server.docs.entries)
      if (e.key.startsWith('$collection/') &&
          !e.key.substring(collection.length + 1).contains('/'))
        RemoteDoc(e.key.substring(collection.length + 1), e.value),
  ];

  @override
  Future<List<RemoteDoc>> list(String collection) async {
    _check(collection, write: false);
    return _in(collection);
  }

  bool _inCollection(String path, String collection) =>
      path.startsWith('$collection/') &&
      !path.substring(collection.length + 1).contains('/');

  final _open = <StreamController<Object?>>{};

  /// Every live stream fails and ends, as a Firestore listener does after
  /// an error (tests).
  void breakListeners([
    Object error = const RemoteFailure(RemoteProblem.denied),
  ]) {
    for (final c in [..._open]) {
      c.addError(error);
      unawaited(c.close());
    }
    _open.clear();
  }

  /// A stream that starts with [first] and then follows the server.
  Stream<T> _follow<T>(T? Function() first, T? Function(String path) next) {
    late StreamController<T> out;
    StreamSubscription<String>? sub;
    out = StreamController<T>(
      onListen: () {
        _open.add(out);
        if (first() case final T v) out.add(v);
        sub = server._changes.stream.listen((path) {
          if (next(path) case final T v) out.add(v);
        });
      },
      onCancel: () {
        _open.remove(out);
        return sub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Stream<List<RemoteDoc>> watch(String collection) {
    _check(collection, write: false);
    return _follow(
      () {
        final all = _in(collection);
        return all.isEmpty ? null : all;
      },
      (path) {
        final doc = server.docs[path];
        return doc != null && _inCollection(path, collection)
            ? [RemoteDoc(path.substring(collection.length + 1), doc)]
            : null;
      },
    );
  }

  @override
  Stream<Map<String, Object?>?> watchDoc(String path) {
    _check(path, write: false);
    // an empty map stands for "no document" (null means "no event")
    return _follow<Map<String, Object?>?>(
      () => server.docs[path] ?? const {},
      (p) => p == path ? server.docs[path] ?? const {} : null,
    ).map((d) => d == null || d.isEmpty ? null : d);
  }
}
