# Ishara Glove: AI (v3.2.2, ASL vocabulary v2.2)

This folder turns the glove's sensor stream into words. It has:
- the tools to record data from the glove;
- training for the models (Random Forest baseline, 3-model 1D-CNN ensemble);
- live recognition with speech;
- the evaluation;
- the build of the **Ishara Mobile Kit** that the app uses.

Until the glove is finished, everything runs on **simulated data** that has the same format as a real recording.

## Version history

- **v3.2.2:** COME is one quick arc of the index toward you (Lifeprint). The old repeated "come here" finger curl is now an everyday movement (`other`). WATER taps the mouth. Retrained from scratch.
- **v3.2:** signs follow Sign Vocabulary v2 (ASL):
  - `good` and `bad` are replaced by `water` and `bye`;
  - HELLO is the salute from the forehead;
  - NO is the index + middle snapping onto the thumb.

  `run_pipeline.sh` now trains before hard-negative mining, and deletes old model files first.
- **v3:** these changes are explained in "How recognition works" below:
  - the `other` class;
  - hard-negative mining;
  - augmentation;
  - the 3-CNN ensemble;
  - the always-on Decider with tentative words.

## Files

| File | What it does |
|---|---|
| `common.py` | Shared code: data format, calibration, the 22 labels, preparing each take |
| `glove.py` | Talking to the glove: finds the serial port, checks the stream, reads the calibration (`#CAL`) |
| `simulate_data.py` | Simulated data for the 22 classes (Sign Vocabulary v2.2, ASL), with one calibration file per simulated person |
| `record.py` | Records real data from the glove |
| `train_rf.py` | Baseline model: Random Forest (fast) |
| `train_cnn.py` | Final model: 1D-CNN. Exports TFLite for the phone and the ESP32-S3 |
| `live.py` | Live recognition: words appear on screen and are spoken |
| `eval_live.py` | Full evaluation: WER on sentences, stray words over hours of everyday movement, latency, per-sign accuracy, stress tests. `--tune` searches Decider settings, `--sessions` measures 3-hour wear sessions |
| `mine_negatives.py` | Hard-negative mining: finds everyday movements the model mistakes for signs and adds them to `other` |
| `build_kit.py` | Builds `Ishara-Mobile-Kit` (models, mock glove files, test vectors) for the app |
| `run_pipeline.sh` | The whole pipeline on simulated data (bash) |
| `decider.json` | Decider settings (confidence, hold, levels) |
| `requirements.txt` | Python packages |

