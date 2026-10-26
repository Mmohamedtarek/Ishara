# speech_to_text 7.5.0 (patched for Ishara)

A copy of [speech_to_text](https://pub.dev/packages/speech_to_text) 7.5.0 (BSD-3, `LICENSE`),
only `lib/`, `android/`, `darwin/`, `pubspec.yaml`, `LICENSE` and `README.md`. The app uses it
through `dependency_overrides` in `app/ishara_app/pubspec.yaml` (user decision S7-27, option a).

Changes (Android only, every one marked `// Ishara:`; the full diff is `ISHARA.patch`):
1. `contextualPhrases` (already sent by the plugin's Dart side, but never read on Android) is
   passed to the recognizer as `RecognizerIntent.EXTRA_BIASING_STRINGS` on Android 13+.
2. The recognizer intent is rebuilt when `onDevice` or the phrases change (upstream compared only
   the language, partial results, listen mode and pause, so a listen could reuse an intent built
   without the on-device flag).
3. Two debug lines (only with `initialize(debugLogging: true)`, which the app passes in debug builds
   with developer mode on): whether the phone has an on-device recognizer, and each intent's
   language, on-device flag, Android version and number of biasing strings (2026-10-26, Talk
   words diagnosis).

When upstream supports biasing on Android, drop this copy and the override.
