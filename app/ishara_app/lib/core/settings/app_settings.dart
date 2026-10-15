import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ishara_app/core/profile/profile_providers.dart';
import 'package:ishara_app/core/settings/settings_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

/// App languages. English is the prototype's default (`var lang = 'en'`).
enum AppLanguage {
  en,
  ar;

  Locale get locale => Locale(name);
  bool get isRtl => this == ar;
}

/// Display settings shared by every screen.
@freezed
abstract class AppSettings with _$AppSettings {
  const factory({
    @Default(AppLanguage.en) AppLanguage language,

    /// Q-D3: follow the system theme; light when the system gives none.
    @Default(ThemeMode.system) ThemeMode themeMode,

    /// Settings › Large text (prototype default off).
    @Default(false) bool bigText,

    /// Settings › High contrast (prototype default off).
    @Default(false) bool highContrast,

    /// Settings › Vibrate (S9-1; off by default).
    @Default(false) bool vibrate,

    /// Settings › Subtitles under the avatar: Talk's caption (S9-2;
    /// prototype default on).
    @Default(true) bool subtitles,
  }) = _AppSettings;
}

/// The phone's settings store (S6-2 pattern).
@Riverpod(keepAlive: true)
SettingsStore settingsStore(Ref ref) =>
    SettingsStore(ref.watch(keyValueStoreProvider));

/// Holds [AppSettings], loaded from and saved to [SettingsStore].
@Riverpod(keepAlive: true)
class AppSettingsController extends _$AppSettingsController {
  SettingsStore get _store => ref.read(settingsStoreProvider);

  @override
  AppSettings build() {
    final s = ref.watch(settingsStoreProvider);
    bool flag(String k, {required bool fallback}) => s.getBool(k) ?? fallback;
    return AppSettings(
      language:
          AppLanguage.values.asNameMap()[s.getString(
            SettingsStore.kLanguage,
          )] ??
          AppLanguage.en,
      themeMode: s.themeMode,
      bigText: flag(SettingsStore.kBigText, fallback: false),
      highContrast: flag(SettingsStore.kHighContrast, fallback: false),
      vibrate: flag(SettingsStore.kVibrate, fallback: false),
      subtitles: flag(SettingsStore.kSubtitles, fallback: true),
    );
  }

  void _flag(String key, {required bool on}) =>
      _store.setBool(key, value: on).ignore();

  void setLanguage(AppLanguage language) {
    state = state.copyWith(language: language);
    _store.setString(SettingsStore.kLanguage, language.name).ignore();
  }

  /// The EN / ع toggle in the top bars.
  void toggleLanguage() => setLanguage(
    state.language == AppLanguage.en ? AppLanguage.ar : AppLanguage.en,
  );

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _store.setString(SettingsStore.kTheme, mode.name).ignore();
  }

  void setBigText({required bool on}) {
    state = state.copyWith(bigText: on);
    _flag(SettingsStore.kBigText, on: on);
  }

  void setHighContrast({required bool on}) {
    state = state.copyWith(highContrast: on);
    _flag(SettingsStore.kHighContrast, on: on);
  }

  void setVibrate({required bool on}) {
    state = state.copyWith(vibrate: on);
    _flag(SettingsStore.kVibrate, on: on);
  }

  void setSubtitles({required bool on}) {
    state = state.copyWith(subtitles: on);
    _flag(SettingsStore.kSubtitles, on: on);
  }
}
