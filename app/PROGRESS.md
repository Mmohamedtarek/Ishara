# Progress

## Phase 0: setup, read, report (2026-10-08)

**Built:** `CLAUDE.md`, `app/tools/strip_prototype.py`, `app/PHASE0-REPORT.md`, `.gitignore` entry for `app/tools/out/`. No app code.

| Checklist (source: user prompt, Phase 0) | Status |
|---|---|
| 0.1 List missing tools and give install commands, no sudo run | ✓ (report §0.1). `flutter doctor -v` **not run yet**: Flutter is not installed, and the disk has only 7.9 GB free |
| 0.2 `CLAUDE.md` with sources, never-change list, review protocol, sign rules, ask-don't-guess | ✓ |
| Prototype read via a re-runnable strip script in `app/tools/` | ✓ (`python3 app/tools/strip_prototype.py`; 2 GLBs, glTF magic checked) |
| 0.3.1 Screen map | ✓ |
| 0.3.2 Avatar engine | ✓ |
| 0.3.3 Sign mismatches (7 confirmed + 14 new) | ✓ |
| 0.3.4 Avatar vs vocabulary v2 table | ✓ from keyframe data. The visual check is planned for Step 5 |
| 0.3.5 Architecture, packages, Firestore model | ✓ |
| 0.3.6 Wrong / contradictory sources | ✓ (C1–C15) |

**Tests:** none (no app code yet). **Screenshots:** static screens rendered with headless Chrome for comparison (scratchpad only).

**Open questions:** all of `PHASE0-REPORT.md` §7. Waiting for the user.

## Step 2: project skeleton (2026-10-08)

**Built:** Flutter app `app/ishara_app/` (Flutter 3.47.6) with the theme, l10n, navigation, typed errors, structured logging, settings state, kit sync with checksum test, CI. Tools: `make_fonts.sh`, `sync_kit.sh`, `extract_strings.py`, `extract_icons.py`, `coverage_check.py`, `proto_shot.py`. Screens are **skeletons** (real title + prototype exits) until their feature steps.

| Checklist (source) | Status |
|---|---|
| App in `app/ishara_app/` (prompt › Architecture) | ✓ |
| Riverpod with codegen, go_router, Material 3, feature-first folders, freezed, typed errors, structured logging (prompt › Stack) | ✓ `core/{errors,logging,router,settings,theme,ui}`, `features/*/presentation` |
| One theme file with the prototype CSS tokens; light, dark, system with light fallback; high contrast; big text (prompt; Q-D3; CSS l.11–70, 494–527) | ✓ `core/theme/`; all 31 tokens × 2 themes tested against `design/prototype.html` |
| Bundled fonts, offline (prototype l.9) | ✓ 13 static TTFs + OFL licences, 1.2 MB |
| ARB en / ar from the prototype, feminine variants, RTL (prompt; Q-D2) | ✓ 230 strings; 78 left out with reasons (`extract_strings.py`) |
| Navigation for every prototype screen, 4-tab shell, slide / pop transitions, RTL, reduced motion (prototype l.169–178, 1006–1034) | ✓ (Back animation differs slightly, see DECISIONS) |
| `sync_kit.sh` + checksum test, pubspec asset check (prompt › Kit files) | ✓ fails on a changed byte and on a missing pubspec folder (both shown) |
| very_good_analysis zero issues, dart format | ✓ `flutter analyze --fatal-infos`: no issues |
| GitHub Actions: analyze, format, tests, coverage gate, Android build (prompt › Quality bar) | ✓ written (`.github/workflows/ci.yml`); **not run yet** (not pushed) |
| Android build | ✗ **not run locally**: only 4.2 GB disk free (see open questions) |
| iOS-ready | ✓ `CFBundleLocalizations` en / ar, display name |

**Tests:** 55 passing (`flutter test`): kit checksums, theme tokens vs CSS, theme, l10n, errors / logging (incl. release redaction), settings, icons, navigation (incl. TalkBack tab activation), golden (tab bar EN/AR × light/dark).
**Coverage:** `lib/core` 98.0 % (347 / 354 lines), every core file loaded by a test; no domain layers yet.

