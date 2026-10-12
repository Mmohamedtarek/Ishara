import 'dart:async';
import 'dart:convert';

import 'package:ishara_app/core/avatar/avatar_controller.dart';

/// A page that records commands and lets the test post messages.
class FakePage implements AvatarPage {
  final sent = <Map<String, Object?>>[];
  final _out = StreamController<String>.broadcast();
  Exception? failWith;

  void post(String type, [Map<String, Object?> data = const {}]) =>
      _out.add(jsonEncode({'type': type, ...data}));

  @override
  Stream<String> get messages => _out.stream;

  @override
  Future<void> send(Map<String, Object?> command) async {
    final e = failWith;
    if (e != null) throw e;
    sent.add(command);
  }

  List<String?> get cmds => [for (final c in sent) c['cmd'] as String?];
}
