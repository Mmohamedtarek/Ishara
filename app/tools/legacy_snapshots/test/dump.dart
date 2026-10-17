import 'dart:convert';
import 'dart:io';

/// Writes every stored value (typed JSON) of [keys] read by [read].
void dump(String name, Set<String> keys, Object? Function(String) read) {
  final out = {for (final k in keys.toList()..sort()) k: read(k)};
  File('out/$name.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(out)}\n',
  );
}