**Review:** self-review fixed 2 bugs (icon colour force-unwrap; duplicate log sinks). `/code-review` found 10, all fixed:
1. `proto_shot.py` crashed after the first screen (null splash) → `?.remove()`.
2. `ScreenEntranceTransition` leaked a listener per rebuild (CurvedAnimation) → `animation.drive(CurveTween)`.
3. Tabs had no semantic tap action (TalkBack / VoiceOver couldn't switch tabs) → `onTap` on `Semantics`; new test proven to fail without the fix.
4. CI kit check could miss new untracked kit files → tests on the committed copy first, then `git status --porcelain` after a fresh sync.
5. Coverage gate passed when a file had no test → every file on disk must appear in lcov (proven with a dummy untested file).
6. Logs could carry free text from errors in release → release builds redact failure messages and error text (tested).
7. `extract_strings.py` could crash on mismatched quick phrases → checks and clear errors.
8. `Result.guard` swallowed programming `Error`s → only `Exception`s are converted; `Error`s propagate (tested).
9. `IsharaColors.copyWith` covered 3 of 35 tokens → all 35 (generated from the fields, tested).
10. Duplicated prototype paths in 3 scripts → shared `tools/proto_common.py`.
**Screens:** only the tab bar is real UI so far: golden `test/goldens/goldens/linux/tab_bar.png` compared with the prototype tab bar (`tools/proto_shot.py learn`): same layout, icons, fonts, colours, indicator, RTL order. No differences found at this size.

**Open questions**
1. Disk: 4.2 GB free (not the 13 GB expected); the emulator isn't running. An Android build plus the Gradle caches needs about 2.5 GB. OK to run it, or will you free space first?
2. Android application id / iOS bundle id is `com.ishara.ishara_app` (from `flutter create --org com.ishara`). It can't change after the first store upload. Which id do you want?
3. Strings left out (78, all listed by `extract_strings.py`). The ones that need a **new draft text** in later steps: `loginLead` (says the glove syncs), `terms` (mentions backups), `yourTurnSub` (per-finger check), `pose3s` (4 s → 3 s), `c2` (rename), `pairLead` / `tip1` / `tip2` (button, light), `mDailyS` ("3 minutes"), `sAboutS` / `sAvatarS` / glove rows (real values), plus the email label and error texts for Q-B2.

### Step 2 follow-ups (2026-10-09)
- **Android build: ✓** `flutter build apk --debug --dart-define=GLOVE=mock` succeeded (cold Gradle cache, 640 s). APK: 167 MB debug, package `io.github.mmohamedtarek.ishara`, label "Ishara", compile/target SDK 36, sha1 `417d9234…`. `build/` deleted afterwards (2.1 GB) to keep disk free.
- App id changed to `io.github.mmohamedtarek.ishara` (Android namespace + Kotlin package, iOS bundle ids) before that build; `aapt2 dump badging` shows the new id and label.
- Back animation now matches the prototype (see DECISIONS); 3 new tests fail on the old code and pass on the new.

## Step 3: glove core (2026-10-09)

**Built:** `lib/core/recognition/` (config, labels, calibration, normalizer, Decider, ensemble, recognizer with the gap rule, isolate engine, recognition service, providers) and `lib/core/glove/` (frame codec, EVENT parser + line assembler, `GloveSource`, `GloveClient` protocol, transport interfaces, mock glove + feed + recordings, providers, failures).

| Checklist (source) | Status |
|---|---|
| Sample = seq + 11 raw values (AI-SPEC §1, BLE §4) | ✓ `GloveSample` |
| Mock CSV parsing, `#` lines as messages, 16-bit seq (AI-SPEC §1) | ✓ `Recording` |
| Frame decoder, all of `ble_frames.txt` (BLE §4, §9) | ✓ 10 frames / 50 samples identical; encode = inverse; bad frames rejected |
| EVENT lines: split notifications, every contract line, unknown ignored (BLE §6) | ✓ |
| Normalize 1e-4 (AI-SPEC §3) | ✓ 6/6 cases |
| Window 100, run every 10 (AI-SPEC §4) | ✓ (ring buffer, order tested) |
| Gap rule v3.2.1 + `gaps` vector (AI-SPEC §4, Q-K1) | ✓ 24/24 events at the exact inputs |
| Ensemble, each model + average 1e-3 (AI-SPEC §4) | ✓ 6/6 cases, 3 models |
| Decider exact, Python rounding, confirm_on_rest ignored (AI-SPEC §5, C7, C8) | ✓ 23/23 events at exact steps |
| 88 mock files exact (C6) | ✓ **88/88** identical events and words |
| Reset on reconnect and new `#CAL` (AI-SPEC §2, §5) | ✓ |
| Isolate; events + smoothed probability per step (Q-L4) | ✓ `IsolateRecognizer` (tested with a real isolate), `RecognitionService` |
| `GloveSource`: samples, calibration, battery, connection; mock at real 50 Hz with `#CAL`/`#BAT`/connection; frames through the same decoder | ✓ 50 Hz measured (≈500 samples / 10 s, consecutive seq) |
| `BleGloveSource` per contract | ◐ protocol done and tested (`GloveClient` + scripted link: order, proto check, timeouts, rejections, disconnect, MTU error); **radio transport waiting for the BLE library decision** |
| `GLOVE=mock\|ble` flag + developer switch; only `core/glove` knows | ✓ + architecture test that fails if any other file references it |
| Labels/config from the kit, nothing hard-coded | ✓ + architecture test scanning `lib/` for label literals |
| Scenario player (word / sentence with idle, A and B, practice files) | ✓ `MockFeed` (UI picker comes with Talk/Learn) |
| Practice check on mock (Q-L5) | ✓ both people × 20 signs: "Sign now" confirms exactly that sign once |
| Recognizer step < 20 ms | ✓ host: 0.43 ms mean, p95 0.48 ms (i7-13650HX). **Phone number pending** (performance step) |

**Tests:** 247 passing + 1 skipped benchmark (`flutter test`); benchmark separate (`--run-skipped --tags bench`). **Coverage:** `lib/core` 97.2 % (1535/1579), every file loaded by a test.

**Review:** `/code-review` (high) found 10 issues, all fixed, each with a regression test (`test/glove/review_regressions_test.dart`):
1. A glove with `#CAL NONE` (or another glove, or the dev switch) kept the previous calibration → words from wrongly scaled data. Now the engine forgets the calibration and ignores samples until a `#CAL` (mutation check: re-introducing the bug makes the test fail).
2. Resets (reconnect, new `#CAL`, link lost) dropped a tentative word without `cancel`, leaving it faded on screen forever → every reset now emits the cancel; the service resets when streaming stops.
3. Any `Error` in the recognizer isolate killed it silently, and `spawn` could hang → the worker reports and keeps running; exit and errors are watched; `spawn` fails cleanly.
4. `dispose` killed the worker before it freed the native interpreters → waits for the worker's acknowledgement (≤ 2 s).
5. `connect` didn't notice a disconnect / dispose / second connect while linking (leaked links, timers) → connection generation token.
6. A failed write left a stale pending command that stole the next reply → removed on write failure.
7. Mock: an MTU drop while streaming looped forever → stops and sends `#ERR STREAM MTU` like the firmware.
8. Mock: changing person while streaming threw on every tick until the file loaded → new recording loaded before switching.
9. An `Error` during setup left the status stuck in "connecting" → always cleaned up, the `Error` still surfaces.
10. Unsolicited `#ERR STREAM MTU` left the status "ready" → the session ends (reconnect offered); a broken `#CAL` reply fails GETCAL at once instead of timing out.
**Mutation checks:** breaking the Decider `hold` rule fails 80+ mock files; shrinking the gap fill fails `gaps`.
**Bugs found by tests and fixed:** `#BAT` lost to a subscribe/listen race; `CAL CANCEL` couldn't cancel a running step; wrong expectation in my float32 test (implementation matched numpy).

**Open questions**
1. **BLE library** (flutter_blue_plus licence + build telemetry): which one? Recommendation: `flutter_reactive_ble` (BSD-3, Philips Hue, Android + iOS, updated 2026-09).
2. 16 KB page-size check of the LiteRT native libraries: on the next APK (performance step).
