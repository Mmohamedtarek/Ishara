# Ishara AI — what the app must do (spec v3.2)

**v3.2 changes only the vocabulary** (Sign Vocabulary v2, ASL): `good` and `bad` are replaced by `water` and `bye`, and the models are retrained. The pipeline, the numbers format and the Decider are exactly the same as v3.1. Code that reads the labels from `labels.txt` needs no change.

The recognizer in the app must behave **exactly** like `live.py` in the AI repo. This file is the full description. `test/test_vectors.json` checks every step with real numbers.

```
samples (50 Hz) → normalize (calibration) → 2-second window → 3 models every 0.2 s → average → Decider → events
```

## 1. Input: one sample

11 numbers per sample, in this order, raw from the glove (BLE frame or mock CSV):

| Index | Name | Raw unit |
|---|---|---|
| 0–4 | f0 f1 f2 f3 f4 (thumb, index, middle, ring, pinky) | ADC 0–4095 |
| 5–7 | ax ay az | 8192 = 1 g |
| 8–10 | gx gy gz | 65.5 = 1 °/s |

Mock CSV lines are `seq,f0,f1,f2,f3,f4,ax,ay,az,gx,gy,gz`: drop the first number (`seq`). Lines starting with `#` are messages, not samples (the first line of every mock file is `#CAL ...`).

## 2. Calibration (from `#CAL`)

```json
{"v":2,"open":[o0..o4],"fist":[f0..f4],"gyro_bias_raw":[bx,by,bz],"roll_neutral":..,"roll_min":..,"roll_max":..}
```

Store it per user. When a new `#CAL` arrives: replace it, and **clear the window** (section 4).

## 3. Normalize every sample (float32)

```
for i in 0..4:   span = fist[i] - open[i];  if |span| < 1: span = 1
                 x[i] = (raw[i] - open[i]) / span          # 0 = open, about 1 = closed
for i in 5..7:   x[i] = raw[i] / 8192                      # g
for i in 8..10:  x[i] = (raw[i] - gyro_bias_raw[i-8]) / 65.5 / 250
```

No clipping, no rounding. Tolerance in the tests: 1e-4.

## 4. Window and model

