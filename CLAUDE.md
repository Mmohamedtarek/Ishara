# Ishara: rules for every session

Ishara = sign-language glove (BLE) + Flutter app: glove → text/speech, speech → 3D avatar signs, Learn.
App v1 = **ASL only**. ArSL comes later as a data-only pack. The app runs today on mock glove data and later on the real glove by changing only the data source and the model files.

## Ask, don't guess
If anything is unclear, or two sources disagree, **stop and ask the user**. Never invent a sign, a word mapping, a threshold or a UI text. A wrong sign shown, or a wrong word spoken, is the worst bug this product can have.

## Sources of truth (read before changing related code)
| Source | Decides |
|---|---|
| `design/prototype.html` (read via `python3 app/tools/strip_prototype.py` → `app/tools/out/prototype/`) | screens, flows, EN/AR texts, colors, animations, avatar engine |
| `design/Figma-Import-Screens/` | pixel reference per screen (390 × 844); where it disagrees with the prototype, ask |
| `app/Ishara-Mobile-Kit/AI-SPEC.md` | recognition pipeline, exactly (normalize → 2 s window → 3-model average → Decider) |
| `app/Ishara-Mobile-Kit/model/` | models, `labels.txt` (22 labels), `decider.json` |
| `app/Ishara-Mobile-Kit/mock/`, `test/test_vectors.json` | mock glove, numbers the pipeline must reproduce |
| `app/Ishara-Mobile-Kit/README.md` | kit rules |
| `docs/BLE-CONTRACT.md`, `docs/BLE-TESTING.md` | everything over Bluetooth |
| `docs/Ishara-Sign-Vocabulary-v2-ASL.pdf` | the 20 glove signs and the ASL form of each (reference for every avatar animation) |

## Never change
`app/Ishara-Mobile-Kit/`, `docs/BLE-CONTRACT.md`, `docs/Ishara-Sign-Vocabulary-v2-ASL.pdf`, `design/`, `AI/`, `firmware/`, `hardware/`.
If one looks wrong, tell the user. Kit files reach the app only through `app/tools/sync_kit.sh` (a checksum test fails on any drift).

## Hard design rules
- One `GloveSource` interface (mock / BLE) → one real Recognizer → `Stream<RecognitionEvent>`. Only `lib/core/glove/` knows which source is active (`--dart-define=GLOVE=mock|ble` + hidden dev switch). The mock fakes raw samples only, never words.
- Labels come from `labels.txt`, config from `decider.json`. Nothing about the 22 labels is hard-coded.
- Test files use **0-based** steps (AI-SPEC §8); the pseudo-code counter starts at 1.
- Recognition runs on the phone, in an isolate. Sensor data and recognized sentences never leave the phone unless the user saves a phrase.
- Every word list lives in `assets/packs/<lang>/signs.json`. No duplicated lists.
- Every Firebase call sits behind a repository interface with a local fake; the app and all tests run with no Firebase project.

## Sign correctness rules
1. Every avatar animation must match vocabulary v2 (hand shape, place, palm direction, movement). If one doesn't, list it for the user; never fix it on your own.
2. New animations (signs with no keyframes) need a user-supplied reference and a front + side preview approved by the user before they reach Learn.
3. Learn "your turn" (glove practice) steps use only `glove: true` signs. `glove: false` signs appear only in "watch and pick" steps.
4. The practice check is real: pass only when the Recognizer emits that exact label (`word` / `confirm`) within the time limit; the % shown is the model's real probability. No random numbers, no timers that always pass.
5. `verified: false` signs show a "being reviewed" marker in debug builds only.
6. Glove → text follows AI-SPEC §7: tentative = faded + "…", `confirm` → normal + spoken, `cancel` → fades out. Never speak a tentative word.
7. Speech → sign: exact match after normalization (case, Arabic diacritics, hamza/alef forms, ة/ه, ى/ي), never fuzzy. A word with no sign keeps the avatar in the ready pose and shows the word in the caption. Never play the wrong sign.
8. ArSL is never active in v1: picking it shows the "coming soon" dialog and keeps ASL; a stored `arsl` falls back to ASL.

## Review protocol (every step, unasked)
1. Before coding: checklist of the step's requirements, each traced to its source (file + section).
2. After coding: `flutter analyze` (zero issues, very_good_analysis), `dart format`, all related tests. Fix until green.
3. Review the diff line by line (bugs, edge cases, null/async, leaks of streams/controllers/WebView, RTL, dark mode, missing translations, hard-coded labels, accessibility, security), then run `/code-review` and fix what it finds.
4. UI steps: screenshot each new/changed screen (EN/AR × light/dark) next to the prototype; list every difference; fix or ask.
5. Record results in `app/PROGRESS.md` (built, checklist ✓/✗, test counts, coverage, screenshots, open questions) and decisions with reasons in `app/DECISIONS.md`.
6. Never call a step done without evidence. Say plainly what failed or was skipped.
7. Commit the step (don't push), show the summary, and wait before the next step.
