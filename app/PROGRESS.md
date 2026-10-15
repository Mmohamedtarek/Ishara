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

### Step 5 review, round 6 (2026-10-10)

| Item | Status | Evidence |
|---|---|---|
| 10 new signs approved → `avatar: true` | ✓ | signs.json; catalogue tests: "hungry" / "جعانه" now play `hungry`; the no-sign rule is tested with a catalogue where one sign is `avatar: false`; the preview's "pending approval" marker is tested the same way |
| COFFEE approved (round 5) | ✓, but its fists changed with the S thumb below → please recheck | — |
| S thumb flat across the fingers (YES, COFFEE) | ✓ for your eye | `tools/out/round6/yes/yes_nour.png`, `tools/out/round6/coffee/coffee_nour.png` (front, side framed on the hands, 3/4); measured in the hand's frame: the thumb's IP joint 1 cm outside the index's middle segment, its tip 1 cm outside the middle finger's (round 5: near the wrist, 1.5 cm below the fist) |
| Only YES / COFFEE changed | ✓ | port check 14 prototype frames (SORRY included), worst 0.046 / 255; contacts 0 mm |

**Engine:** `thumbTo: "fingers"` (CCD; the base joint free, the outer joints on their hinge; solved once per character, hand and shape) replaces round 5's `thumbMax` / `thumbDir`. Validated: only `"fingers"`, only on a closed hand (index and middle curled ≥ 70).
**Review:** `/code-review` found 9 issues, all fixed: a rig without a thumb end bone (the last joint is left out of the solve), hinge-only outer joints, the palm side from `palmNormal`, the cached solve, `thumbTo` only on closed hands, COFFEE back to "please check", the 10 signs "approved" in the report, these notes, a test for the pending-approval marker.

**Step 5 approved by the user (2026-10-10):** YES and COFFEE (the S thumb lies flat across the fingers from every angle). Step 5 is done.

## Step 6: onboarding, pair, calibration (started 2026-10-10)

Checklist (before coding), each traced to its source:

| # | Requirement | Source |
|---|---|---|
| 1 | Welcome: brand bar + EN/ع toggle; avatar hero with the "Hi, I'm Nour!" bubble waving `hello`; title, lead (avatar name from the cast), 3 features; Get started → Create account, I already have an account → Sign in, Continue as guest → Setup | prototype `#s-welcome`; RB-1 / S5-13 (name from the cast) |
| 2 | Login / Create account: segmented toggle, name (create only), **email** (not phone), password with show / hide, Forgot password, guest card, terms; field errors with `role=alert` semantics; no Remember me, no Google, no phone; loading and error states; `AuthRepository` + local fake | prototype `#s-login`; Q-B2; S6-1; CLAUDE.md (Firebase behind a repository with a fake) |
| 3 | Setup: 3-step header; who (I sign / I speak); sign language (ASL selected; ArSL → "coming soon" dialog, stays ASL); spoken language (Arabic default); avatar choice only when `showPicker` (Nour only → none); Continue → Pair | prototype `#s-setup`; sign rule 8; Q-B5; S5-13; Q-D4 |
| 4 | Pair: radar; scan → found (device card: real name `Ishara-XXXX`, real RSSI, battery after connecting, fw from INFO) → connecting (3 real checks) → connected; Scan again; tips (draft) | prototype `#s-pair`; Q-K2; Q-K3; BLE-CONTRACT §1, §3; S6-3 |
| 5 | Pair states the prototype lacks: Bluetooth off, permission denied, location off (Android ≤ 11), not found / timeout, `proto ≠ 1`, `#MPU FAIL`, connection lost; runtime permission prompts | Phase 0 screen map; BLE-CONTRACT §2, §6; PROGRESS step 3 (permissions come with Pair) |
| 6 | Calibrate: Step n of 3; OPEN / FIST (2 s) / TURN (3 s, text says 3 s) driven by `CAL OPEN/FIST/TURN`, then `CAL SAVE` → `#CAL {…}` to the recognizer; hold-still indicator from the gyro during OPEN / FIST; finger bars hidden until OPEN and FIST are done; rotation track during TURN; Back cancels (`CAL CANCEL`) | prototype `#s-cal`; BLE-CONTRACT §5, §7; Q-K4; Q-K7 |
| 7 | Calibrate failures: `MOVED`, `RANGE`, `MPU`, `CANCELLED`, `#FLEX WEAK i`, `#ERR CAL …`, disconnect; Skip only with a stored `#CAL` (else hidden, with the reason) | BLE-CONTRACT §6, §7; Q-K6 |
| 8 | Ready: no "96 %"; glove row with the real name and battery; sign language + voice + role; Start talking → Talk (role decides what comes first); Calibrate again / Calibrate now (skipped) | prototype `#s-ready`; Q-K5; Q-D4 |
| 9 | Restart: setup answers, paired glove and "onboarding done" persist; with onboarding done the splash goes to Talk and the last glove reconnects | S6-2 |
| 10 | Every new or changed text in EN + Egyptian Arabic, listed as a draft for approval | Q-D2; CLAUDE.md (drafts) |
| 11 | New packages: licence and telemetry checked (permission handling, local key-value store) | CLAUDE.md › Dependencies |
| 12 | Tests (repositories, validation, pair and calibration state machines on the mock glove, widgets, goldens), screenshots EN/AR × light/dark next to the prototype, mock integration test on the emulator | review protocol |

