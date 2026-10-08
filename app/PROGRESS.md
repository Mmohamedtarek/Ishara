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