Model files:
- `ishara_cnn.tflite`, `ishara_cnn_2.tflite`, `ishara_cnn_3.tflite`: the ensemble, for the phone;
- `ishara_cnn*_int8.tflite`: for the ESP32-S3;
- `ishara_cnn*.keras`: the Keras models;
- `ishara_rf.joblib`: the Random Forest (not in git; it's rebuilt by `train_rf.py`).

## Setup

Use **Python 3.12** (TensorFlow doesn't support newer versions yet). One virtual environment covers everything.

### Ubuntu

```bash
sudo apt install python3.12-venv      # if venv is missing
cd AI/Ishara-AI-v3-2
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
sudo apt install espeak-ng           # speech in live.py
sudo usermod -aG dialout $USER       # read the glove's USB port; log out and back in once
```

Each new terminal: `source .venv/bin/activate`.

### Windows 10 / 11

1. Install Python 3.12 from python.org, and tick **"Add python.exe to PATH"**.
2. In PowerShell:

```powershell
cd AI\Ishara-AI-v3-2
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

If PowerShell refuses to run `Activate.ps1`, run this once, then activate again:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

In Command Prompt, use `.venv\Scripts\activate.bat` instead.

Speech uses the built-in Windows voice (nothing to install). The ESP32-S3's USB port needs no driver on Windows 10 / 11.

### The glove's port

The scripts find the glove by itself (the ESP32-S3 USB id is `0x303A`). If they don't, give the port by hand:

| | Typical port | Example |
|---|---|---|
| Ubuntu | `/dev/ttyACM0` (sometimes `/dev/ttyUSB0`) | `python live.py --port /dev/ttyACM0` |
| Windows | `COM3`, `COM5`, … (see Device Manager → Ports) | `python live.py --port COM5` |

Close the PlatformIO / Arduino serial monitor first: only one program can use the port at a time.

## 1. Try it on simulated data (no glove needed)

The commands are the same on Ubuntu and Windows (with the virtual environment active):

```bash
python simulate_data.py          # creates data/ (simulated people)
python train_rf.py               # baseline
python train_cnn.py              # main CNN
python eval_live.py --hours 5 --no-stress   # quick evaluation (full: python eval_live.py)
python live.py --sim             # watch and hear the demo sentences (--fast: no waiting, --mute: no sound)
```

### The full pipeline

On **Ubuntu** (it takes about 1 hour):

```bash
bash run_pipeline.sh
```

It writes the kit to `app/Ishara-Mobile-Kit` (or to `KIT=...` if you set it).

On **Windows**, run the same steps in PowerShell, one after another:

```powershell
python simulate_data.py
Remove-Item ishara_cnn*.tflite, ishara_cnn*.keras, ishara_rf.joblib -ErrorAction SilentlyContinue
python train_rf.py;  python train_cnn.py
python mine_negatives.py --round 1
python train_rf.py;  python train_cnn.py
python mine_negatives.py --round 2
python train_rf.py;  python train_cnn.py
python train_cnn.py --member 2;  python train_cnn.py --member 3
python eval_live.py --hours 30
python eval_live.py --sessions 20 --no-stress --hours 1
python build_kit.py ..\..\app\Ishara-Mobile-Kit
```

(Or run `run_pipeline.sh` in Git Bash.)

**Note:** `build_kit.py` writes into the kit folder you give it. In the repo that folder is `app/Ishara-Mobile-Kit`. Only the AI team updates it, and the app then copies it with `app/tools/sync_kit.sh`.

## 2. With the real glove

1. Delete the `data` folder (it holds simulated data).
2. **Calibrate once per person:**
   - Calibrate the glove itself, from the app or from the serial monitor with `c`. There are three steps: open hand → fist → turn the wrist.
   - Then run `python record.py calib ahmed`. It reads the calibration from the glove and saves it to `data/calib/ahmed.json`.
3. **Record each sign 20 times**: `python record.py water ahmed`. Each Enter counts down 3‑2‑1, then records 2 seconds; type `q` and Enter to stop. Use the exact labels from `docs/Ishara-Sign-Vocabulary-v2-ASL.pdf`, and the ASL references in `docs/ASL-REFERENCES.md`.
4. **Everyday movements** (typing, phone, cup, …), about 60 takes: `python record.py other ahmed`.
5. **A long wear session with no signing**, then mine it:

   ```bash
   python record.py wear ahmed 60
   python mine_negatives.py --from-recording ahmed
   ```

   This is the strongest protection against stray words.
6. **Train:**

   ```bash
   python train_rf.py
   python train_cnn.py --full
   python train_cnn.py --member 2
   python train_cnn.py --member 3
   ```

   `--full` runs a complete leave-one-person-out test: slower, and that's the number to present.
7. **Evaluate:** `python eval_live.py`. Tune with `--tune` only when you have enough real people.
8. **Build the kit** and send it to the app team: `python build_kit.py ../../app/Ishara-Mobile-Kit`.

The number to present at the defense is **accuracy on new people** (people the model never saw). Accuracy on your own hand is always higher.

To pick the port by hand while recording: `python record.py water ahmed COM5` (Windows) or `... /dev/ttyACM0` (Ubuntu).

## 3. Live recognition with the glove

```bash
python live.py                   # reads the calibration from the glove
python live.py --person ahmed    # if the glove isn't calibrated, use ahmed's saved calibration
```

With no calibration at all, `live.py` runs a quick one: open hand, then fist.

Options:
- `--model rf`: use the Random Forest;
- `--mute`: no speech;
- `--port COM5` or `--port /dev/ttyACM0`.

Live recognition here uses the **USB cable**. Over Bluetooth, the app does the recognition (`app/Ishara-Mobile-Kit/AI-SPEC.md`).

## The calibration line

When the glove receives `j`, it answers:

```
#CAL {"v":2,"open":[...5],"fist":[...5],"gyro_bias_raw":[gx,gy,gz],"roll_neutral":..,"roll_min":..,"roll_max":..}
```

- `open`, `fist`: the 5 finger readings (0–4095) with the hand open and closed.
- `gyro_bias_raw`: the gyro bias in **raw stream units** (65.5 = 1 °/s). If a firmware sends it in °/s, `common.parse_glove_cal` converts it. camelCase keys (`gyroBias`, …) are accepted too.
- The bias is subtracted before the model, so differences between gloves don't matter.

If a glove can't send `#CAL`, you can still record `calib_open` and `calib_fist` the old way (`python record.py calib_open ahmed`). The gyro bias then comes from the open-hand recording, because the hand is still.

## How recognition works (v3)

- **`other` class:** everyday movements that aren't signs, such as typing, a phone, a cup, pointing or carrying a bag. Without it, the model had to pick a sign for every movement.
- **Hard-negative mining** (`mine_negatives.py`): two rounds. Each round finds the movements the model gets wrong and trains on them.
- **Augmentation** (`train_cnn.py`):
  - the MPU rotated up to 25°;
  - sign speed from 0.65× to 1.5×;
  - a dead finger sensor;
  - sensor drift after calibration.
- **Ensemble of 3 CNNs** (`--member 2`, `--member 3`, with different kernels and seeds): the prediction is their average.
- **Decider** (`live.py`, settings in `decider.json`). Translation is always on, with no button:
  - **idle:** the first word must be very clear. Otherwise it shows as a **tentative** word, which is confirmed if another word follows or it stays clear, and is removed if nothing comes.
  - **active:** inside a conversation, word-to-word transitions are fast. It goes back to idle after 4 seconds without a word.

### Results (simulated data, people the model never saw, always-on translation)

| | v3.1 (vocabulary v1) | v3.2 (ASL v2) | **v3.2.2 (ASL v2.2)** |
|---|---|---|---|
| Stray words per minute (60 h of 3-hour wear sessions) | 0.0003 | 0.0014 | **0.0017** (upper 95%: 0.0036) |
| Stray words in 30 h of everyday movement | 0 | 2 | **2** (0.0011 per minute) |
| WER | 9.4–10.6% | 9.1–10.3% | **8.8% (sentences), 12.1% (sessions)** |
| Tentative words shown and removed (per minute) | — | 0.031 | **0.014** |
| Single-sign accuracy | 94.8% | 95.6% | **96.1%** |
| Glove worn tilted 30° | 96.1% | 96.0% | **96.2%** |
| One dead sensor | 83.5% | 85.9% | **87.1%** |

Weakest signs:
- **one / me / you**: same handshape; only the direction differs.
- **water / two**, a little.
- **come / drink / hungry** signed on their own, because they look like everyday movements (a cup, a hand moving down the chest).

When recording real data, record these with clear angles, and record many similar everyday movements as `other`.

Simulated data is easier than real data. These numbers compare versions of the system; they are not the accuracy to present.
