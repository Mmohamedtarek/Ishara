# Ishara Mobile Kit (v3.2.3)

The kit holds everything the mobile app needs to recognize signs today. The app doesn't have to wait for the glove, and needs no rewrite when the glove is ready.

## What's new

- **v3.2.3:** new `mock/A/calibration/` and `mock/B/calibration/` folders with `open.csv`, `fist.csv` and `turn.csv`: what the glove's sensors read during each calibration step, for the same person as the other mock files. The mock glove plays them during `CAL OPEN` / `CAL FIST` / `CAL TURN`. Models, labels, config, spec and every other file are unchanged.
- **v3.2.2:** new models trained on Sign Vocabulary **v2.2**:
  - COME is one quick arc of the index toward you (Lifeprint);
  - WATER taps the mouth.

  `model/`, `mock/` and `test/` are rebuilt. **The spec is unchanged (v3.2.1)**, and so are the labels and the config. Run `sync_kit.sh` and the tests.
- **v3.2.1:**
  1. The BLE gap rule is now exact in `AI-SPEC.md` section 4, with a new `gaps` test in `test/test_vectors.json`.
  2. New `mock/A/practice/` and `mock/B/practice/` folders: one file per sign, held the way a learner signs in Learn. Each file confirms its sign exactly once (including `one` and `me`).
- **v3.2:** the signs follow **ASL** (Sign Vocabulary v2):
  - `good` and `bad` are replaced by `water` and `bye`;
  - HELLO, NO and THREE use their ASL forms.

  The models, `mock/` and `test/` are rebuilt. Nothing about how the app works changes: same normalize, same Decider, same events. If your code reads the labels from `labels.txt`, swap the files and you're done.

## Files

| File | What it is | Who changes it |
|---|---|---|
| `BLE-CONTRACT.md` | The contract between the glove and the app: UUIDs, data format, commands, calibration | **Both teams together only** |
| `AI-SPEC.md` | The recognizer in the app, step by step: normalize, window, the 3 models, the Decider and its events (word / tentative / confirm / cancel) | **AI team only** |
| `model/ishara_cnn.tflite`, `ishara_cnn_2.tflite`, `ishara_cnn_3.tflite` | The 3-model ensemble; the app averages them (about 490 KB in total) | **AI team only** |
| `model/labels.txt` | The order of the 22 output classes | **AI team only** (changes with the model) |
| `model/decider.json` | Decider settings | **AI team only** |
| `mock/A/`, `mock/B/` | A simulated glove for two people. Each folder holds: <br>• one file per sign (20), plus `rest` and `other`; <br>• `sentences.csv` (continuous sentences); <br>• `everyday.csv` (5 minutes of everyday movement); <br>• `practice/` (each sign held, as in a Learn practice) | — |
| `mock/<person>/calibration/` | `open.csv` and `fist.csv` (2.4 s, hand still) and `turn.csv` (3.4 s, palm turned about ±42° left and right, then still). The first line is the same `#CAL` as that person's other files. They pass the firmware's rules: gyro std below 3 °/s per axis while still, ≥ 300 counts between open and fist on every finger, ≥ 30° of roll (roll = atan2(ay, az), rate on gyro X) | — |
| `mock/expected.json` | The confirmed words the app **must** produce from each file, and every event in order | — |
| `mock/ble_frames.txt` | Real BLE frames (hex) with their decoded values, to test the frame parser | — |
| `test/test_vectors.json` | Numbers your code must reproduce: normalize, each model, their average, the Decider events, and the BLE gap rule | — |
| `claude-code-prompt-ble-firmware.md` | The prompt the embedded team used to build BLE in the glove on this contract | Embedded team |

## Rules that keep the teams from breaking each other's work

1. **Don't change the AI logic.** Normalize and the Decider are copied from `AI-SPEC.md` exactly. If something is unclear, ask the AI team; don't guess.
2. **One data source.** The whole app talks to one `GloveSource` interface. Underneath it are `MockGlove` (reads `mock/` at 50 samples per second) and `BleGlove` (the real glove). When the glove is ready, the change is one line.
3. **`model/` is replaced as a unit.** When the model improves, the AI team sends all its files together. You drop them in place without changing code.
4. **Any change to `BLE-CONTRACT.md` or `AI-SPEC.md`** needs both teams to agree, and a new version number.

## How to check your code is right

1. **`test/test_vectors.json`:**
   - normalize matches to 0.0001;
   - each model matches to 0.001;
   - the Decider produces the same events at the same steps;
   - the `gaps` stream produces the same events.
2. **`mock/expected.json`:** play every mock file through the app and compare the words and events.
3. **`mock/ble_frames.txt`:** the BLE parser decodes every frame to the same numbers.

The AI team checked this kit with an independent implementation written from the spec only:
- all test vectors match;
- every event matches at the same step;
- 88 of 88 mock files give exactly the same words and events;
- the gap test matches.

**Step numbers (`step`) in the test files start at 0** (the first model run is step 0). See `AI-SPEC.md` section 8.

## Translation is always on (no button)

There is no "talk" button. The Decider works out by itself whether the person is signing or just moving their hand. The app gets **4 events** (details in `AI-SPEC.md` section 5):

| Event | What the app does |
|---|---|
| `word` | Show the word and speak it |
| `tentative` | Show the word **faded**, with "…", and don't speak it |
| `confirm` | The faded word becomes normal and is spoken now |
| `cancel` | Remove the faded word (it wasn't a sign) |

Test results (new people, 60 hours of continuous wear, no button):

| | |
|---|---|
| Stray words | **0.0017 per minute** (about one every 10 hours of wear) |
| WER in conversations | about 9–12% |
| A faded word shown and removed | less than once an hour |

## Notes

- **This data is simulated.** The model was trained on similar data, so it understands it well. That's right for building the app; the real numbers come after the glove is recorded.
- **Some mock files don't produce every expected sign, on purpose.**
  - When `one`, `me`, `come`, `drink` and `hungry` are signed **on their own** (not in a sentence), they need to be held still for about half a second to be confirmed. In those files a tentative word sometimes appears and is cancelled.
  - `sentences.csv` has one or two mistakes.
  - The app must produce **exactly** what `expected.json` says, not the "right" words.
- **Learn practice:** use the files in `practice/`; each confirms its sign once.
- **Calibration on the mock:** during `CAL OPEN`, `CAL FIST` and `CAL TURN`, play `calibration/open.csv`, `fist.csv` and `turn.csv` (loop a file if a step lasts longer). At `CAL SAVE` / `GETCAL`, reply with the file's first line (`#CAL …`). Don't play `rest.csv` during calibration: its gyro isn't still, so a real glove would answer `MOVED`.
- **Optional UI idea:** the user can tap a faded word to confirm it.
- **The BLE frame format is final.** If the firmware isn't ready, build the parser from `ble_frames.txt`.
