import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ishara_app/core/settings/app_settings.dart';

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  AppSettings read() => c.read(appSettingsControllerProvider);
  AppSettingsController ctl() => c.read(appSettingsControllerProvider.notifier);

  test('defaults: English (prototype), system theme (Q-D3), options off', () {
    expect(read().language, AppLanguage.en);
    expect(read().themeMode, ThemeMode.system);
    expect(read().bigText, isFalse);
    expect(read().highContrast, isFalse);
  });

  test('language toggle switches EN <-> AR and RTL', () {
    ctl().toggleLanguage();
    expect(read().language, AppLanguage.ar);
    expect(read().language.isRtl, isTrue);
    expect(read().language.locale, const Locale('ar'));
    ctl().toggleLanguage();
    expect(read().language.isRtl, isFalse);
  });

  test('setters', () {
    ctl()
      ..setThemeMode(ThemeMode.dark)
      ..setBigText(on: true)
      ..setHighContrast(on: true)
      ..setLanguage(AppLanguage.ar);
    expect(
      read(),
      const AppSettings(
        language: AppLanguage.ar,
        themeMode: ThemeMode.dark,
        bigText: true,
        highContrast: true,
      ),
    );
  });
}
