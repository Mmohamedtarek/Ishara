# Decisions

User decisions use the IDs from `PHASE0-REPORT.md` §7 (answered 2026-10-08, after kit v3.2.1, commit `1bbd09d`). "Draft" means: show the text or screenshots to the user before it ships.

## Release blockers
| ID | Blocker |
|---|---|
| **RB-1** (Q-A1) | The Nour / Sara avatar models are "sample models, for non-commercial use". Fine for development and the graduation demo. **They must be replaced before any store release.** Avatar files stay swappable: the character list is data, and nothing in the code depends on the model files. |

## Machine and workflow
| ID | Decision |
|---|---|
| Q-M1 | Toolchain installed (Flutter 3.47.6 / Dart 3.13.5, Android SDK 36, build-tools 36.0.0, JDK 21, Node 22.23.3, firebase-tools 15.33.0, flutterfire_cli 1.4.1). Emulator `ishara_api36` is for development and for integration tests on the mock. The user's Android phone over USB is for anything BLE. CI runs everything that needs no device. Keep build outputs and caches lean (disk is tight). |

## Design
| ID | Decision |
|---|---|
| Q-D1 | The prototype wins on everything. Static screens are an older design: use them only as a pixel reference where they show the same screen with the same structure. Out of v1: hair / hijab / colour options, the SOS location sender, "Speak after a pause", "Simulate glove sign", "Work offline", male / female voice choice, Reconnect / Update. |
| Q-D2 | New screens and states are built from the prototype's own components. Screenshots and the full list of new EN + AR texts (Egyptian colloquial Arabic) go to the user for approval (draft). |
| Q-D3 | Theme follows the system; light is the fallback. |
| Q-D4 | Setup "I speak" opens Talk in face-to-face mode with the mic card first. "I sign" opens Talk with the glove text first. |

## Talk
| ID | Decision |
|---|---|
| Q-T1 | Remove the unsure-word chip, the "Did you mean" alternatives and the 75 % switch; use AI-SPEC tentative / confirm / cancel. **Tapping a tentative word confirms it and speaks it**, and it is logged as a user confirmation (not a Decider event). |
| Q-T2 | Each `word` / `confirm` is spoken when it arrives. When the conversation ends (`active_s` with no new confirmed word) or the user taps Clear, the live sentence moves to the feed as a "me" message. "Speak" repeats the current sentence aloud. "Type" adds typed words, spoken when sent. |
| Q-T3 | Speech to text uses the platform recognizer, preferring on-device when the phone supports it. Privacy states clearly that speech to text may use Google / Apple servers for the other person's voice. |
| Q-T4 | v1 SOS only speaks the SOS phrase aloud. "Emergency contact" is hidden. No SMS, no location. |
| Q-T5 | Arabic spoken text for all 20 labels: drafted in `signs.json` for approval. Aliases: keep `hi`, `hey` → hello; `i` → me; `thank` → thanks; `doctors` → doctor. Add the full phrases `السلام عليكم` → hello and `من فضلك` → please. Remove every other alias listed in report item 8. |

## Learn
| ID | Decision |
|---|---|
| Q-L1 | 5 modules: Start here (hello, thanks, please, yes, no); Numbers (one–five); People (me, you, iloveyou, come, call); Needs (water, drink, hungry, sorry, bye); Watch only (coffee, doctor, home, family, help: pick-the-meaning steps only). Modules with unapproved animations stay locked. |
| Q-L2 | XP: quiz +10, practice +15. Medal when a mission ends at ≥ 80 % accuracy. Streak = consecutive local days with at least one finished mission. "Signs learned" = passed at least once in practice (or in a quiz for watch-only signs). Unlock = finish the module above. Daily challenge = 5 random signs from unlocked modules, +30 XP, once a day. Practice: 8 s after "Sign now", 3 attempts. |
| Q-L3 | Drop the random per-finger tips. |
| Q-L4 | Match % = the smoothed average probability of the target label at the step where its `word` / `confirm` fired. |
| Q-L5 | Never fake anything. On the mock source, the practice check plays `mock/A/practice/<label>.csv` (or `B`) through the real pipeline; each confirms its sign exactly once. The old isolated files stay as they are. |
| Q-L6 | No "Share medal" in v1. |

