import 'dart:math';

/// A random id of [bytes] bytes, as lowercase hex (ids of messages,
/// conversations and phrases).
String hexId(Random random, int bytes) => [
  for (var i = 0; i < bytes; i++)
    random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