**Open (on the draft list):** signal bars from RSSI (Q-K2 says real RSSI, no thresholds anywhere: I show the dBm value and propose thresholds as a draft); finger bars after OPEN + FIST come from the flex values the phone received during each 2 s step (the glove sends `open` / `fist` only after `CAL SAVE`).

### Step 6 results (2026-10-10)

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Welcome | ✓ | goldens `onboarding_welcome`; emulator cold start `tools/out/step6/device/welcome_pair.png` (real avatar, "Hi, I'm Nour!") |
| 2 | Login / Create account (email only, fake repository) | ✓ | `test/onboarding/auth_screen_test.dart` (7), `test/auth/auth_repository_test.dart` (6); goldens `onboarding_create_account`, `onboarding_sign_in` |
| 3 | Setup | ✓ | goldens `onboarding_setup`; answers saved as chosen |
| 4 | Pair: scan → found → 3 real checks → connected | ✓ | `test/pair/pair_controller_test.dart` (10), `pair_screen_test.dart` (5); goldens `onboarding_pair_*`; emulator run |
| 5 | Pair states the prototype lacks | ✓ | permission once / for good, Android 11 location, Bluetooth off / location off / unsupported / not ready, not found (+ tips), failed check, `#MPU FAIL`, `proto ≠ 1` (tests + goldens) |
| 6 | Calibrate (OPEN 2 s / FIST 2 s / TURN 3 s, SAVE, live hand, hold still, rotation) | ✓ | `test/calibration/*` (17), `test/glove/live_hand_test.dart` (6); emulator: three steps + save in ~10 s |
| 7 | Calibrate failures, Skip only with a stored `#CAL` | ✓ | MOVED / RANGE / MPU / CANCELLED / `#FLEX WEAK` / `#ERR CAL` / disconnect (tests) |
| 8 | Ready (no 96 %, real glove line, answers) | ✓ | goldens `onboarding_ready`, `onboarding_ready_skipped` |
| 9 | Restart: answers, glove, done persist; splash → Talk + reconnect | ✓ | `test/profile/onboarding_store_test.dart` (7, incl. the export for the S6-2 migration), splash test; emulator: `ishara.*` keys saved in the phone store |
| 10 | New texts as drafts | ✓ (awaiting approval) | 74 drafts, `tools/out/step6/drafts.html`; ARB descriptions say "DRAFT" |
| 11 | Package licences / telemetry | ✓ | S6-4 |
| 12 | Tests, goldens, screenshots, emulator | ✓ | 515 tests, `lib/core` 94.1 %; 11 goldens × EN/AR × light/dark; prototype comparison `tools/out/step6/compare/*.png`; `integration_test/onboarding_test.dart` passed on `emulator-5554` |

**Emulator (mock glove, real store):** account 1.5 s → Setup → Pair found 1.1 s after the scan starts → 3 checks 0.7 s → OPEN / FIST / TURN + SAVE ~10 s → Ready → Talk; saved `{onboarding.version: 1, setup.role: speak, setup.spoken: en, glove.id: mock:ishara, glove.name: Ishara-M0CK, onboarding.done: true}`.

**Open (for the user):** the 74 draft texts; signal-bar thresholds (S6-6); the live calibration view (S6-5); the prototype differences kept on purpose (DECISIONS 2026-10-10). Not done here: the avatar picker (step 9, S6-9); email verification and the real reset email (step 10, S6-1); the database migration test (step 10, S6-2); the real-glove check on your phone (BLE permissions and pairing).

**Review (step 6):** `/code-review` found 10 issues, all fixed with tests: a drop during the 0.75 s pause after a step was overwritten (mutation-checked); Calibrate opened with no glove had no action (now "disconnected" + Pair again); Pair re-checks permissions / Bluetooth when the app resumes (back from settings); "Pair again" pushes Pair (it replaced the stack, so Back had nothing to pop); start-up reconnect stops the scan before connecting and refuses `#MPU FAIL` as pairing does; Back can't run twice; Welcome's greeting checks `mounted` and logs failures; the live view redraws on samples (the frame ticker only runs during a countdown); `main` warms the cast provider instead of repeating it; font names come from `IsharaFonts`.

**Step 6 review fixes (2026-10-10):** Arabic changes applied, drafts approved; dBm only in developer mode; test that the bars switch to the glove's `#CAL` after Save; "Captured" check as an icon (was an empty box). Review material redone: the Calibrate comparison now walks the prototype's own UI to its Calibrate screen (the old sheet showed Welcome) and covers all 10 states × EN/AR × light/dark (`tools/out/step6/compare/calibrate/`, plus 5 goldens for states the prototype lacks); the emulator video starts recording only once Ishara is in front (the old frames were the launcher, before install) and shows the real flow from the splash: Welcome → Login → guest → Setup → Pair → Calibrate → Ready → Talk (`tools/out/step6/device/onboarding_flow.mp4`, 42 s, 13 key frames checked). 515 tests, `lib/core` 94.1 %.
**Open (mock data vs firmware rule):** the mock glove plays the kit's `rest.csv` during every calibration step. That recording's gyro varies 10–41 °/s per 2 s window, above the firmware's 3 °/s still limit, so the live view says "Hand moving" while the mock glove answers OK; and Open and Fist get the same data, so the finger bars show "—". Asked the user.

