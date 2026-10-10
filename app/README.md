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

## CI

`.github/workflows/ci.yml` tests the whole repo on every push and pull request (no path filters, no branch
protection: a failing job shows as a red ✗ on the commit). `app`, `ai` and `firmware` run in parallel;
`android` starts after `app`. A newer push to the same branch cancels the running workflow.

| Job | What it checks | When it fails |
|---|---|---|
| **Flutter app** (`app/ishara_app`) | generated code builds; the committed kit assets match `app/Ishara-Mobile-Kit/` (checksums, then a fresh `sync_kit.sh` must change nothing); `dart format`; `flutter analyze --fatal-infos --fatal-warnings`; all host tests (pipeline, mock files, goldens, widgets) with coverage; ≥ 90 % on `lib/core` | Run the same command locally (section *Tests*). Kit drift: run `app/tools/sync_kit.sh`, commit the assets. Golden failure: download the `golden-failures` artifact from the run, compare; update goldens only for an intended UI change. |
| **Android build** | `flutter build apk --debug --dart-define=GLOVE=mock` | Run it locally; usually a Gradle, SDK or plugin version problem. |
| **AI (Python + kit)** (`AI/Ishara-AI-v3-2`) | `python -m pytest tests -q` (33 tests), then `python tests/verify_kit.py ../../app/Ishara-Mobile-Kit`: recomputes every test vector, the BLE gap test and all 88 mock files from the models, independently of the app | `AI/` belongs to the AI team: don't fix it in the app. Tell them, with the failing test or the `MISMATCH` line. If only `verify_kit` fails right after a kit update, the kit in `app/Ishara-Mobile-Kit/` and the AI code disagree: ask the AI team which one is right. |
| **Firmware (ESP32-S3)** (`firmware/ishara-firmware`) | `pio run -e devkit -e xiao -e wokwi` (flash and RAM use of each build in the log and the run summary); the Wokwi calibration test `test/calibration.test.yaml` when the `WOKWI_CLI_TOKEN` secret exists, otherwise a "skipped" notice | `firmware/` belongs to the embedded team: don't fix it here. Send them the build error or the Wokwi step's log. To enable the Wokwi test, add the secret (repository *Settings → Secrets and variables → Actions*); the test then uploads the wokwi build to Wokwi's simulator. |

Run a job's commands locally before pushing: the *Tests* commands above; `cd AI/Ishara-AI-v3-2` and the two
Python commands (in a Python 3.12 venv with `requirements.txt`); `cd firmware/ishara-firmware && pio run -e devkit -e xiao -e wokwi`.
`data/` and `ishara_rf.joblib` are not in git; the AI job doesn't need them.

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
| `vendor_three.sh` | Copies three.js 0.186.0 (the prototype's version, MIT) from npm into `assets/avatar/three/` with `SHA256SUMS` (a test checks them). |
| `extract_avatar_library.mjs` | Extracts the prototype engine's hand shapes and signs into `test/fixtures/prototype_avatar_library.json` (port-fidelity test). `node app/tools/extract_avatar_library.mjs` |
| `fmt_avatar_library.py` | Re-formats `assets/packs/<lang>/avatar/library.json` (one keyframe per line). |
| `avatar_shots.py` | Front / side contact sheets of avatar signs with the app's own engine page (headless Chrome). `app/tools/.venv/bin/python app/tools/avatar_shots.py water --views 0,-90` |
| `avatar_port_check.py` | Renders the unchanged signs in the prototype and in the port and compares the pixels (needs the network for the prototype's CDN three.js). |
| `avatar_contacts.py` | Prints how far each body contact lands from its target (mm), per character, from the engine's own bake. |
| `make_sign_report.py` | Builds the sign review page (`out/review2/index.html`): sheets, Lifeprint links, status per sign. |
| `make_brand.py` | Generates every app icon and native launch image (Android adaptive + monochrome, legacy PNGs, Android 12+ splash; iOS AppIcon, LaunchImage, LaunchBackground) from `ishara_app/brand/ishara_mark.svg`. |

## Avatar on a device

- Integration test (WebView + WebGL): `flutter test integration_test/avatar_test.dart -d <device>`: avatar ready, every sign plays to its end, frame rate.
- Emulator on this laptop (hybrid GPU): `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only emulator -avd ishara_api36 -no-snapshot -gpu host &`. Run one heavy job at a time.
- Developer sign preview: Settings → "Sign preview (dev)" (debug / profile builds only).

## Firebase emulators *(later: backend step)*

## Adding the ArSL pack *(later: sign-language packs step)*