## Glove and calibration
| ID | Decision |
|---|---|
| Q-K1 | BLE gap rule = AI-SPEC v3.2.1 §4 exactly (test: `test_vectors.json` → `gaps`). 1–5 missing: repeat the last accepted sample, the repeats count. More than 5 (and < 32768): emit `cancel` for a pending tentative word, then reset the window, the counter and the Decider, then push the sample. Duplicate or older (`gap ≥ 32768`): drop. `seq` is mod 65536. |
| Q-K2 | Pair copy (draft), only true facts: switch the glove on and keep it near the phone; it shows as `Ishara-XXXX`; show real RSSI, battery after connecting, `fw` from INFO. No button, no light colours. |
| Q-K3 | Pairing checks: (1) connect + MTU 247 + services; (2) INFO `proto == 1` + subscribe to EVENT (+ `#BAT`, no `#MPU FAIL`); (3) `GETCAL`. Check 2 is renamed "Checking the sensors". |
| Q-K4 | TURN lasts 3 s; the text says 3 seconds. |
| Q-K5 | Remove "96 % accuracy". |
| Q-K6 | Skip calibration is allowed only when the glove has a stored `#CAL {…}`. With `#CAL NONE`, Skip is hidden and the screen explains why. |
| Q-K7 | Finger bars are hidden until both OPEN and FIST are done. During OPEN / FIST a "hold still" indicator driven by the gyro is shown. |

## Avatar
| ID | Decision |
|---|---|
| Q-A1 | See RB-1. |
| Q-A2 | Avatar studio v1 = avatar picker + speed. `AvatarController.customize()` still exists. |
| Q-A3 | PLEASE keeps the B hand. SORRY keeps the A hand. I LOVE YOU is held still (remove the forward push). Vocabulary v2.1 (same PDF) now says the same. |
| Q-A4 | Rename the engine sign `love` → `iloveyou`. |
| Q-A5 | Remove the wrong-sign aliases (`my`, `your`, `house`, `sure`, `ok`, `okay`, `yeah`, `nope`, `أكيد`, `اكيد`, `السلام` alone, `فضلك` alone, `من`). The aliases kept in Q-T5 stay. |
| Q-A6 | Add finger spread to the engine as data plus a few lines in `curlHand`. Show FIVE vs FOUR and TWO vs NO in the preview screen. |
| Q-A7 | The user sends references for the 10 new signs before step 5. Steps 2–4 don't wait for them. |

## Step 4 approvals (2026-10-09)
| ID | Decision |
|---|---|
| S4-1 | `signs.json` drafts approved: all Arabic spoken words, all extra variants (goodbye, phone, لو سمحت, آسفة, تليفون, باي, …) and the categories of the 5 avatar-only signs. No field is marked `draft` any more. |
| S4-2 | Inside Arabic sentences the app name is always "إشارة". ArSL dialog (AR): "لغة الإشارة المصرية هتكون متاحة في تحديث قريب. حاليًا إشارة بيستخدم لغة الإشارة الأمريكية (ASL)." |
| S4-3 | Gendered Arabic words (آسف/آسفة, جعان/جعانة, إنت/إنتي): the voice speaks the masculine form for now; both forms match for speech → sign. **Future:** a profile setting for the signer's gender picks the spoken form. |
| S4-4 | iOS `NSBluetoothAlwaysUsageDescription` approved: "Ishara uses Bluetooth to connect to your Ishara glove and read your signs." (Arabic version still needs Xcode on a Mac.) |
| S4-5 | The "Coming soon" badge design (amber `.xp`-style chip) approved. |

## Vocabulary v2.2 (2026-10-09)
| ID | Decision |
|---|---|
| V-1 | `docs/ASL-REFERENCES.md` (user, commit `331fbfa`) holds one Lifeprint reference per sign; avatar animations follow it together with the vocabulary PDF. |
| V-2 | COME = index forward, palm up, **one quick arc toward you** (not a repeated beckon). |
| V-3 | WATER = W hand, the index fingertip taps the **mouth** twice (not the chin). The avatar's existing WATER is changed. |
| V-4 | The AI team retrains for v2.2 and delivers kit v3.2.2 (new models, same labels and spec, plus the §8 doc fix). The kit isn't edited here; sync only when the user says so. Until then the repo PDF still reads v2.1 for COME / WATER; V-2 and V-3 win. |