**Kit v3.2.3 (2026-10-10):** merged `ai-tests` (2cf40f5, 65d9ff4); `sync_kit.sh` (102 files; the two new `calibration/` folders added to pubspec); the mock glove plays the calibration recordings. New tests: `mock_calibration_test.dart` (persons A and B: full calibration on the real mock glove + glove client + Calibrate screen: "Hand still" through OPEN and FIST, five real bars, ≥ 30° of TURN rotation, saved, Ready; fails with the old rest playback, mutation-checked), `mock_feed_calibration_test.dart` (looping, back to rest, `#CAL` source). Emulator: the paced flow again (`tools/out/step6/device/onboarding_flow.mp4`, Calibrate key frames checked: "Hand still" while capturing, bars 0-51 %, rotation −50° … +20°). Previous video kept in `device/old-v322/`.
**Open:** at the real data's ±42° the turned hand drawing leaves the card on the left / covers the finger labels on the right; the prototype does the same at its own ±33° (`device/prototype_turn_peaks.png`). Asked the user.

## CI fix: welcome golden made deterministic (2026-10-11)

**Failed:** CI run 38088177938 (commit 95fd6c0), job *Flutter app*, `flutter test --coverage`: 489 passed, 1 failed, 1 skipped. The failure was `onboarding_golden_test.dart` › `welcome` (variant: CI), 19,205 px. The AI and Firmware jobs passed; Android was skipped.

**Root cause (evidence):**
- In the `golden-failures` artifact, the isolated diff is exactly the four "Hi, I'm Nour!" bubbles (EN/AR × light/dark), with 0 px different outside the bubble band. The runner drew the bubble. The committed `ci/onboarding_welcome.png` (from 432af54) has none.
- Welcome reads `currentCharacterProvider`, which is the cast loaded from `rootBundle`. The golden test didn't override it, so the bubble and the name in the lead depended on whether the load finished before the capture (6 × `runAsync(2 ms)`).
- Reproduced on a Mac. The old test with the normal load drew the bubble. With a temporary real 300 ms delay on the cast load (not committed), it drew no bubble and matched the committed golden. The fixed test with the same delay draws the bubble.
- The committed `linux/` real-text golden already shows the bubble and is correct (unchanged).

**Fix (test only):** `onboarding_golden_test.dart` reads `assets/avatar/cast.json` once from the file and overrides `avatarCastProvider` with `AsyncData(cast)` for every scenario, so the cast is loaded from the first frame, as in `main.dart`. No product code changed, no tolerance changed, nothing skipped.

**New `ci/onboarding_welcome.png`:** the CI runner's own `onboarding_welcome_testImage.png` from run 38088177938 (user decision). It was used instead of `--update-goldens` on this Mac, because:
- On the Mac the fixed test's image is identical (0 px) to the old test's image whenever the cast loaded in time, so the runner's image is what the fixed test draws.
- A Mac-made golden differs from the runner's by 20 px on the bubble edges, and would fail CI.

No other golden changed.

**Checks (MacBook, Apple Silicon, Flutter 3.47.6 in `~/development/flutter`):**

| Check | Result |
|---|---|
| pub get, gen-l10n, build_runner | ✓ |
| `flutter test test/kit`, then `sync_kit.sh` | ✓ 3 passed, no drift |
| `dart format` | ✓ 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | ✓ no issues |
| `CI=true flutter test --coverage` | 463 passed, 1 skipped, 27 failed. All 27 are CI goldens that differ by 1–83 px on this Mac (Apple Silicon rasterising vs the Linux-made goldens), welcome included: 23 px of bubble edges now, instead of 19,205. Every non-golden test passes. |
| Coverage gate | ✓ `lib/core` 94.1 % |
| `pio run -e devkit -e xiao -e wokwi` | ✓ (build only, no firmware change) |

**CI after the push:** run 38164162404 on `eaa9286`, all 4 jobs green (Flutter app, Android build, AI, Firmware). Flutter app: 490 tests passed, 1 skipped, `lib/core` 94.1 %.

**Not verified here:**
- Platform goldens (`flutter test` without `CI=true`) can't be compared on a Mac: it uses `goldens/macos/`, and only `linux/` is committed.

**Notes:**
- CI goldens are not pixel-identical across OS / CPU, contrary to the earlier assumption. They match between Linux machines.
- The suite has 491 tests today; the Step 6 entry says 515.

## Step 7a: Talk, speech → sign (2026-10-12)

Checklist (before coding), each traced to its source. Your answers to the plan are S7-1…S7-13 (DECISIONS).

