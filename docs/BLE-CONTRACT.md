# Ishara Glove — BLE Contract v1

This is the single agreement between the **glove firmware** and the **mobile app**. Both sides implement exactly this. Any change needs both teams to agree, and bumps `proto` (section 8).

All multi-byte numbers are **little-endian**. Text is **UTF-8**.

---

## 1. Advertising

| Item | Value |
|---|---|
| Device name | `Ishara-XXXX` (XXXX = last 4 hex digits of the BLE MAC, upper case, e.g. `Ishara-3FA2`) |
| Advertised service | the Ishara service UUID below |
| Connections | one central at a time. A second central is refused while one is connected. |
| After disconnect | streaming stops, advertising restarts within 1 s |

## 2. GATT

Service **Ishara**: `6e1a0001-7b5c-4f3a-9a62-1d2c3b4a5f60`

| Characteristic | UUID | Properties | Content |
|---|---|---|---|
| **DATA** | `6e1a0002-7b5c-4f3a-9a62-1d2c3b4a5f60` | Notify | sensor frames, binary (section 4) |
| **CMD** | `6e1a0003-7b5c-4f3a-9a62-1d2c3b4a5f60` | Write, Write Without Response | one text command per write (section 5) |
| **EVENT** | `6e1a0004-7b5c-4f3a-9a62-1d2c3b4a5f60` | Notify | text lines starting with `#` (section 6) |
| **INFO** | `6e1a0005-7b5c-4f3a-9a62-1d2c3b4a5f60` | Read | JSON, see below |

INFO (read once after connecting):

```json
{"proto":1,"fw":"0.4.0","board":"devkit","rate_hz":50,"channels":11,
 "acc_lsb_per_g":8192,"gyro_lsb_per_dps":65.5,"flex_max":4095,"samples_per_frame":5}
```

The app must check `proto == 1`. If not, show "update the app / firmware" and do not stream.
`board` is `"devkit"` (ESP32-S3-DevKitC-1, development) or `"xiao"` (Seeed XIAO ESP32-S3, final glove). It is for display and support only: **both boards behave exactly the same over BLE**, so the app must not branch on it. The app must ignore INFO fields it does not know.

## 3. Connection setup (app side, in this order)

1. Connect.
2. **Request MTU 247.** (Android starts at 23 and a frame does not fit. iOS negotiates on its own, usually 185.)
3. Discover services. Read INFO and check `proto`.
4. Subscribe to EVENT, then to DATA.
5. Write `GETCAL` → wait for `#CAL ...` (section 6).
6. Write `STREAM 1` → frames start arriving on DATA.

Recommended connection interval: 15–30 ms. The firmware requests it. The app should not force a slower one.

## 4. DATA frame (binary)

One notification = one frame = **n consecutive samples** (n = 5 by default → 10 frames per second at 50 Hz).

| Offset | Size | Type | Field |
|---|---|---|---|
| 0 | 1 | uint8 | `ver` = 1 |
| 1 | 1 | uint8 | `n` = number of samples in this frame (1–10) |
| 2 | 2 | uint16 | `seq` of the **first** sample. Each sample adds 1, wraps 65535 → 0 |
| 4 | 22 × n | int16 × 11 per sample | `f0 f1 f2 f3 f4 ax ay az gx gy gz` |

Frame size = 4 + 22·n bytes (n = 5 → **114 bytes**).
The firmware picks n = min(5, ⌊(MTU − 3 − 4) / 22⌋). If that is 0 (MTU < 29), it does not stream and sends `#ERR STREAM MTU`.

**Channel values are the raw values, exactly as in the USB serial line** (no scaling, no calibration):

| Channel | Meaning | Range / unit |
|---|---|---|
| f0 … f4 | flex ADC: thumb, index, middle, ring, pinky | 0–4095 |
| ax ay az | MPU-6050 accelerometer, ±4 g | 8192 = 1 g |
| gx gy gz | MPU-6050 gyroscope, ±500 °/s | 65.5 = 1 °/s |

**Timing:** samples are taken every 20 ms by a timer, not "as fast as possible". The app treats sample k as time `k × 20 ms`, ignoring when the notification arrived.

**Lost frames:** the app compares `seq` with the expected value.
- gap of 1–5 samples: repeat the last good sample for the missing ones;
- gap > 5 samples (100 ms): clear the 2-second recognition window and start filling it again.

The USB serial line for the same sample is `seq,f0,f1,f2,f3,f4,ax,ay,az,gx,gy,gz` (12 numbers; the serial `seq` is 8-bit). The mock files in `mock/` use that serial format.

## 5. CMD (app → glove)

UTF-8 text, upper case, one command per write, at most 20 bytes. Every command gets **exactly one** reply line on EVENT: `#OK <CMD>` or `#ERR <CMD> <reason>`, within 500 ms (except the calibration steps, section 7).