- Keep the **last 100 normalized samples** (2 s), oldest first.
- Count samples. When the window is full **and** the count is a multiple of 10, run the model once (5 times per second).
- Models: the files listed in `decider.json` → `"models"` (today 3: `ishara_cnn.tflite`, `ishara_cnn_2.tflite`, `ishara_cnn_3.tflite`). Each takes float32 input `[1, 100, 11]` and gives `[1, 22]` softmax probabilities.
- Run **every** model on the same window and take the **element-wise average** of their 22 probabilities. That average is what the Decider gets. (Three small models that disagree on a weird movement cancel each other's mistakes; together they cost about 15 ms per run on a phone.)
- Output order = `model/labels.txt`, one label per line: the 20 signs, then `rest`, then `other`.
- `rest` and `other` are **non-words** (never shown or spoken).
- Missing samples (BLE gap): see BLE-CONTRACT section 4.

## 5. Decider: when to say a word

Translation is **always on** (no button). The Decider works out by itself whether the person is signing or just moving their hand, and emits **events**:

| Event | What the app does |
|---|---|
| `word w` | show `w` and speak it |
| `tentative w` | show `w` **faded / grey** with a small "…" (not spoken yet) |
| `confirm w` | the faded `w` becomes normal, and is spoken now |
| `cancel w` | remove the faded `w` (it was not a sign) |

Config = `model/decider.json` → object `"cnn"`:

| Field | Meaning |
|---|---|
| `models` | model files to average (section 4) |
| `smooth` | average the last `smooth` probability vectors |
| `idle` | level used for a word when the person is not in a conversation: strict |
| `tentative` | easier level: when the person is not in a conversation, a word that passes it is shown as tentative |
| `active` | easy level used inside a conversation (after any confirmed word) |
| `active_s` | the conversation ends after this many seconds without a confirmed word |
| `confirm_s` | how long a tentative word waits for confirmation |
| `confirm_rf` | always `false` in the app (ignore) |

Each level (`idle`, `tentative`, `active`) has: `confidence` (min averaged probability of the top label), `per_class` (`{label: threshold}` overriding `confidence`), `hold` (consecutive runs the same label must pass), `max_null` (max averaged probability of `rest + other`).

One model run = one **step** = 0.2 s. `active_s` and `confirm_s` in steps = seconds × 5 (rounded).

State: `recent` (last `smooth` vectors), `last_said = none`, `rest_seen = 0`, `step = 0`, `active_until = -1`, `pending = none`, `pending_until = -1`, `blocked = {}` (a set of labels), and for each level a run `(run_label = none, run_count = 0)`.

On every averaged model output `p`:

```
step += 1
events = []
if pending != none and step > pending_until:
    events += cancel(pending); blocked.add(pending); pending = none

recent.push(p)                                  # keep the last `smooth`
avg = mean(recent); top = argmax(avg); label = labels[top]; conf = avg[top]

if label is "rest" or "other":
    rest_seen += 1
    if rest_seen >= 2: last_said = none; blocked.clear()
    every level's run = (none, 0)
    return events
rest_seen = 0
null = avg["rest"] + avg["other"]

for each level L in (idle, tentative, active):         # update all runs every step
    thr = L.per_class[label] if label in L.per_class else L.confidence
    if len(recent) == smooth and conf >= thr and null <= L.max_null:
        run_count(L) = run_count(L) + 1 if run_label(L) == label else 1
        run_label(L) = label
        passed(L) = run_count(L) >= L.hold
    else:
        run(L) = (none, 0); passed(L) = false

if step <= active_until:                                   # inside a conversation
    if passed(active) and label != last_said:
        events += word(label); say(label)
elif pending != none:                                       # waiting to confirm a tentative word
    if label == pending:
        if passed(idle): events += confirm(label); say(label); pending = none
    elif passed(active) and label != last_said:            # a second word arrived: both are real
        events += confirm(pending); events += word(label); say(label); pending = none
elif label != last_said:                                    # idle, nothing pending
    if passed(idle):
        events += word(label); say(label)
    elif passed(tentative) and label not in blocked:
        events += tentative(label); pending = label; pending_until = step + confirm_steps
return events

say(label):  last_said = label; active_until = step + active_steps
```

Events come out in this order inside one step. Reset all state (and the window) when the glove reconnects or a new calibration arrives.

## 6. Words to speak

| label | spoken | label | spoken |
|---|---|---|---|
| one | one | no | no |
| two | two | sorry | sorry |
| three | three | water | water |
| four | four | bye | bye |
| five | five | come | come |
| me | me | drink | drink |
| you | you | call | call |
| hello | hello | iloveyou | I love you |
| thanks | thank you | hungry | hungry |
| please | please | yes | yes |

## 7. UI notes

- Tentative words: same position as a normal word, grey/faded, with "…". On `confirm` animate to normal and speak. On `cancel` fade out. A tentative word usually lasts under 3.5 s.
- Do not speak tentative words. Only `word` and `confirm` are spoken.
- No talk / listen button is needed.

## 8. How to know your implementation is right

`test/test_vectors.json`:
- `normalize.cases`: raw window + `calibration` → first normalized row and the sum of the whole window must match (1e-4);
- `model.cases`: raw window → each model's 22 probabilities (`probs_each`) and their average (`probs`) must match (1e-3);
- `decider`: feed `probs` one by one with `config` → the events (word / tentative / confirm / cancel) must come out at exactly the `expected` steps.

**Step numbers in the test files:** `step` in `test_vectors.json` and `mock/expected.json` is the **0-based index of the model run** (the first model run is step 0). The pseudo-code counter above starts at 1, so compare `step - 1` with the files. `sample` in `expected.json` is the number of samples received when that model run happened.

`mock/expected.json`: play each mock file at 50 Hz through the full pipeline → the app must produce the same confirmed `words`, and the same `events`. (Words are computed with the Keras model; the .tflite in the kit can differ by about 1e-6, which can very rarely move a word by one step.)

## 9. What changes later, and what does not

When the AI team retrains on the real glove, they send **only** the `model/` folder (the .tflite files, `labels.txt`, `decider.json`). Nothing in this spec changes, so no app code changes. If the spec ever has to change, this file gets a new version number first.