| # | Requirement | Source | Status |
|---|---|---|---|
| S1 | Mic card idle / listening (state dot, pulse, level bars); no demo sentences | prototype `#s-talk .mic-card`, `listen()` | ✓ |
| S2 | Phone recognizer, on-device first (retry without it when it lacks the language); `ar-EG` → any Arabic; phone English → `en-US` → any English; language from the spoken-language setting | Q-T3, C14 | ✓ |
| S3 | `SpeechToSign` exact match, longest phrase first, only the Q-T5 aliases | sign rule 7 | ✓ (EN, AR, aliases, gendered forms, removed aliases and near-misses tested) |
| S4 | Segments played in order, each awaiting `signEnded` (length + 1.5 s); no sign → ready pose; interrupted → stop; never blocking | DECISIONS 2026-10-09; Q10 | ✓ |
| S5 | Avatar card: Ready / Signing pill, Replay, speed 1x → 0.5x → 1.5x, caption word by word | prototype `#avatar`, `avSign()`; S7-3 | ✓ |
| S6 | Feed "them" bubble "Signed by Nour" after signing | prototype `avatarSay()` | ✓ |
| S7 | Face to face: card turned 180° (0.6 s), "For the hearing person", "Waiting for signs…" + "Tap the mic to reply", toasts | prototype `.f2f` | ✓ (the live words in the card come with 7b) |
| S8 | Missing states: mic refused (D4 Allow) / for good (D5 Open settings, cleared on resume), no recognizer (D6), language missing (D7 / D8), nothing heard (D9), other error | Phase 0 row 7 | ✓ |
| S9 | Q-T3 privacy line (D19), once, until OK | Q-T3; S7-8 | ✓ |
| T1 | "I speak" opens face to face | Q-D4; S7-2 | ✓ ("I sign" focus on the live box: 7b) |
| T2 | Feed on the phone behind `ConversationRepository` (versioned, export / clear for step 10) | Q-B4; S7-1 | ✓ |
| T3 | EN / AR, RTL, light / dark, TalkBack labels, reduced motion | prototype CSS; review protocol | ✓ (48 dp: see Open) |

