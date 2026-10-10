import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'developer_mode.g.dart';

/// Developer details on screen (e.g. the glove's RSSI in dBm, step 6
/// review). Off for users; the hidden developer switch in Settings (step 9)
/// turns it on.
@Riverpod(keepAlive: true)
class DeveloperMode extends _$DeveloperMode {
  @override
  bool build() => false;

  // The switch sets it; a setter would hide that intent.
  // ignore: use_setters_to_change_properties
  void set({required bool on}) => state = on;
}