## Step 5 review answers (2026-10-09)
| ID | Decision |
|---|---|
| S5-1 | CALL: option (b), keyframes may set the elbow direction. HOME uses it too. Correct signs matter more than "port, not rewrite". |
| S5-2 | Contact depth: fix the body measurement. WATER (mouth), ME (chest), THANK YOU (chin), PLEASE / SORRY / HUNGRY (chest) must touch. Guard: the 71-frame comparison may differ only where a contact now touches or an elbow is set; before / after for every changed sign. |
| S5-3 | New signs stay `avatar: false` until the user approves them after these fixes and a new recording. Phone FPS later. INTERNET permission OK while cleartext stays limited to 127.0.0.1. |
| S5-4 | App logo, launcher icons and native splash exactly as the prototype mark; adaptive + monochrome Android icon from one vector source kept in the repo; Android 12+ splash API; no white flash, no Flutter logo, no light flash in dark mode; iOS AppIcon + LaunchScreen from the same source; golden + "not Flutter's icon" test. |
| S5-5 | The sign preview always shows the sign that is playing, whoever started it (screen recordings are reviewed). |

## Step 5 review, round 2 (2026-10-10)
| ID | Decision |
|---|---|
| S5-6 | Splash keeps the prototype layout (whole group centred). The mark moves from the native-splash centre to its place in the group (300 ms, prototype easing); with reduced motion it doesn't move. |
| S5-7 | CALL: the hand beside the head (thumb at the ear, pinky toward the jaw / mouth corner, eye uncovered), elbow down and slightly out, below the shoulder. HOME: flat-O at the mouth corner, then the cheekbone, elbow low. Sara's hair clipping in CALL: no per-character hand adjustment in the engine → known issue, not blocking. |
| S5-8 | HELP, COFFEE, DOCTOR, FAMILY references added (docs/ASL-REFERENCES.md); check and report. New signs stay `avatar: false`. |

## Backend
| ID | Decision |
|---|---|
| Q-B1 | Free Spark plan, **no Cloud Functions**. Account deletion: re-authenticate if Firebase requires it, the client deletes its own data, then the Auth user. Interruption-safe: a local "deletion pending" flag, retried on next launch. Code stays ready to move to a callable function. |
| Q-B2 | Email + password only. No Google, no phone number, no "Remember me". |
| Q-B3 | Unverified accounts can use the app; sync starts after the email is verified. |
| Q-B4 | History (signed and heard sentences) stays on the phone only. Starring makes it a saved phrase, which syncs. Titles come from date and time. |
| Q-B5 | Settings has a sign-language row using the same two pills as Setup, with the "Coming soon" badge on ArSL. |

## Source issues (report §6)
| ID | Resolution |
|---|---|
| C6 | Expect an exact match on every mock file in `expected.json` (now 88). If one differs, stop and ask. |
| C7 | AI-SPEC "rounded" = Python round-half-to-even, with a test. |
| C8 | Ignore `confirm_on_rest` and the top-level level defaults in `live.py`; not part of the spec. |
| C10, C11 | Fixed in kit v3.2.1. |
| C12 | Fixed in vocabulary v2.1 (Please = flat B, Sorry = A fist, I love you held still). |
| C14 | See Q-T3. |