**Built:** `lib/core/speech/` (`SpeechToText` + `PlatformSpeechToText` on `speech_to_text` 7.5.0, `MicPermissions`), `lib/core/avatar/sign_sequencer.dart`, `sign_speed.dart`, `lib/core/conversation/` (repository + providers), `lib/core/ui/dashed_box.dart`, `IconCircleButton` toggle state, `features/talk/` (controller, screen, mic card, avatar overlay, feed). Android `RECORD_AUDIO` + `RecognitionService` query; iOS microphone / speech usage texts (DRAFT D20 / D21). 20 draft keys (`STEP7_DRAFTS`); `qSaySos` excluded (S7-7). New package: `speech_to_text` 7.5.0 (+ `_platform_interface` 2.5.0, `_windows` 1.0.1), all BSD-3, no network code in their sources (the phone's recognizer may use the network: Q-T3 line).

**Tests:** 82 new: speech 21 (through the plugin's real method channel: locales, on-device fallback, late `done`, watchdog, errors), sequencer 9, conversation 7, Talk controller 27, Talk screen 18 (incl. labelled tap targets). Two `/code-review` findings fixed, each with a test that fails without the fix (mutation-checked): a stale avatar controller after the runtime rebuilds; the on-device fallback ended as "nothing heard". Line-by-line review fixed: feed keys by position (identical messages), errors while signing logged and shown.

**Results (MacBook, Apple Silicon):** `flutter analyze` 0 issues; `dart format` 0 changed; `CI=true flutter test --coverage`: 545 passed, 1 skipped, 27 failed: the same 27 Linux-made CI goldens off by 1-83 px on a Mac (2026-10-11 entry); every non-golden test passes. Expected on Linux CI: 572 passed, 1 skipped. Coverage `lib/core` 94.0 %.

**Screenshots:** `tools/out/step7/compare/talk_idle_*.png` (prototype | app, EN / AR × light / dark), app renders of the signing, face-to-face listening and mic-blocked states. Differences: the glove chip and the user's zone (live box, Speak / Type / Clear, quick phrases) are 7b; "Today" without a place (S7-12); in the golden harness the avatar card is ~10 px taller (CSS `27vh` uses the screen height, the harness's size differs; on the phone it is the real height).

**Not committed:** `test/goldens/talk_golden_test.dart` and its images. Its CI images were rendered on a Mac, and CI goldens come from Linux (2026-10-11); asked the user how to make them.

**Open:** the Talk goldens (above); trying it on the phone.

**After the user's answers (2026-10-12):** D1-D23 approved as written (S7-14); tap targets keep the prototype sizes (S7-15). Talk goldens: a manual workflow (`.github/workflows/goldens.yml`) renders them on Linux and uploads them; the images are committed by hand after review.

**CI after the 7a push (run 38267215903, `ba28b2c`):** Flutter app ✓ 572 passed, 1 skipped, `lib/core` 94.0 %; AI ✓; Firmware ✓; **Android build ✗** `java.io.IOException: No space left on device` while copying `app-debug.apk` to `flutter-apk/` (the APK itself built; the previous green run on the same runner image installed the same NDK r28c and CMake). Fix: the Android job frees runner disk first and logs `df -h` (DECISIONS 2026-10-12). Verified: run 38270378947 (`d9e1ee4`, the fix) all 4 jobs green: Flutter app 572 passed, 1 skipped, `lib/core` 94.0 %; Android build ✓. Disk: 13 GB free at the start (60 / 72 GB used), 27 GB after freeing, 15 GB left after the build, so the build needs about 13 GB: before the fix it had at most 13 GB.

**Phone test 1 (user, 2026-10-12, Samsung, Google Voice Typing, EN-US + AR-EG offline):** every word ended with "Didn't catch that". Logcat: the on-device recognizer (SODA) returned the word (`#handleFinalResult: 1 hyp`, twice), kept listening, then ended the session with no final result (`Result lattice is not set`); the app got `done` and logged `listen_failed noSpeech`. Cause: `speech_to_text` types those phrases as `intermediate`, and only a final result counted. Fix (DECISIONS 2026-10-12): finished phrases are the sentence when the session ends without a final; debug-only recognizer log. 7 new tests replay the phone's sequence (3 fail without the fix, mutation-checked). Mac: 552 passed, 1 skipped, the 27 known Mac golden failures; expected on Linux CI 579 passed, 1 skipped; `lib/core` 94.0 %.

**Phone test 2 (user, 2026-10-12):** "hello", "thank you" work; "yes", "you", "one"…"help" show nothing. Log: for those words the on-device recognizer returned one empty result and no partial at all (`#onResults empty final recognition results`, `withSpeech: false`; the app's `words: 1` was my log counting an empty text, fixed). Also found: the locale went to Android as `en_GB` (not BCP-47) and was ignored ("Using Locale.getDefault()"), harmless for English on this phone, wrong for Arabic. Fixed: BCP-47 locale; last partial at the end of a session (user rule); digits 1-5 / ١-٥ (user approved); `1.5`, `3:30` never split into number signs (found by the new test); debug-only `STT_ON_DEVICE=false` to compare recognizers. Tests: the exact log sequence (still "nothing heard": the recognizer returned no text), last partial, empty phrase after a partial, BCP-47 tag, digits, punctuation / capitals; 5 fail with the old code (mutation-checked). Mac: 557 passed, 1 skipped, the 27 known Mac golden failures; expected on Linux CI 584 passed, 1 skipped; `lib/core` 94.0 %.

**Phone test 3 (user, 2026-10-12, `862b203`):** A (on-device): only "help" signs; B (`STT_ON_DEVICE=false`): nothing; no `stt_` line in the output (the lines use `debugPrint` and reached logcat in test 2, so no listen started). Found in the plugin's Android code: (1) the locale list never answers when the on-device support check fails, and each tap asked again: the mic could stay in "preparing" forever: fixed (time limits, the locale kept per language, a "try again" notice; tests: the phone never answering → busy within the limit, then works; asked once per language; asked again after "language missing"; the controller isn't stuck; the cache test fails without the fix). (2) Not changed yet, needs the phone's log: the plugin caches its recognizer intent without the on-device flag in the key, so since `862b203` (`en-GB` equal to the phone default) English listens reuse an intent built without the on-device flag or a language; before, `en_GB` forced a rebuild. Mac: 561 passed, 1 skipped, the 27 known Mac golden failures; expected on Linux CI 588 passed, 1 skipped; `lib/core` 94.0 %. CI for `862b203`: green (584 passed, 1 skipped).

**Phone test 4 (user, 2026-10-12):** very short words said alone come back empty from the phone's recognizer; in a sentence they work. Added D24 under D9 (draft, `tools/out/step7/drafts.html`); homophone list tested (`know`, `eye`, `ewe` added). Biasing: `speech_to_text` 7.5.0 ignores `contextualPhrases` on Android and iOS (only its Dart interface has it); options for the user. Mac: 562 passed, 1 skipped, the 27 known Mac golden failures; the architecture test caught a model label in a comment (fixed).

## Step 7b: Talk, glove → text and the rest of Talk (2026-10-13)

Answers: S7-16…S7-25 (DECISIONS). Checklist, each traced to its source:

| # | Requirement | Source | Status |
|---|---|---|---|
| 1 | Real `RecognitionService` events only; labels from `labels.txt`, words from `signs.json` | CLAUDE.md; AI-SPEC §5 | ✓ (`RecognitionFeed`; unknown labels ignored) |
| 2 | word: shown + spoken; tentative: faded "…", not spoken; confirm: normal + spoken; cancel: fades out | AI-SPEC §5, §7; sign rule 6 | ✓ |
| 3 | Tap a tentative word: confirm + speak, logged as a user confirmation; later cancel keeps it, later confirm not spoken again | Q-T1; S7-9 | ✓ |
| 4 | Conversation end (`active_s` after the last spoken word) and Clear: confirmed words → feed as "me"; tentative dropped; Speak repeats (disabled when empty, "Speaking…"); Type adds words spoken when sent | Q-T2; S7-20, S7-21, S7-22 | ✓ |
| 5 | Quick phrases: the sentence first, then the phrase spoken and added; SOS speaks D23 and shows D2 | S7-18; Q-T4; S7-7 | ✓ |
| 6 | Words shown and spoken in the voice language; voice `ar-EG` / any Arabic, phone English / `en-US`; no voice → shown, not spoken (D16) | S7-17, S7-23, S7-11 | ✓ (`flutter_tts` 4.2.5, MIT) |
| 7 | Glove chip: real `#BAT` %, LOW (amber, D12), USB (no %), Reconnecting (D11), not connected (D10); tap → Settings / Pair | Q-K2; S7-4 | ✓ |
| 8 | Missing glove states in the live box: no glove (D13 + Connect), no calibration (D14 + Calibrate now), recognizer stopped (D15) | Phase 0 row 7; Q-K6 | ✓ |
| 9 | One background reconnect after a drop (permission already granted, no prompt) | S7-19 | ✓ |
| 10 | Conversation on the phone (ConversationRepository) | Q-B4; S7-1 | ✓ (from 7a; "me" messages now) |
| 11 | Screen on only while Talk is visible and in the foreground | S7-5 | ✓ (own channel, no package) |
| 12 | Developer panel: debug / profile + mock only; person A / B; every mock file through the real pipeline | S7-24 | ✓ |
| 13 | "I sign": the live box first for screen readers; face-to-face card shows the user's words | S7-2; prototype `.mic-signs` | ✓ |
| 14 | Goldens override every async provider; CI images rendered on Linux | DECISIONS 2026-10-11 | test updated (7 states); images from the goldens workflow, pending |

**Built:** `lib/core/speech/text_to_speech.dart`, `lib/core/device/keep_screen_on.dart` (+ `MainActivity`, `AppDelegate`), `RecognitionFeed` + `recognitionFeedProvider` + `conversationTimeoutProvider`, `reconnectToPairedGlove` (shared with start-up), `lib/core/glove/mock/mock_controls.dart`; `features/talk`: `TalkGlove` controller, `MeZone` (live box, type box, Speak / Type / Clear, quick phrases), `GloveChip`, `MockPanelButton`; the screen's layout (the avatar yields height). Android `TTS_SERVICE` query. Texts: D16's language names (approved with D16); D25 "Add" / «ضيف» (draft).

**Tests:** Talk 90 (controller 25, glove screen 20, plus 7a's), navigation tests with the Talk fakes; integration test `integration_test/talk_test.dart` (mock glove plays A/hello.csv through the real pipeline; not run here: no emulator on this Mac). `/code-review` found 5 bugs, all fixed with tests: glove → text stopped after the recognizer was rebuilt; words were spoken with no voice for the language; the reconnect after a drop was missed when the glove was connected before Talk started (the realistic test then found a crash: a state change inside build); a faded word could be left behind when Talk was hidden; leaving Talk didn't stop glove → text. Mutation-checked: 4 of 5 fail without their fix; the dispose one is also covered by the visibility path (a second safety net, not separately testable). The architecture tests caught the panel reaching the mock glove directly and a label in a comment.

**Results (Mac):** analyze 0 issues; format 0 changed; `CI=true flutter test --coverage`: 604 passed, 1 skipped, 35 failed = the 27 known Mac goldens + the 7 Talk goldens (new images pending from Linux) + one navigation test (a pending timer from the real recognizer: fixed by giving it the Talk fakes; then `app_navigation_test.dart` 15/15 passed); `lib/core` 93.5 %.

**Open:** D25 approval; the Talk golden images (workflow, then the user's OK); the emulator / phone run of the integration test; recognizer biasing (a / b / c).

**Recognizer biasing (S7-27, option a), 2026-10-13:** `app/third_party/speech_to_text/` = speech_to_text 7.5.0 (BSD-3) with an Android patch (`ISHARA.md`, `ISHARA.patch`, every change marked `// Ishara:`): `contextualPhrases` → `EXTRA_BIASING_STRINGS` (Android 13+), and the intent cache now includes the on-device flag and the phrases (the upstream gap suspected after `862b203`). Used through `dependency_overrides`; outside `app/ishara_app`, so the app's format / analyze rules don't apply to upstream code. Talk passes every variant of the avatar's signs in the spoken language (biasing only: matching stays exact, sign rule 7). Tests: the channel gets `contextualPhrases` (no key when empty); EN / AR phrase sets. Not compiled here (no Android SDK): CI's Android job builds it. Whether it helps single short words is for the phone test (the recognizer returned no text for them).
**D25** approved (S7-26).

## Before step 8: fixes (2026-10-14, Linux laptop, emulator `ishara_api36`)

| # | Item | Status |
|---|---|---|
| 0.1 | `onboarding_test.dart` waited for the step-6 `skeleton-talk`: now waits for `talk-mic-card` and checks the glove chip ("Glove connected" + %, active source mock, device `Ishara-M0CK`, phase ready) | ✓ emulator: both tests pass (Talk at 19.9 s) |
| 0.1 | Found by that run: `TalkGlove._start` wrote state after Talk was disposed (`UnmountedRefException` after the first test, so the guest test never ran). Fixed (`ref.mounted`), unit test fails without the fix | ✓ |
| 0.1 | CLAUDE.md review protocol: every step ends with all of `integration_test/` on an emulator or phone, results here | ✓ (rule 4) |
| 0.1 | README troubleshooting: Kotlin "Conflicting overloads" in `SpeechToTextPlugin.kt` → delete `build/speech_to_text` | ✓ |
| 0.2 | TURN drawing capped at ±33°, number shows the real angle | ✓ widget test (20° → 20°, ±42° → ±33°, label ±42°) |
| 0.2 | Live roll vs turn.csv (±42°) | ✗ before: rest.csv (≈ −93°) before TURN pulled the first second of the sweep down (−50° … +20° on the emulator). Cause and fix: DECISIONS 2026-10-14. ✓ after: unit test (persons A, B; 0 / 37 / 100 / 411 rest samples before TURN) min −41.8°, max +41.1° … +41.3°, within ±3°; 6 of 8 fail without the fix. `mock_calibration_test` (real mock glove, controller, screen) now checks −42° / +42° ± 3° on every sample batch; both persons fail without the fix |

Tests: analyze 0 issues, format 0 changed; talk + calibration + glove + architecture: 216 passed.

## Step 8: Learn (2026-10-14 → 15, Linux laptop, emulator `ishara_api36`)

Your answers: S8-1 … S8-4 (DECISIONS). Static screens `08-learn` / `08b`: a category list with per-finger % (Q-L3), not the prototype's structure, so not used (Q-D1).

| # | Requirement | Source | Status |
|---|---|---|---|
| 1 | Real stats only: XP, streak, medals, signs learned, from the log | prompt; Q-L2 | ✓ `LearnProgress.compute` |
| 2 | 5 modules of Q-L1 in order, progress = signs passed / signs | Q-L1; S8-3 | ✓ `signs.json` `learn.modules`; progress counts practice or quiz |
| 3 | Locking + the prototype's locked text and toast | Q-L2; S8-3; `renderLearn` | ✓ |
| 4 | Daily challenge: 5 signs from unlocked modules, +30 once per local day, date seed, no practice for glove: false | Q-L2; S8-4 | ✓ pool = modules unlocked when the day began |
| 5 | Guest banner | prototype `#guestBanner` | ✓ live from the account |
| 6 | Watch and pick: user speed, looped; 4 distinct tiles, seeded; right +10; wrong: right tile marked, replay 0.5× | prompt; `renderMissionStep` | ✓ |
| 7 | Your turn (glove: true only): cuePractice + 8 s, 3 attempts, exact label word/confirm, match % = Q-L4, +15; another sign: neutral text | sign rules 3, 4; Q-L2, Q-L4; DECISIONS 2026-10-09 | ✓ `PracticeCheck` |
| 8 | Watch-only module: quiz steps only | Q-L1 | ✓ |
| 9 | Result: XP, accuracy, time, medal ≥ 80 %, Back to Learn, no Share | Q-L2, Q-L6 | ✓ |
| 10 | Glove states during practice (no glove, no calibration, link lost, #MPU FAIL) + skip | S8-1 | ✓ (also "recognizer stopped", D15) |
| 11 | Append-only, versioned, exportable activity log, Phase 0 fields; totals never stored | prompt; PHASE0 §5 | ✓ `LocalActivityRepository` (nothing ever dropped) |
| 12 | Domain in `lib/features/learn/domain/`, pure Dart, ≥ 90 % | prompt; CI gate | ✓ 100 % (259/259) |
| 13 | Edge cases: midnight, missed day, two missions a day, clock / timezone change, Egypt DST, daily on an unlock day, zero practice steps | prompt | ✓ (DST also on the real tz database: `TZ=Africa/Cairo`, a CI step) |
| 14 | Shared WebView avatar: play, loop, replay, speed; only avatar: true signs | prompt | ✓ |
| 15 | Exactly one consumer of recognition events (Talk vs Learn) | DECISIONS 2026-10-13 | ✓ test (fails without Talk's gate) |
| 16 | Texts: prototype + changes, drafts EN + AR | prompt; Q-L3 | ✓ 20 drafts, `tools/out/step8/drafts.html` |

**Built:** `lib/features/learn/` (domain 8 files, data `activity_repository.dart`, application `learn_providers`, `mission_controller`, `practice_hand`, presentation `learn_screen`, `mission_screen`, `mission_widgets`, `learn_modules_ui`), `lib/core/device/device_id.dart`, `lib/core/avatar/avatar_card_parts.dart`, `lib/core/ui/blink.dart`, `lib/core/ui/hand_drawing.dart` (moved), `signs.json` modules + icons, `library.json` `celebrate`, single-flight reconnect, `tools/step8_compare.py`, `tools/step8_drafts.py`, CI Cairo step.

**Tests (Linux laptop):** analyze 0 issues (`--fatal-infos`); format 0 changed; `flutter test --coverage`: **819 passed, 4 skipped** (the Cairo tests outside Cairo), **6 failed** = the 3 TURN Calibrate goldens × 2 variants changed by fix 0.2 (new images in `tools/out/step8/goldens_review/`, waiting for your OK); `TZ=Africa/Cairo` egypt test 3/3; coverage `lib/core` 93.2 %, `lib/features/*/domain` 100 %. New: domain 46 (+3 Cairo), controller 31, pipeline 4 (real mock glove + recognizer, persons A/B + mutation), Learn screen 10, mission screen 9, Talk/Learn one reader 1, repository + device id 6, catalogue 3, caption box 1, reconnect 1. Mutation-checked: pass on another label, pass on a tentative, Talk's visibility gate, avatar stop, daily day, replay on show, result reframe.

**Integration (emulator `ishara_api36`):** onboarding_test ✓ 2/2; talk_test ✓ 1/1; avatar_test ✓ 1/1 (53.7–56.5 fps); learn_test ✓ 3/3: persons A and B, a whole "Start here": every practice step passed on the first try through the real pipeline (99–100 % match), the deliberate wrong pick replays exactly 2.0× longer (0.5×), +115 XP, 90 %, medal, Numbers unlocked; mutation (please → thanks.csv): please fails after 3 tries, the rest pass.

**Screens:** comparison sheets `tools/out/step8/compare/` (learn, quiz, quiz_wrong, practice_idle, practice_counting, practice_passed, practice_failed, result; prototype | app, EN / AR × light / dark). Differences: real numbers instead of demo ones; 5 Q-L1 modules; pill "Signing" during practice (prototype "Ready" while signing); match ring = arc of the real %, readable % in light; no fake per-finger % or tips (Q-L3); no Share medal (Q-L6); no medal circle under 80 % (+ L17); result lead true to what happened (L14/L15); quiz tiles ~6 px lower. Fixed from the comparison: medal gradient size, result spacing, tile overflow, unreadable match % in light.
**Video:** `tools/out/step8/device/learn_mission.mp4` (person A, paced, 54 s mission + Learn after), 13 frames checked (`frames_sheet.png`): signs played match the steps, live bars move, countdown, feedback, result, Learn updated.

**Review:** line-by-line + `/code-review` (10 findings, 9 fixed with tests, 1 = commit hygiene): replay after hidden / background; stale "Reconnecting…"; caption height from another screen; guest flag loop with a Firebase-style stream; 10 rebuilds/s while counting (fill animated on screen, state once a second); daily across midnight credited to the wrong day; "today" stale across midnight (timer); second damaged log overwrote the first backup; `Feedback` name clash. Found by tests on the way: provider changes during build (Learn, mission); a mission's sign kept looping into Talk.

**Not committed (waiting for you):** `test/goldens/learn_golden_test.dart` + its images (rendered on this Linux laptop; existing CI goldens match the runner's here, but you asked for the runner's workflow, which needs a push); the 6 TURN Calibrate images. Untracked and left alone: `design/*.stl`, `app/ishara_app/run.txt`, `stt.txt`.

**Open questions**
1. Approve drafts L1-L20, the 4 module looks and the 12 neutral tile icons (`drafts.html`).
2. Goldens: render on the runner (push a branch for the workflow) or accept the laptop renders? Also approve the TURN Calibrate before / after.
3. Streak: today counts up to yesterday until midnight (DECISIONS) — OK? The chip says "1 days" (prototype has only "days" / «يوم»): a singular text?
4. Connect / Calibrate now from a practice step end on Ready (`go`), leaving the mission (Talk does the same). Return to the mission instead?
5. Practice loops at 0.8× (prototype), not the user's speed — keep?

### Step 8 review answers (2026-10-15): S8-5 … S8-9

| # | Answer | Status |
|---|---|---|
| 1 | L1-L16, L18-L20 approved; L17 AR «اوصل لدقة {p}% …»; looks and tile icons approved | ✓ ARB descriptions "approved new text (step 8, 2026-10-15)" |
| 2 | TURN Calibrate "after" images committed; Learn goldens from the runner (branch `step8`) | ✓ calibrate (both variants); Learn: see below |
| 3 | Streak up to yesterday kept; ICU plural chip | ✓ `streakDays` (L21, **draft**, `drafts.html`): EN 0/1/2/5, AR 1/2/3/10/11/25/100 tested; AR 0 uses the 11+ form (not in your list) |
| 4 | Connect / Calibrate now → back to the same practice step, attempts reset; Talk unchanged | ✓ `?back=N` on Pair / Calibrate; widget tests (4: Connect, a used attempt reset, Calibrate now, Pair → Calibrate), 2 of them fail with the old `go(ready)`, 1 without the reset; learn_test: disconnect during practice → Connect → Pair → back on the step (A and B) |
| 5 | Practice at min(0.8×, user speed) | ✓ test (1x → 0.8, 0.5x → 0.5, 1.5x → 0.8) |

**Checks (Linux laptop):** analyze 0 issues, format 0 changed; `flutter test --coverage`: 823 passed, 4 skipped, 8 failed = the Learn goldens' local laptop images (stale chip text, never committed; replaced by the runner's); Cairo 3/3; `lib/core` 93.3 %, domain 100 %. Emulator: onboarding 2/2, talk 1/1, avatar 1/1 (59.8-60 fps), learn 3/3 (with the disconnect → reconnect).
**Learn goldens:** rendered by the goldens workflow on the runner, run 38727389574 on `step8` (`fbdbb26`), 15 tests × both variants; the runner's 30 images committed (none from the laptop); they also pass locally on Linux (both variants).
**L21 (2026-10-15):** approved with AR 0 = «0 يوم» (S8-10); ARB description and `drafts.html` updated; test covers AR 0.
