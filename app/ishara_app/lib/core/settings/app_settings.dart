import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
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
  }) = _AppSettings;
}

/// Holds [AppSettings]. In memory for now; persisted with the local database
/// in the storage step.
@Riverpod(keepAlive: true)
class AppSettingsController extends _$AppSettingsController {
  @override
  AppSettings build() => const AppSettings();

  void setLanguage(AppLanguage language) =>
      state = state.copyWith(language: language);

  /// The EN / ع toggle in the top bars.
  void toggleLanguage() => setLanguage(
    state.language == AppLanguage.en ? AppLanguage.ar : AppLanguage.en,
  );

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void setBigText({required bool on}) => state = state.copyWith(bigText: on);

  void setHighContrast({required bool on}) =>
      state = state.copyWith(highContrast: on);
}
