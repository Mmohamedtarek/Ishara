import 'package:ishara_app/core/settings/app_settings.dart';
import 'package:ishara_app/core/settings/settings_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'developer_mode.g.dart';

/// Developer details on screen (e.g. the glove's RSSI in dBm, step 6
/// review). Off for users; the hidden developer switch in Settings (step 9)
/// turns it on.
@Riverpod(keepAlive: true)
class DeveloperMode extends _$DeveloperMode {
  @override
  bool build() =>
      ref.watch(settingsStoreProvider).getBool(SettingsStore.kDeveloper) ??
      false;

  void set({required bool on}) {
    state = on;
    ref
        .read(settingsStoreProvider)
        .setBool(SettingsStore.kDeveloper, value: on)
        .ignore();
  }
}
