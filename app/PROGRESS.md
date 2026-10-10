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

### Step 3 follow-up: BLE transport (2026-10-09)
- `flutter_reactive_ble` 5.6.0 (user decision), licence and network checked first (see DECISIONS).
- `lib/core/glove/ble/reactive_ble_transport.dart`: adapter state → `BluetoothUnavailableFailure` (off, unauthorized, location off, unsupported); scan filtered to `Ishara-XXXX` + service, deduplicated, strongest first, ends on time; connect → MTU 247 (Android only) → service check (all 4 characteristics) → link; notifications forwarded (listen first, then subscribe); CMD write with response; close / remote disconnect / notification error close the link; cleanup on every failure path. Replaces the "unsupported" stand-in.
- Tests: 18 (fake `BleApi`), including GloveClient end to end over the adapter (ready, `#BAT`, frames, out of range). Tests that close connections run in short real time (a broadcast cancel completes in the root zone, which FakeAsync never runs).
- **Android build: ✓** (62 s with a warm cache) after `compileSdk = 37` (required by reactive_ble_mobile). **16 KB page size: ✓** `zipalign -c -P 16`: all 18 native libraries aligned. Merged manifest checked: no location permission on Android 12+.
- **Not tested on hardware yet:** the real glove over BLE needs the user's phone (Pair step).
- Totals: 264 tests passing (+1 skipped benchmark), analyze 0 issues. `lib/core` coverage 95.7 %: the uncovered lines are `FlutterReactiveBleApi`, the thin wrapper over the plugin (needs a device).
- Note: the AI team fixed the AI-SPEC §8 sentence (Keras vs tflite); it reaches the app when the updated kit is synced.

### Step 3 follow-up: BLE review (2026-10-09)
`/code-review` of the BLE adapter found 10 issues; all fixed with 7 new regression tests (`a295b55`). Remaining by design: runtime permission prompts come with the Pair screen (step 6); iOS Bluetooth text is a draft.

## Step 4: sign catalogue and language packs (2026-10-09)

**Built:** `lib/core/packs/` (SignLanguage, SignLanguagePack, PackRegistry, providers), `lib/core/catalogue/` (SignCatalogue, WordNormalizer, SpeechToSign), `assets/packs/asl/signs.json` (25 signs), `lib/core/ui/sign_language_picker.dart` (pills + ArSL dialog). Kit assets moved to `assets/packs/asl/kit/`.