## Technical decisions (mine)
| Date | Decision | Reason |
|---|---|---|
| 2026-10-08 | Read the prototype through `app/tools/strip_prototype.py` (outputs git-ignored in `app/tools/out/`) | The 12 MB file is mostly base64 GLBs; the script can be re-run and never touches `design/`. |
| 2026-10-08 | `docs/BLE-CONTRACT.md` is the BLE source; the kit copy is identical | The user's prompt names `docs/`. |
| 2026-10-08 | Avatar: `webview_flutter` + loopback HTTP server (planned for step 5) | First-party and maintained; ES modules don't load from `file://`. |
| 2026-10-08 | Fonts are bundled as static TTFs cut from the google/fonts variable fonts (`tools/make_fonts.sh`), only the weights the prototype loads. Bricolage Grotesque is pinned at opsz 24 / wdth 100. | Works offline; Flutter matches static weights reliably. CSS picks opsz from the font size, Flutter can't; 24 is the middle of the title sizes (17–42 px). |
| 2026-10-08 | ARB files are generated from the prototype (`tools/extract_strings.py`). Avatar name → `{name}`; feminine Arabic → `{gender, select, female{…} other{…}}`; keys that are Dart keywords get a `Label` suffix (`continueLabel`). Strings removed or made untrue by decisions are excluded with a reason; changed and new texts are drafts for approval. | One source of truth for the copy; regenerating can't silently bring back removed strings. |
| 2026-10-08 | Prototype icons are ported as SVG strings (`tools/extract_icons.py`) and drawn with `flutter_svg` 2.3.0; `arrow`, `back` and `chev` flip in RTL. | Identical icons to the prototype (no icon-font substitutes). |
| 2026-10-08 | Generated code (`*.g.dart`, `*.freezed.dart`, `lib/l10n/gen/`) isn't committed; CI and developers run `gen-l10n` and `build_runner`. | Smaller diffs, no stale generated code. |
| 2026-10-08 | Constructors use Dart 3.13's `const new(...)` form. | `very_good_analysis` 11 enforces `unnecessary_type_name_in_constructor`; zero issues is required. |
| 2026-10-08 | Goldens use `alchemist`. CI goldens (text drawn as blocks) are checked in CI; platform goldens (real text) are generated locally and used for the screenshot review. | Font rasterising differs between machines; CI must not flake. |
| 2026-10-08 | Navigation: `go_router` with a `StatefulShellRoute` for the 4 tabs. Screen entrance = the prototype's slide (22 px, mirrored in RTL) or pop (Ready, Mission), 0.38 s, `cubic-bezier(.2,.8,.2,1)`; reduced motion turns it off. | Matches the prototype CSS. Known difference: on Back the leaving screen animates out, whereas the prototype hides it at once and slides the previous screen in. |
| 2026-10-08 | Tests read `design/prototype.html` (colour tokens) and `app/Ishara-Mobile-Kit/` (checksums) directly. | A change in either source makes a test fail instead of drifting silently. |
| 2026-10-08 | Prototype screenshots for UI review come from `tools/proto_shot.py` (Playwright 1.63 + system Chrome, venv in `app/tools/.venv`, git-ignored). | Headless Chrome alone doesn't run the prototype's layout script and splash reliably. |
| 2026-10-09 | Android applicationId / iOS bundle id = `io.github.mmohamedtarek.ishara`. App name "Ishara" everywhere (logo, launcher label in every language); "إشارة" only inside Arabic sentences, exactly as the prototype strings. | User decision (step 3 answers 2, 5). |
| 2026-10-09 | Back: the leaving screen disappears at once and the revealed screen replays its entrance (driven by the route's secondary animation); on push the covered screen disappears at once. A themed background sits behind the navigator. | User decision 4: match the prototype exactly. Accessibility kept: hidden screens are out of the semantics tree (opacity 0), the system back button pops the same way (tested). Not a predictive-back gesture page (Android 14+ animates nothing during the drag; the pop runs on release). |
| 2026-10-09 | TFLite runtime: `flutter_litert` 3.9.3, classic CPU `Interpreter`, 1 thread, no delegates. | Its bundled native libraries make the model tests run in `flutter test` on Linux and CI (tflite_flutter needs a hand-built .so); classic Interpreter because its README says CompiledModel "miscomputes some models". All kit vectors and 88/88 mock files match exactly. |
| 2026-10-09 | Pipeline numerics copy the Python reference: normalize in float64 then float32; ensemble mean in float32 with rounding after each add (checked against numpy 2.5.3); Decider in float64; argmax = first maximum. | Exact event steps (C6). |
| 2026-10-09 | Glove layer: one `GloveClient` (contract setup, command/reply matching, EVENT lines, DATA frames) over a small `GloveTransport`/`GloveLink`. The mock glove is a transport that simulates firmware 0.3.0 and always streams real 5-sample frames at 50 Hz, so mock data always goes through the same frame decoder and line parser. | One code path for mock and BLE; the prompt's "can also send BLE frames" is the only mode. |
| 2026-10-09 | `GloveLink` exposes notification streams before subscribing; the client listens first, then enables notifications. | `#BAT` is sent the moment EVENT is subscribed (BLE §6); a race lost it in the first test run. |
| 2026-10-09 | Command replies: timeout 1.5 s (contract: 500 ms) for margin; calibration steps 2 s / 3 s capture + 1.5 s; first `#BAT` waited for at most 2 s. Commands are sent one at a time, except `CAL CANCEL`, which goes at once so it can cancel a running step. | BLE §5, §7. |
| 2026-10-09 | Without `--dart-define=GLOVE`: mock in debug/profile, real glove in release. The developer switch overrides it. | A release build can never ship on mock by accident. |
| 2026-10-09 | Learn "Sign now" calls `GloveSource.cuePractice(label)`: no-op on the real glove, the mock plays `practice/<label>.csv`. Mock idle = the person's `rest.csv`, looped. Mock-only: changing person sends that person's `#CAL`. | Learn never knows which source is active (Q-L5). |
| 2026-10-09 | Pipeline value types are plain `@immutable` classes, not freezed. | They cross the isolate boundary and sit in the hot path; no copyWith needed. Freezed stays for state/domain models (e.g. AppSettings). |
| 2026-10-09 | ~~Open: BLE library.~~ **Resolved:** `flutter_reactive_ble` 5.6.0 (user decision). `flutter_blue_plus` is not used at all. | See the row below for the original problem. |
| 2026-10-09 | Was open: BLE library. `flutter_blue_plus` 2.x (named in the prompt) is no longer BSD: free only for personal / nonprofit / educational use, paid for any for-profit use (including development), and it may send build-time telemetry (package name, app name, version). Removed before any build; `PendingBleTransport` reports "Bluetooth unsupported" until the user decides. Alternatives: `flutter_reactive_ble` 5.6.0 (BSD-3), `universal_ble` 2.3.0 (BSD-3), `bluetooth_low_energy` 6.2.1 (MIT). | User decision needed. |
| 2026-10-09 | Note for the AI team: `build_kit.py` computes `expected.json` and the `gaps` vector with `Predictor.batch()`, which loads the **Keras** models; AI-SPEC v3.2.1 §8 says the `.tflite` files. Our `.tflite` pipeline matches every file exactly anyway. | Doc accuracy only. |
| 2026-10-09 | BLE radio = `flutter_reactive_ble` 5.6.0 behind a small `BleApi` interface (`ReactiveBleTransport`). Licence check: flutter_reactive_ble, reactive_ble_mobile, reactive_ble_platform_interface are BSD-3; native deps RxAndroidBle 1.16.0, RxKotlin, RxAndroid (Apache-2.0), protobuf-javalite and the Protobuf pod (BSD-3), SwiftProtobuf (Apache-2.0). Source scan of the 5.6.0 archives: no network code (`dart:io` only for `Platform` checks; URLs are comments or the SPM source of swift-protobuf). | User decision; "check its licence and that it sends no data anywhere". |
| 2026-10-09 | `compileSdk = 37` (targetSdk stays 36, minSdk unchanged), with `android.suppressUnsupportedCompileSdk=37`. | `reactive_ble_mobile` 5.6.0 requires apps to compile against API 37; AGP 9.1 only recommends ≤ 36 (warning, the build works). |
| 2026-10-09 | Android permissions: `BLUETOOTH_SCAN` (neverForLocation), `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION` only up to API 30; the `uses-permission-sdk-23` location entries merged in by RxAndroidBle are removed (`tools:node="remove"`). `bluetooth_le` feature not required. | The scan never derives location; no location prompt or Play location disclosure on Android 12+. Without BLE the app still offers speech → avatar and Learn. |
| 2026-10-09 | The BLE plugin object is created on first use only. | It talks to the platform as soon as it exists; mock mode and tests never need it. |
| 2026-10-09 | ~~Open: iOS `NSBluetoothAlwaysUsageDescription`~~ **Resolved:** approved (S4-4). | Every user-facing text is a draft for approval (Q-D2). Needed before any iOS run with the real glove. |
| 2026-10-09 | Language packs: everything of a sign language lives under `assets/packs/<lang>/`: `signs.json`, the kit (`kit/model`, `kit/mock`, `kit/test`, synced by `sync_kit.sh`) and later the avatar library. `PackRegistry` (ASL available, ArSL not); `activeSignLanguageProvider` + `activePackProvider` are the only way to a pack; `PackRegistry.require` throws for an unavailable pack. | Prompt: "recognizer models under assets/packs/<lang>/"; ArSL later = new data only. |
| 2026-10-09 | `signs.json` is the only word list. Variants are matched exactly after normalization (case, Arabic diacritics + tatweel, أ إ آ ٱ → ا, ؤ → و, ئ → ي, ة → ه, ى → ي; apostrophes removed so "I'm" never becomes "I"), longest phrase first. Loading refuses a catalogue where a normalized variant leads to two signs, or that disagrees with `labels.txt`. | Sign rule 7; prompt catalogue tests. |
| 2026-10-09 | Normalizer characters are written as code points. | A tool turned `\u` escapes into invisible combining characters during this step; code points can't be mangled and are reviewable. |
| 2026-10-09 | Catalogue content: the 20 glove-sign descriptions come from vocabulary v2.1; words/variants from the prototype minus Q-A5 removals plus Q-T5 additions; EN spoken from AI-SPEC §6. Everything else is marked `draft` in `signs.json` for approval (Arabic spoken text, words of the 10 new signs, a few variants, categories of the 5 avatar-only signs). `verified: false` = coffee, doctor, family, help (not in vocabulary v2). | Q-T5 (drafts), sign rule 5. |
| 2026-10-09 | Sign language picker: the prototype's pills in prototype order (ArSL, ASL), 48 dp high (prototype 44 px), ArSL with a "Coming soon" badge styled like the prototype's `.xp` chip (draft design); the dialog is a themed AlertDialog with the approved text. Approved new strings live in `extract_strings.py` `APPROVED_NEW`. | Prompt Sign language section; 48 dp rule. |
| 2026-10-09 | Avatar engine = the prototype's engine code copied into `assets/avatar/engine.js`; every change is marked `Ishara app:` in the file. Changes: data (shapes, signs, cast) loaded from files instead of inline; three.js and the GLBs from the local server instead of jsdelivr / base64; the unused compressed-rig path (`buildRig`, `loadScript`, `inflate`) not ported; the word mapping (`ALIASES`, `poseNameFor`) removed (the catalogue maps words; Q-A5, sign rule 7); events to Flutter (`ready`, `signStarted`, `signEnded`, `error`, `thumbnail`, `stats`); `pause` / `resume`, `reframe(captionPx)` (the caption is a Flutter widget), `setReduceMotion` (from the OS, not the WebView media query), `preview` (freeze + camera angle); finger spread (Q-A6). | Prompt: "ported, not rewritten". Checked by `tools/avatar_port_check.py`: 71 frames of the 13 unchanged signs render identically to the prototype (worst mean difference 0.07 / 255, blinks). |
| 2026-10-09 | Sign library per pack: `assets/packs/<lang>/avatar/library.json` (shapes with curl / reach / optional spread, signs as keyframes, `previewPairs`). The prototype's data is extracted by `tools/extract_avatar_library.mjs` into `test/fixtures/prototype_avatar_library.json`, with the sha256 of the prototype block; a test fails if the prototype changes or if a ported sign differs from it (except the decided WATER / I LOVE YOU changes). | ArSL = new data only; port fidelity is tested, not trusted. |
| 2026-10-09 | Finger spread (Q-A6): per shape `spread` = degrees per finger (+ toward the thumb side), applied at the knuckle in the palm plane before the curl. Shapes without `spread` behave exactly as before. | Q-A6 ("data plus a few lines in curlHand"). |
| 2026-10-09 | Loopback server `AvatarAssetServer`: `dart:io` HttpServer on 127.0.0.1, random port, random 128-bit path token, GET/HEAD only, `Host` must be 127.0.0.1:port (DNS rebinding), only `avatar/**` and `packs/<lang>/avatar/*` with html/js/css/json/glb types, `nosniff`, `no-store`. Page CSP: `default-src 'none'`, scripts from self + the import map's hash + `wasm-unsafe-eval` (meshopt decoder), no network. WebView navigation limited to the server. Android: `INTERNET` permission + cleartext allowed for 127.0.0.1 only (network security config); iOS: `NSAllowsLocalNetworking`. | ES modules don't load from `file://`; nothing leaves the phone. |
| 2026-10-09 | One WebView for the app: `AvatarHost` (app root) keeps it alive; screens place `AvatarStage` / `AvatarSlot`; a slot is visible while its route is on stage (ticking: not covered by an opaque route, not a hidden tab) and not leaving; the last one to become visible wins (prototype `mountAvatar`). A dialog or sheet on top keeps the avatar where it is (review fix). Ownership changes after the frame, under one GlobalKey, so the view is never built twice; with no slot it is parked offstage and rendering is paused (also when the app is in the background). | Prompt: "keep one WebView alive for the whole app". Dialogs stay above the avatar (it lives in the screen, not over the navigator). |
| 2026-10-09 | `AvatarController.play(label)` accepts only labels of the pack's library and throws otherwise (a bug, never a guess). `noSign()` = the prototype's "word without a sign" behaviour. Every `signStarted` has exactly one `signEnded` (interrupted or not), with the id `play` returned. Commands before the page is up are queued; when the WebView (re)loads the page (`pageStarted`), signs sent to the old page end as interrupted, commands wait, and after `init` the new page gets back pause / stats / caption height / tint. Pausing (no screen shows the avatar, app in background) ends the current sign as interrupted: a sign nobody saw is never reported as played. `setCharacter` returns nothing; the greeting after a character loads is pack data (`library.json` `greeting`, ASL: hello, as the prototype) and has id null. | Sign rule 7; Talk (step 7) sequences sentences on these events. |
| 2026-10-09 | Without a WebView (flutter test, unsupported platform) the avatar reports `unsupported`: the stage keeps the prototype's silhouette placeholder, no server is started. | Tests and all screens run without a device. |
| 2026-10-09 | New signs (one–five, bye, come, drink, call, hungry) are in the library but stay `avatar: false` in `signs.json` until the user approves their front + side previews; the developer preview screen (`/dev/signs`, debug / profile builds only, English only) and `tools/avatar_shots.py` show them. | Sign rule 2. |
| 2026-10-09 | Observation, not changed (port fidelity): the prototype's body-depth grid (`measure`) finds no vertices for both GLB characters, so every contact depth uses the fallback `0.08 · k`; contacts are tuned by `lmAdj` / keyframe offsets instead. | Reported to the user. |
| 2026-10-09 | One asset reader `readAssetBytes` (lib/core/assets) for every bundle read; it returns only the asset's range of the `ByteData` buffer. | Review fix: three copies used the whole backing buffer. |
| 2026-10-09 | Gradle heap 3 GB (`android/gradle.properties`; template default 8 GB). Emulator on this laptop (Intel iGPU + RTX 4050): plain `-gpu host` falls back to the iGPU and fails ("Your GPU cannot be used for hardware rendering"); it runs on the RTX 4050 with NVIDIA PRIME offload: `__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only emulator -avd ishara_api36 -no-snapshot -gpu host &`. One heavy job at a time. | The machine hung twice under Gradle (8 GB) + software-GPU emulator + another job (user instruction). |
| 2026-10-09 | Engine fix (S5-2): `measure` reads skinned vertex positions (`SkinnedMesh.getVertexPosition`). The GLB meshes are quantized (KHR_mesh_quantization: raw positions in -1..1), so the prototype found no vertex and used one fixed depth (0.08·k) for every contact. The surface lookup also searches up to 3 cells (3 cm) beside the face before that fallback. | The fixed depth put Nour's contacts 1–2 cm off and Sara's up to 5 cm off. |
| 2026-10-09 | Engine fix (S5-2): contacts land on the skin. For a key measured from a landmark with `at: tip / palm`, the baked pose is measured (the shape's `tip` finger end, or the palm centre) and the target moved by the error, up to 5 times (< 2 mm). Contact frames now use small depths (0–6 mm); the prototype's depths had been tuned around the wrong measurement. Keys with absolute points are untouched. | Exact contacts; the 6 signs without contacts stay pixel-identical (port check: worst 0.06 / 255). |
| 2026-10-09 | Engine (S5-1): a hand key may carry `E`, the elbow direction (signer frame, like H); without it, the prototype's fixed pole. Used by CALL and HOME. | Elbows at head height were wrong signs. |
| 2026-10-09 | Engine (Q-A6 extended): `spread` also applies to the thumb: like the fingers, + turns it toward the pinky → index direction, which swings the thumb sideways away from the fingers (skipped if it already points that way). FIVE and THREE use it, so FIVE's thumb is out and FOUR's (no spread, curl 88) lies across the palm; the two differ from the side. | Review: FOUR and FIVE looked the same from the side. |
| 2026-10-09 | Sign fixes from the review (all `avatar: false` new signs stay unapproved): FOUR thumb folded; THREE / FIVE thumb out; COME start at chest height; DRINK short arc to the chin, hand below the lips; HUNGRY deeper C angled into the chest; CALL Y hand beside jaw and cheek, elbow down; HOME elbow low, cheek touch 2.5 cm lower; YOU points level; contact signs touch. I LOVE YOU was already still (the recording's motion is the lead-in from the ready pose). | Review sheets and status per sign: `tools/out/review2/index.html` (`tools/make_sign_report.py`). |
| 2026-10-09 | Brand: `brand/ishara_mark.svg` is the only source; `tools/make_brand.py` writes the Android adaptive icon (gradient background, white hand in the safe zone, monochrome), legacy PNGs, launch / Android 12+ splash vectors and colours, and the iOS AppIcon (opaque), LaunchImage and LaunchBackground (light / dark). `IsharaMark` draws the same mark in Flutter; a test keeps the SVG, the widget and the prototype logo in step. | User S5-4. |
| 2026-10-09 | Native launch: `windowBackground` (LaunchTheme and NormalTheme) and the Android 12+ `windowSplashScreenBackground` are `@color/ishara_bg` = prototype `--bg` (light `#F4F2EC`, dark `#121318`). The Flutter splash is the prototype `#splash` (radial gradient, mark with glow, "Ishara", tagline, loading bar, pop-ins; Welcome after 2.1 s or a tap). | No white flash, no Flutter logo, no light flash in dark mode (emulator burst screenshots). Known difference: the mark moves up about 60 dp when the Flutter splash takes over (the native splash can only centre the mark; the prototype centres the whole group). |
| 2026-10-09 | Emulator screen recording (`adb shell screenrecord`) crashed the host-GPU emulator when started before the app; starting it once the app runs, at 540 × 1170, works. | Note for later recordings. |
| 2026-10-09 | Engine: landmark `ear` (beside the head) takes its height from the eyes and its depth from the head bone, not from the skin (the side of the face and hair are too uneven to measure). CALL's wrist uses it, so it lands beside the jaw on both characters (Nour's pose unchanged; Sara's hand no longer covers her face). | Found when checking the contact signs on Sara. Sara's hair is not simulated: her arm passes through it in CALL. |
| 2026-10-10 | Splash: wrapped in a transparent `Material` (its texts had no Material / DefaultTextStyle and showed Flutter's debug style: yellow double underline). Golden renders the real app root and route; a test fails if any splash text has the debug fallback style (checked to fail without the fix). | Review round 2, item 1. |
| 2026-10-10 | Splash layout: a `MultiChildLayoutDelegate` centres the group and places the mark between the screen centre and its slot from the real size at every layout (a first attempt measured after the frame and kept a 0 × 0 window size, sending the mark to a corner). The background gradient's ellipse is skipped at 0 × 0 (it divided by zero). The 2.1 s and the animations start after the splash's first frame with a real size (on a cold debug start Android lays the window out at 0 × 0 behind its own splash, and the timer had already run out). | Found on the emulator; regression tests for both. |
| 2026-10-10 | Android 12+ splash exit: the default (fade) is kept. An instant `setOnExitAnimationListener { remove() }` removed the system splash before Flutter had drawn and showed black frames. | Emulator. |
| 2026-10-10 | Emulator note: on the host GPU the starting window was sometimes black and the emulator crashed several times (GL context lost); on the software GPU (`-gpu swiftshader_indirect`) the launch is correct in both themes. Launch checks use a launcher-style start (`monkey … LAUNCHER`). | Not an app issue; the real check is the user's phone. |
| 2026-10-10 | DOCTOR (avatar-only, `verified: false`): the bent fingertips tap the middle of the other palm, Lifeprint's recommended form taps the inside of the wrist (pulse). Listed for the user, not changed (sign rule 1). HELP, COFFEE, FAMILY match their references. | S5-8. |
