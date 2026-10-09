# Ishara: rules for every session

Ishara = sign-language glove (BLE) + Flutter app: glove → text/speech, speech → 3D avatar signs, Learn.
App v1 = **ASL only**. ArSL comes later as a data-only pack. The app runs today on mock glove data and later on the real glove by changing only the data source and the model files.

## Ask, don't guess
If anything is unclear, or two sources disagree, **stop and ask the user**. Never invent a sign, a word mapping, a threshold or a UI text. A wrong sign shown, or a wrong word spoken, is the worst bug this product can have.

## Sources of truth (read before changing related code)
| Source | Decides |
|---|---|
| `design/prototype.html` (read via `python3 app/tools/strip_prototype.py` → `app/tools/out/prototype/`) | screens, flows, EN/AR texts, colors, animations, avatar engine |
| `design/Figma-Import-Screens/` | older design: pixel reference **only** where it shows the same screen with the same structure; the prototype wins everywhere else, and static-only features are out of v1 (Q-D1) |
| `app/Ishara-Mobile-Kit/AI-SPEC.md` | recognition pipeline, exactly (normalize → 2 s window → 3-model average → Decider) |
| `app/Ishara-Mobile-Kit/model/` | models, `labels.txt` (22 labels), `decider.json` |
| `app/Ishara-Mobile-Kit/mock/`, `test/test_vectors.json` | mock glove, numbers the pipeline must reproduce |
| `app/Ishara-Mobile-Kit/README.md` | kit rules |
| `docs/BLE-CONTRACT.md`, `docs/BLE-TESTING.md` | everything over Bluetooth |
| `docs/Ishara-Sign-Vocabulary-v2-ASL.pdf` | the 20 glove signs and the ASL form of each (reference for every avatar animation) |
| `docs/ASL-REFERENCES.md` | one ASL video reference per sign; vocabulary v2.2 decisions (COME = one arc toward you, WATER taps the mouth) win over the v2.1 PDF (DECISIONS V-1…V-4) |

## Never change
`app/Ishara-Mobile-Kit/`, `docs/BLE-CONTRACT.md`, `docs/Ishara-Sign-Vocabulary-v2-ASL.pdf`, `design/`, `AI/`, `firmware/`, `hardware/`.
If one looks wrong, tell the user. Kit files reach the app only through `app/tools/sync_kit.sh` (a checksum test fails on any drift).

## Hard design rules
- One `GloveSource` interface (mock / BLE) → one real Recognizer → `Stream<RecognitionEvent>`. Only `lib/core/glove/` knows which source is active (`--dart-define=GLOVE=mock|ble` + hidden dev switch). The mock fakes raw samples only, never words.
- Labels come from `labels.txt`, config from `decider.json`. Nothing about the 22 labels is hard-coded.
- Test files use **0-based** steps (AI-SPEC §8); the pseudo-code counter starts at 1.
- BLE gaps follow AI-SPEC v3.2.1 §4 exactly (repeat 1–5, reset > 5 with `cancel` first, drop duplicate/older, `seq` mod 65536). "Rounded" in the spec = Python round-half-to-even.
- Every mock file in `mock/expected.json` must match exactly (events and steps). If one differs, stop and ask.
- Recognition runs on the phone, in an isolate. Sensor data and recognized sentences never leave the phone unless the user saves a phrase.
- Every word list lives in `assets/packs/<lang>/signs.json`. No duplicated lists.
- Every Firebase call sits behind a repository interface with a local fake; the app and all tests run with no Firebase project.

## Sign correctness rules
1. Every avatar animation must match vocabulary v2 (hand shape, place, palm direction, movement). If one doesn't, list it for the user; never fix it on your own.
2. New animations (signs with no keyframes) need a user-supplied reference and a front + side preview approved by the user before they reach Learn.
3. Learn "your turn" (glove practice) steps use only `glove: true` signs. `glove: false` signs appear only in "watch and pick" steps.
4. The practice check is real: pass only when the Recognizer emits that exact label (`word` / `confirm`) within 8 s (3 attempts); the % shown is the smoothed model probability of that label at that step. No random numbers, no timers that always pass. On the mock source, "Sign now" plays `mock/<A|B>/practice/<label>.csv` through the real pipeline.
5. `verified: false` signs show a "being reviewed" marker in debug builds only.
6. Glove → text follows AI-SPEC §7: tentative = faded + "…", `confirm` → normal + spoken, `cancel` → fades out. Never speak a tentative word on its own; the only exception is the user tapping it, which confirms and speaks it and is logged as a user confirmation (Q-T1). No unsure-word alternatives.
7. Speech → sign: exact match after normalization (case, Arabic diacritics, hamza/alef forms, ة/ه, ى/ي), never fuzzy. A word with no sign keeps the avatar in the ready pose and shows the word in the caption. Never play the wrong sign. The only aliases are those in Q-T5.
8. ArSL is never active in v1: picking it shows the "coming soon" dialog and keeps ASL; a stored `arsl` falls back to ASL.

## Decided product rules
All user decisions live in `app/DECISIONS.md` by ID (Q-…, C…). Follow them; a rule there overrides the prototype. Key ones: email-only auth (Q-B2); Spark plan, no Cloud Functions (Q-B1); theme follows the system (Q-D3); history stays on the phone, starred phrases sync (Q-B4). Release blocker RB-1: the avatar models are non-commercial samples and must stay swappable.
Anything marked "draft" (new texts, Arabic spoken words, pair copy, new screens) is shown to the user before it ships.

## Dependencies
Check the licence of every new package (and whether it phones home) before adding it. `flutter_blue_plus` is not used (licence + build telemetry); the BLE library is `flutter_reactive_ble` 5.6.0 (user decision).

## Devices
Emulator `ishara_api36` for development and mock integration tests; the user's USB phone for anything BLE; CI runs everything that needs no device. Disk is tight: keep build outputs and caches lean.

## Review protocol (every step, unasked)
1. Before coding: checklist of the step's requirements, each traced to its source (file + section).
2. After coding: `flutter analyze` (zero issues, very_good_analysis), `dart format`, all related tests. Fix until green.
3. Review the diff line by line (bugs, edge cases, null/async, leaks of streams/controllers/WebView, RTL, dark mode, missing translations, hard-coded labels, accessibility, security), then run `/code-review` and fix what it finds.
4. UI steps: screenshot each new/changed screen (EN/AR × light/dark) next to the prototype; list every difference; fix or ask.
5. Record results in `app/PROGRESS.md` (built, checklist ✓/✗, test counts, coverage, screenshots, open questions) and decisions with reasons in `app/DECISIONS.md`.
6. Never call a step done without evidence. Say plainly what failed or was skipped.
7. Commit the step (don't push), show the summary, and wait before the next step.