| Checklist (source) | Status |
|---|---|
| `signs.json`: label, en/ar words + spoken + variants, category, glove, avatar, verified, description (prompt › Sign catalogue) | ✓ 25 entries (20 glove, 15 avatar) |
| One word list; everyone reads the catalogue (prompt; CLAUDE.md) | ✓ provider `signCatalogueProvider`; Learn/Talk/avatar use it from their steps |
| SignLanguage enum, pack per language under `assets/packs/<lang>/`, registry with `available`, one provider (prompt) | ✓ |
| ASL default; ArSL → dialog EN/AR + OK/تمام, ASL kept, nothing saved; "Coming soon"/"قريبًا" badge; stored `arsl` → ASL; nothing runs with ArSL | ✓ tested (rules + widget, EN and AR) |
| Exact speech → sign matching after normalization; Q-T5 aliases only (sign rule 7) | ✓ |
| Tests: every model label has an entry; practice = glove signs; avatar:true ⊆ engine library; no normalized collisions; 4 sign-language tests | ✓ (avatar library = the prototype's SIGNS with love → iloveyou until the engine is ported) |
| Drafts shown before shipping | ✓ table below |

**Tests:** 317 passing (+1 skipped benchmark). **Coverage:** `lib/core` 96.0 %. Analyze: 0 issues.

**Review:** `/code-review` found 10 issues, all fixed with tests: (1) speech mapped to signs the avatar can't perform → no sign, ready pose; (2) draft variants were live → skipped until approved; (3) a catalogue of another/unavailable language could load → refused; (4) phrases spanned punctuation ("Thank. You") → stop at sentence punctuation; (5) glued words ("hello,you") lost their signs → split; (6) non-text "language" threw a TypeError → ParseFailure; (7) the catalogue waited for the 3 model files → reads only labels.txt; (8) hard-coded ASL paths → derived from the pack registry; (9) a double tap opened two dialogs → guarded; (10) the dialog had no screen-reader name → semanticLabel.
**Screens:** golden `test/goldens/goldens/linux/sign_language_picker.png` (EN/AR × light/dark) vs prototype Setup (`tools/proto_shot.py setup`): same pill style (glass, 1.5 px border, selected tint + check, 13.5 px / 800), both wrap onto two rows. Differences: ASL selected by default (decision), new "Coming soon" badge (draft), 48 dp height vs 44 px.

**Drafts for approval (signs.json)** — G = glove, A = avatar, V = verified:

| label | glove / avatar / verified | EN word · spoken · variants | AR word · spoken · variants | draft fields |
|---|---|---|---|---|
| one | G / - / V | One · one · one | واحد · واحد · واحد | en.word, ar.word, ar.spoken, ar.variants |
| two | G / - / V | Two · two · two | اتنين · اتنين · اتنين, اثنين, اثنان | en.word, ar.word, ar.spoken, ar.variants |
| three | G / - / V | Three · three · three | تلاتة · تلاتة · تلاتة, ثلاثة | en.word, ar.word, ar.spoken, ar.variants |
| four | G / - / V | Four · four · four | أربعة · أربعة · أربعة | en.word, ar.word, ar.spoken, ar.variants |
| five | G / - / V | Five · five · five | خمسة · خمسة · خمسة | en.word, ar.word, ar.spoken, ar.variants |
| me | G / A / V | Me · me · me, i | أنا · أنا · أنا | en.word, ar.spoken |
| you | G / A / V | You · you · you | إنت · إنت · إنت, إنتي | en.word, ar.word, ar.spoken |
| hello | G / A / V | Hello · hello · hello, hi, hey | أهلاً · أهلاً · أهلاً, السلام عليكم | ar.spoken |
| thanks | G / A / V | Thank you · thank you · thank you, thanks, thank | شكراً · شكراً · شكراً | ar.spoken |
| please | G / A / V | Please · please · please | من فضلك · من فضلك · من فضلك, لو سمحت | ar.spoken, ar.variants:لو سمحت |
| yes | G / A / V | Yes · yes · yes | أيوه · أيوه · أيوه | ar.spoken |
| no | G / A / V | No · no · no | لأ · لأ · لأ, لا | ar.spoken |
| sorry | G / A / V | Sorry · sorry · sorry | آسف · آسف · آسف, آسفة | ar.spoken, ar.variants:آسفة |
| water | G / A / V | Water · water · water | مية · مية · مية | ar.spoken |
| bye | G / - / V | Bye · bye · bye, goodbye | مع السلامة · مع السلامة · مع السلامة, باي | en.word, en.variants:goodbye, ar.word, ar.spoken, ar.variants |
| come | G / - / V | Come · come · come | تعالى · تعالى · تعالى, تعال, تعالي | en.word, ar.word, ar.spoken, ar.variants |
| drink | G / - / V | Drink · drink · drink | اشرب · اشرب · اشرب | en.word, ar.word, ar.spoken, ar.variants |
| call | G / - / V | Call · call · call, phone | اتصل · اتصل · اتصل, تليفون | en.word, en.variants:phone, ar.word, ar.spoken, ar.variants |
| iloveyou | G / A / V | I love you · I love you · i love you | بحبك · بحبك · بحبك | ar.spoken |
| hungry | G / - / V | Hungry · hungry · hungry | جعان · جعان · جعان, جعانة | en.word, ar.word, ar.spoken, ar.variants |
| coffee | - / A / ? | Coffee · coffee · coffee | قهوة · قهوة · قهوة | category, ar.spoken |
| doctor | - / A / ? | Doctor · doctor · doctor, doctors | دكتور · دكتور · دكتور, الدكتور | category, ar.spoken |
| home | - / A / V | Home · home · home | بيت · بيت · بيت, البيت | category, ar.spoken |
| family | - / A / ? | Family · family · family | عيلة · عيلة · عيلة | category, ar.spoken |
| help | - / A / ? | Help · help · help | مساعدة · مساعدة · مساعدة, ساعدني | category, ar.spoken |

**Open questions:** all answered 2026-10-09 (DECISIONS S4-1…S4-5): drafts approved and removed from `signs.json`; ArSL dialog (AR) uses "إشارة"; masculine spoken forms for now (future profile setting); iOS Bluetooth text and badge approved. Vocabulary v2.2 (V-2, V-3): WATER/COME descriptions updated.

## Step 5: avatar WebView (started 2026-10-09)

**Checklist (before coding)**

| # | Requirement | Source |
|---|---|---|
| 1 | WebView runs the prototype's Three.js engine, **ported, not rewritten** (same IK, CURL, baking, playback, camera, lights, face) | prompt › Avatar; prototype l.1393–2105 |
| 2 | three.js 0.186.0 + GLTFLoader + meshopt decoder + the 2 GLBs bundled as local assets; no CDN, works offline | prompt › Avatar; Phase 0 §2 |
| 3 | Served by a local loader so ES modules load (loopback HTTP server, 127.0.0.1, random port + token, assets allow-list only) | prompt › Avatar; DECISIONS (2026-10-08 webview_flutter + loopback) |
| 4 | One typed `AvatarController`: `play(label, speed, loop)`, `stop()`, `setCharacter()`, `customize()`; events `ready`, `signStarted`, `signEnded`, `error` | prompt › Avatar |
| 5 | One WebView alive for the whole app, moved between screens (slots) | prompt › Avatar; Phase 0 architecture |
| 6 | Sign library per pack (`assets/packs/asl/`), labels only; no word mapping inside the engine (catalogue does it; Q-A5 aliases gone) | prompt › packs; sign rule 7; Q-A5 |
| 7 | `love` → `iloveyou` (Q-A4); I LOVE YOU held still (Q-A3); PLEASE B hand, SORRY A hand unchanged (Q-A3) | DECISIONS |
| 8 | WATER: index fingertip taps the **mouth** (V-3) | DECISIONS V-3; ASL-REFERENCES |
| 9 | Finger spread in the engine as data + a few lines in `curlHand`; FIVE vs FOUR and TWO vs NO shown in the preview | Q-A6 |
| 10 | 10 new signs in the engine format (one two three four five bye come drink call hungry), new CURL shapes (C, Y, numbers, bye flap), COME = one arc (V-2) | prompt sign rule 2; ASL-REFERENCES; vocabulary v2.1 + V-2 |
| 11 | Preview screen for every sign, front + side; new signs stay `avatar: false` (no speech/Learn use) until the user approves the preview | prompt step 5; sign rule 2 |
| 12 | Every `avatar: true` sign exists in the engine library | prompt › Catalogue tests |
| 13 | No leaks (WebView, channels, server), WebView can't navigate anywhere else; avatar never blocks the UI | prompt › review; security |
| 14 | 60 fps target on a mid-range Android phone (measured on device later; emulator number recorded) | prompt › Performance |
| 15 | Reduced motion honoured (OS setting passed in, not the WebView media query) | prototype `reduce`; accessibility |
| 16 | RB-1: characters are data (cast list), nothing in code depends on the model files | DECISIONS RB-1 |

**Built:** `assets/avatar/` (engine.js ported from the prototype, index.html with CSP, style.css, cast.json, three.js 0.186.0 vendored by `tools/vendor_three.sh` with SHA256SUMS, nour/sara GLBs), `assets/packs/asl/avatar/library.json` (15 ported signs + 10 new drafts, shapes incl. spread, previewPairs), `lib/core/avatar/` (AvatarLibrary, AvatarCast, AvatarEvent, AvatarController, AvatarAssetServer, WebViewAvatarPage / UnavailableAvatarSurface, AvatarSlotRegistry / AvatarSlot / AvatarParking, AvatarHost / AvatarStage, providers), `lib/features/dev/presentation/sign_preview_screen.dart` (`/dev/signs`, debug/profile only), Android INTERNET + loopback-only cleartext, iOS NSAllowsLocalNetworking. Tools: `extract_avatar_library.mjs`, `fmt_avatar_library.py`, `avatar_shots.py` (front/side contact sheets), `avatar_port_check.py` (port vs prototype pixels).

| # | Status | Evidence |
|---|---|---|
| 1 ported, not rewritten | ✓ | `avatar_port_check.py`: 71 frames of the 13 unchanged signs, worst mean pixel difference 0.07/255 vs the prototype; library test: 13 signs byte-identical to the prototype data (sha256-pinned fixture) |
| 2 offline, local three.js + GLBs | ✓ | page test: no remote URL, CSP `default-src 'none'`; three.js checksums |
| 3 loopback loader | ✓ | 6 server tests (types, token, traversal, host header, methods) |
| 4 typed AvatarController + events | ✓ | 14 controller/protocol tests |
| 5 one WebView for the app | ✓ | host widget tests: one view instance, never recreated across push/pop, parked + paused offstage, tabs, lifecycle |
| 6 library per pack, no word mapping in the engine | ✓ | page test (no ALIASES/poseNameFor code); catalogue test vs library |
| 7 Q-A3/Q-A4 | ✓ | iloveyou held still (test) |
| 8 V-3 WATER at the mouth | ✓ landmark; ✗ contact (see open questions) | review sheet `tools/out/avatar_review/water_nour.png` |
| 9 spread (Q-A6) | ✓ | shapes v/three/four/five/y; preview pairs FIVE/FOUR, TWO/NO |
| 10 10 new signs | drafts; CALL not right | sheets in `tools/out/avatar_review/` |
| 11 preview screen | ✓ | widget test; emulator |
| 12 avatar:true ⊆ library | ✓ | catalogue test (new signs stay avatar:false until approved) |
| 13 leaks / navigation lock | ✓ | dispose paths tested; WebView may only open the server's pages |
| 14 60 fps | emulator ✓ (RTX 4050 host GPU): 58.9–60.5 fps; phone pending | `integration_test/avatar_test.dart` |
| 15 reduce motion from the OS | ✓ | host test |
| 16 RB-1 characters as data | ✓ | cast.json; cast tests |

**Emulator (`ishara_api36`, -gpu host via NVIDIA PRIME offload):** `integration_test/avatar_test.dart` 3/3 runs pass: ready in 2.9–3.8 s, 25/25 signs play to the end with the library's timing, 58.9–60.5 fps. Earlier on the software GPU: ~20 fps, and 2 runs where no page event arrived after `ready` (machine overloaded; the emulator itself died twice). Not reproduced on the hardware GPU in 3 runs. Mitigation for Talk (step 7): never wait for `signEnded` without a timeout (library duration + margin).

**Review:** `/code-review` found 10 issues, all fixed with tests: (1) a dialog over an avatar screen took the avatar away and paused it → slot visibility = route on stage and not leaving; (2) the preview screen left the shared avatar turned / frozen → reset on close; (3) commands sent while the page reloaded were lost and state (pause, stats, caption, tint) not restored → `pageStarted` event, queue, replay; open signs end as interrupted; (4) a page load failure stayed `loading` forever → `page` is fatal; (5) the engine hard-coded `hello` → pack data `greeting`; (6) `setCharacter` returned an id that might never end → returns nothing; (7) assets read with the whole backing buffer → `readAssetBytes` with offset/length; (8) paused signs were still reported as played → pause interrupts; (9) encoded `/` or leading `.` in a path segment → refused; (10) three copies of the asset reader → one. Also from my own review: on iOS the dispose `about:blank` load was blocked by the navigation guard → allowed.

**Tests:** 375 passing (+1 skipped benchmark), `lib/core` 94.8 % (webview_avatar_page.dart 30 %: only testable on a device, covered by the emulator test). Analyze: 0 issues. Emulator (hardware GPU): avatar test passes, incl. pause → interrupted; screenshot `tools/out/avatar_review/device_preview_emulator.png`.

**Screens:** the only new screen is the developer preview (not in the prototype, debug only, English). The avatar stage uses the prototype's `#avatar` look (radius 24, stage gradient tokens, silhouette placeholder). Differences: the inset shadow is a bottom gradient (Flutter has no inset shadow); the placeholder has no drop shadow. Talk / Welcome / Mission screens with captions come in their steps.

**Open questions (step 5)**
1. New sign previews for approval (front + side, keyframe moments): `app/tools/out/avatar_review/{one,two,three,four,five,bye,come,drink,hungry,call}_nour.png`; FIVE vs FOUR and TWO vs NO in the same folder (`no_nour.png`). They stay `avatar: false` until approved.
2. CALL is not right yet (7 attempts): the engine has one fixed elbow direction and fixed thumb opposition, so a Y hand at the ear either lifts the elbow to shoulder height or turns the thumb forward instead of up to the ear. Options: (a) accept a simpler form (Y hand beside the cheek, as now) for v1; (b) let a keyframe set the elbow direction (engine change, beyond "port, not rewrite"); (c) you send a frame-by-frame reference and I try again.
3. Contact depth: the prototype's body-depth measurement finds no vertices for both characters, so every contact (WATER at the mouth, ME at the chest, THANK YOU at the chin) uses one fixed depth; the fingertips stop about 2–4 cm in front of the face. Fix the measurement (engine change) or keep the prototype behaviour?
4. Real FPS on your phone (`flutter test integration_test/avatar_test.dart -d <phone>`).

### Step 5 follow-up: AI-team review of the emulator recording (2026-10-09)

| Item | Status | Evidence |
|---|---|---|
| 1 Logo / splash / launcher | ✓ | `brand/ishara_mark.svg` + `tools/make_brand.py`; adaptive + monochrome icon, legacy PNGs, Android 12+ splash, light / dark launch background, iOS AppIcon / LaunchScreen; splash golden EN/AR × light/dark (`test/goldens/goldens/linux/splash.png`); `test/brand/brand_assets_test.dart` (no icon equals any of 87 Flutter template images); emulator: `tools/out/device/launcher_drawer.png`, `launch_sequence_{light,dark}.png` (no white / light flash, no Flutter logo) |
| 2 Preview follows the playing sign | ✓ | widget test (another caller's `play`, live time at 1x and 1.5x); recording `tools/out/device/signs_preview_recording.mp4`, frames `recording_frames.png` |
| 3 CALL / HOME elbow (b), contact depth fix, guard | ✓ | engine: skinned-vertex measurement, contact correction (0 mm residual, `tools/avatar_contacts.py`), `E` elbow keys; port check: 6 untouched signs worst 0.06 / 255; before / after side views `tools/out/before_side/`, `after_side/`, front `tools/out/port/` |
| 4 Signs | see report | `tools/out/review2/index.html`: 25 signs, front + side at every keyframe, Lifeprint link, status (fixed / unchanged / needs your call) |
| Emulator test | ✓ | 25/25 signs, pause interrupts, 60 fps (hardware GPU) |

**Tests:** 386 passing (+1 skipped benchmark), `lib/core` 94.8 %, analyze 0 issues.

**Review (follow-up):** `/code-review` found 10 issues, all fixed: (1) the preview's clock could be created during dispose (debug assertion) → created in initState, test "opened and closed untouched"; (2) the splash created CurvedAnimations on every rebuild (listener leak) → curves made once with `drive`; (3) the port check exempted whole signs → only contact / elbow frames (and YOU) are exempt: 38 frames must match the prototype, worst 0.055 / 255; (4) a rig without fingertip end bones would press contacts in by one segment → tip extrapolated past the last joint; (5) the measurement skinned every mesh → eyes, lashes, teeth, shoes and trousers skipped (same surface depths); (6) splash colours duplicated tokens → `track`, `stageB`; (7) a second copy of the pop-in transform → shared `PopIn` / `popInMatrix`; (8) thumb-spread comments were wrong → corrected; (9) the preview kept following a dead controller → detaches; (10) `_dbg.contacts()` repeated hold frames → skipped.

### Step 5 review, round 2 (2026-10-10)

| Item | Status | Evidence |
|---|---|---|
| 1 Splash debug text style | ✓ fixed | `Material` above the splash; real-root golden `test/goldens/goldens/linux/splash.png`; test fails if any splash text uses the debug style (verified by removing the fix) |
| 2 Mark moves from the native centre into the group | ✓ | layout delegate; tests: first frame at the screen centre, in place after 300 ms, group centred, no movement with reduced motion, late window size; emulator `tools/out/device2/l4/{light,dark}_run1.png` |
| 3 CALL / HOME | ✓ (for your eye) | `tools/out/call3/call_nour.png`, `tools/out/home3/home_nour.png` (front, side, 3/4); Sara CALL `tools/out/call_both/both.png` (hair clipping: known issue) |
| 4 HELP / COFFEE / DOCTOR / FAMILY vs references | HELP, COFFEE, FAMILY match; DOCTOR differs (palm, not wrist) — your call | `tools/out/review2/index.html` |

**Also found and fixed on the emulator:** the splash measured its target at a 0 × 0 window (mark sent to a corner); the gradient divided by zero at 0 × 0; the splash time ran out before the first visible frame on a cold start; an instant Android 12 splash exit showed black frames (reverted to the default).
**Guard:** 38 prototype frames still match (worst 0.061 / 255).
**Tests:** 389 passing, `lib/core` 94.8 %, analyze 0 issues.

**Review (round 2):** `/code-review` found 8 issues, all fixed: (1–3) HOME, CALL and the flat-O shape are now pinned exactly in the tests (a mutation of HOME's cheek touch fails); (4) the splash no longer forces frames while the window is 0 × 0: the layout delegate reports the first real size and the clock starts once, after that frame; (5) reduce-motion is read in `didChangeDependencies` only; (6) the HOME test name matched an old check → renamed; (7) one mark widget, placed by the delegate in both modes; (8) the mark's move runs on its own 300 ms controller, so layout follows it only while it moves.

### Step 5 review, round 3 (2026-10-10)

| Item | Status | Evidence |
|---|---|---|
| 1 Splash | ✓ approved (round 2) | — |
| 2 CALL: thumb at the earlobe, pinky toward the mouth corner, elbow kept | ✓ for your eye | `tools/out/round3/call_{nour,sara}.png`; elbow 41 mm below the shoulder before and after (Nour) |
| 3 HOME: closed flat-O; first touch at the mouth corner | ✓ Nour; Sara slightly open (RB-1 known issue) | `tools/out/round3/home_{nour,sara}.png`; fingertip-to-thumb-pad 11–21 mm (Nour, joint centres) |
| 4 DOCTOR: tap the inside of the other wrist | ✓ for your eye | `tools/out/round3/doctor_{nour,sara}.png`; tip 15 mm from the wrist joint (Nour) |
| 5 Sara hair → RB-1 | ✓ | DECISIONS.md, RB-1 known issues |

**Engine:** optional per-shape `split` (validated in `AvatarLibrary`, test added); debug-only `_dbg.bake(R, L)` and shape tables for measuring.
**Tests:** HOME, CALL, DOCTOR and the flat-O pinned exactly; DOCTOR moved out of the byte-for-byte prototype list. **Guard:** 33 prototype frames still match (worst 0.055 / 255); DOCTOR frames exempt as a decided change.

**Review (round 3):** `/code-review` found 9 issues. Fixed: the prototype-shapes test now also rejects a `split`; validator tests for every `split` branch; `split` documented as fingers-only; `_dbg.bake` guarded; simpler split check; a dated DECISIONS row supersedes "DOCTOR not changed"; port-check docstring. Reported, not built: DOCTOR's wrist tap is fixed coordinates tuned on Nour (Sara: 34 mm, at the heel of the palm); a contact target relative to the other hand would fix it for every character (proposal for the user).

### Step 5 review, round 4 (2026-10-10)

| Item | Status | Evidence |
|---|---|---|
| CALL, HOME, DOCTOR on Nour | ✓ approved by the user | — |
| Contacts on the other hand (engine + validator) | ✓ | `_dbg.contacts()`: 0 mm on every DOCTOR, HELP, COFFEE contact, Nour and Sara |
| DOCTOR / HELP / COFFEE before → after | ✓ for your eye | `tools/out/round4/before/*.png`, `tools/out/round4/after/*.png`; Sara check `tools/out/round4/sara/` |
| Guard: only these signs changed | ✓ | port check: 19 prototype frames still match (worst 0.002 / 255); HELP / COFFEE / DOCTOR contact frames exempt |
| Sara hidden behind one flag | ✓ | `cast.json` `hidden`; tests: Nour only + no picker, stored "sara" → Nour, flag off brings her back, bad flags refused; engine: `tools/avatar_cast_check.py` (asked for Sara → Nour shown, no error, her model never downloaded) |

**Not built yet:** the Setup / Settings / Avatar studio pickers (skeleton screens); they must list `AvatarCast.characters` and show a choice only when `showPicker` (S5-13).

**Review (round 4):** `/code-review` found 10 issues; 9 fixed: the aim rule now checks the keys in effect (a carried key), the aimed-at hand may not touch the body, `edge` only with a closed hand at a contact point, hidden characters fully checked, the controller resolves ids through the cast (test: stored "sara" → Nour at start and in setCharacter), base hands pinned to the prototype, unused `hiddenIds` dropped, hand points read once per frame, S5-12 says the user asked for HELP / COFFEE. Kept: the extra arm solve per other-hand frame (about 16 frames, at character load). Re-checked after the fixes: contacts 0 mm, `avatar_cast_check` OK, port check 19 frames worst 0.000.

### Step 5 review, round 5 (2026-10-10)

| Item | Status | Evidence |
|---|---|---|
| HELP, DOCTOR, Sara hidden | ✓ approved by the user | — |
| S hand: thumb across the fingers (COFFEE, YES) | ✓ for your eye | `tools/out/round5/after/{coffee,yes}_nour.png` (front, side, 3/4); before: `tools/out/round5/{coffee,yes}_nour_before.png`; candidates: `tools/out/round5/cands/cmp2.png` |
| Only YES / COFFEE changed | ✓ | port check: 14 prototype frames match (SORRY included), worst 0.072 / 255; COFFEE contacts 0 mm |
| Kit v3.2.2 synced | ✓ | 96 files; kit checksum test; 88/88 mock files = expected.json; practice files confirm each sign once (both people) |

**Checks (round 5):** `flutter analyze` 0 issues; 393 tests passing; `lib/core` coverage 94.8 %; contacts 0 mm (COFFEE, HELP, DOCTOR, HOME, HELLO, PLEASE); port check 14 frames worst 0.066 / 255. **Review:** `/code-review` found 7 issues, all fixed: the thumb rest-curl calibration stays measured against 80° when a shape sets `thumbMax`; a misplaced engine comment; `thumbDir` weights bounded [0, 4] and `thumbMax` ≤ 180° (tests); the default thumb direction is a named constant read once per hand; S5-14 records that the user asked for the shape fix; the port-check note says YES's keyframes stay pinned byte-for-byte; these counts.