| Command | Effect | Reply |
|---|---|---|
| `STREAM 1` | start DATA frames | `#OK STREAM` |
| `STREAM 0` | stop DATA frames | `#OK STREAM` |
| `GETCAL` | send the stored calibration | `#CAL {json}` or `#CAL NONE` (this line is the reply, no `#OK`) |
| `CAL OPEN` | calibration step 1: hand open, flat, still for 2 s | `#CALSTEP OPEN OK` / `#CALSTEP OPEN FAIL <reason>` |
| `CAL FIST` | calibration step 2: fist, still for 2 s | `#CALSTEP FIST OK` / `… FAIL <reason>` |
| `CAL TURN` | calibration step 3: rotate the wrist left ↔ right for 3 s | `#CALSTEP TURN OK` / `… FAIL <reason>` |
| `CAL SAVE` | store the 3 steps and send the result | `#CAL {json}` or `#ERR CAL <reason>` |
| `CAL CANCEL` | drop unsaved steps | `#OK CAL` |
| `BAT` | battery state now | `#BAT ...` (section 6) |
| `PING` | link check | `#PONG` |

Unknown command → `#ERR <first word> UNKNOWN`.
Streaming can stay on during calibration (the app shows live values while the user holds the pose).

## 6. EVENT (glove → app)

Text lines, each ending with `\n`. A line longer than one notification is **split across notifications**; the app joins bytes until `\n`. The app must **ignore any line it does not know** (new messages can be added later without breaking old apps).

| Line | When |
|---|---|
| `#CAL {"v":2,"open":[5],"fist":[5],"gyro_bias_raw":[3],"roll_neutral":r,"roll_min":a,"roll_max":b}` | reply to `GETCAL` / `CAL SAVE` |
| `#CAL NONE` | glove not calibrated yet |
| `#CALSTEP <OPEN\|FIST\|TURN> <OK\|FAIL> [reason]` | end of each step |
| `#BAT NO_BATTERY (USB)` · `#BAT OK 3.92V 78%` · `#BAT LOW 3.38V` | at connect, on every state change, and as the reply to `BAT` |
| `#OK <CMD>` · `#ERR <CMD> <reason>` | command replies |
| `#PONG` | reply to `PING` |
| `#MPU FAIL` | MPU-6050 not responding (sensor problem) |
| `#FLEX WEAK <finger index 0-4>` | a finger moved less than 300 counts during calibration (sensor problem) |

`#CAL` field meanings and units are the same as the USB `#CAL` line (`gyro_bias_raw` is in raw gyro units, 65.5 = 1 °/s). This JSON is what the app stores and passes to the recognizer.
The JSON **always contains** `v`, `open`, `fist`, `gyro_bias_raw`, `roll_neutral`, `roll_min`, `roll_max`. It may contain more fields (the firmware also sends `fw`, `gravity`, and older camelCase copies such as `gyroBias`): the app reads the fields above and ignores the rest.

**Timing:** `#BAT` (and `#MPU FAIL` if the sensor is missing) is sent when the app **subscribes to EVENT**, not at connect, because a line sent before the subscription would be lost.

## 7. Calibration flow (app-driven)

```
app: CAL OPEN   → UI "open your hand, keep it still"   → glove: #CALSTEP OPEN OK
app: CAL FIST   → UI "make a fist, keep it still"      → glove: #CALSTEP FIST OK
app: CAL TURN   → UI "turn your wrist left and right"  → glove: #CALSTEP TURN OK
app: CAL SAVE   →                                       → glove: #CAL {json}
```

- Each step takes 2 s (TURN: 3 s) after the command arrives. The reply comes at the end of the step.
- A step fails if the hand moved too much (OPEN/FIST) or did not turn enough (TURN). The app shows the reason and asks again.
- Any step can be repeated before `CAL SAVE`. `CAL SAVE` without all 3 steps → `#ERR CAL MISSING <step>`.
- The gyro bias is measured during the OPEN step (hand still), as today.
- Capture starts as soon as the command arrives (no countdown on the glove: the app shows its own).
- `FAIL` reasons: `MOVED` (gyro standard deviation over 3 °/s during OPEN or FIST), `RANGE` (wrist turned less than 30° during TURN), `MPU` (no MPU-6050 during OPEN or TURN), `CANCELLED` (`CAL CANCEL` arrived during the step).
- `#FLEX WEAK <i>` lines come right before the OPEN or FIST reply, once both OPEN and FIST are done.
- Other errors: `#ERR CAL BUSY` (the USB serial calibration or another step is running), `#ERR CAL NVS` (saving failed), `#ERR CAL UNKNOWN` (unknown step), `#ERR STREAM ARG` (not `0` or `1`).
- Unsaved steps are dropped on disconnect, and when someone presses `c` or `r` on the USB serial.
- Commands are trimmed and upper-cased by the firmware, so trailing `\r\n` or lower case are accepted.
- The USB serial `c` flow stays as it is; both flows write the same stored calibration.

## 8. Versioning

Firmware 0.3.0 is the first implementation of this document.


- `proto` in INFO and `ver` in every DATA frame are both **1** for this document.
- Adding a new EVENT line or a new command does **not** change the version (old apps ignore it).
- Changing the frame layout, a UUID, or the meaning of an existing command **does**: `proto` = 2, and this file gets a new section.

## 9. Test without hardware

`mock/ble_frames.txt` has DATA frames in hex, encoded from `mock/A/hello.csv` exactly as in section 4, next to the decoded samples. The app's frame parser must decode every line to the same 11 numbers.