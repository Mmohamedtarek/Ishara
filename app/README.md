# Ishara app

Flutter app for the Ishara sign-language glove: glove → text and speech, speech → 3D avatar, Learn.
App v1 is **ASL only**. Rules for contributors (and Claude sessions): `../CLAUDE.md`. Decisions: `DECISIONS.md`. Progress: `PROGRESS.md`.

```
app/
  Ishara-Mobile-Kit/   AI team's kit (models, mock glove, test vectors). Never edit by hand.
  ishara_app/          the Flutter app
  tools/               helper scripts (below)
```

> This README grows with each build step. Sections marked *(later)* are filled in by their step.

## Setup from zero (Ubuntu)

1. Install the toolchain: see `PHASE0-REPORT.md` §0.1 (Flutter 3.47.6, JDK 21, Android SDK 36, Node 22).
2. Get the code and generate sources:
   ```bash
   cd app/ishara_app
   flutter pub get
   flutter gen-l10n
   dart run build_runner build --delete-conflicting-outputs
   ```
   Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/gen/`) are not committed.

## Run

```bash
flutter run --dart-define=GLOVE=mock    # mock glove (today)
flutter run --dart-define=GLOVE=ble     # real glove over Bluetooth  (later: glove step)
```
Use the emulator (`ishara_api36`) for development. Bluetooth needs a real phone over USB.

## Tests

```bash
flutter analyze --fatal-infos            # must report zero issues
dart format --set-exit-if-changed lib test
flutter test --coverage                  # all host tests, incl. goldens and kit checksums
python3 ../tools/coverage_check.py coverage/lcov.info --min 90 lib/core 'lib/features/*/domain'
flutter test --update-goldens            # only after reviewing an intended UI change
```
Goldens: `test/**/goldens/ci/` (text drawn as blocks) are checked everywhere; `goldens/linux/` (real text)
are local only and are the images used for the screenshot review.

## Updating the AI models (new kit from the AI team)

1. Replace `app/Ishara-Mobile-Kit/` with the new kit.
2. Run `app/tools/sync_kit.sh` (copies `model/`, `mock/`, `test/` into `ishara_app/assets/packs/asl/kit/`, and checks that
   `pubspec.yaml` declares every folder).
3. Run `flutter test`. `test/kit/kit_sync_test.dart` fails if any asset differs from the kit; the pipeline tests
   check the new models against the kit's test vectors *(later: glove core step)*.

## Tools (`app/tools/`)

| Script | What it does |
|---|---|
| `strip_prototype.py` | Splits `design/prototype.html` into a readable copy and the avatar `.glb` files (`tools/out/`, git-ignored). Run first. |
| `extract_strings.py` | Writes `lib/l10n/app_{en,ar}.arb` from the prototype strings; lists the strings left out and why. |
| `extract_icons.py` | Ports the prototype's SVG icons to `lib/core/ui/ishara_icon_data.dart`. |
| `make_fonts.sh` | Builds the bundled static fonts (Figtree, Cairo, Bricolage Grotesque, OFL) from google/fonts. |
| `sync_kit.sh` | Copies the Mobile Kit into the app's assets (the only allowed way). |
| `coverage_check.py` | Coverage gate used by CI. |
| `proto_shot.py` | Screenshots prototype screens (EN/AR × light/dark) with Playwright + system Chrome, for UI review. Needs `python3 -m venv app/tools/.venv && app/tools/.venv/bin/pip install 'playwright==1.*'`. |

## Firebase emulators *(later: backend step)*

## Adding the ArSL pack *(later: sign-language packs step)*
