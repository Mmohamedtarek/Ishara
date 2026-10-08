# Testing the glove over BLE

Two ways to check a glove against [`BLE-CONTRACT.md`](BLE-CONTRACT.md) before the app is ready: by hand with **nRF Connect** on a phone, or automatically with `tools/ble_check.py` on a computer.

Keep the USB serial monitor open while testing (`pio device monitor`). The firmware prints `# BLE connected`, `# BLE command <CMD>` for every command, and `# BLE disconnected, advertising`.

## UUIDs

| Name | UUID |
|---|---|
| Service | `6e1a0001-7b5c-4f3a-9a62-1d2c3b4a5f60` |
| DATA (notify) | `6e1a0002-…` |
| CMD (write) | `6e1a0003-…` |
| EVENT (notify) | `6e1a0004-…` |
| INFO (read) | `6e1a0005-…` |

All five share the same tail `-7b5c-4f3a-9a62-1d2c3b4a5f60`. nRF Connect shows them as "Unknown Service" / "Unknown Characteristic"; tell them apart by the 4th–8th hex digits (`0001` … `0005`).

## nRF Connect (Android or iOS)

1. **Find the glove.** Open the **Scanner** tab and tap **Scan**. The glove shows up as `Ishara-XXXX` (the last 4 hex digits of its Bluetooth address, also printed in the serial banner as `BLE          Ishara-XXXX`). Tap **Connect**.
   Only one phone can connect at a time. If the glove is missing from the list, another phone or the app is probably connected to it.

2. **Request MTU 247** (Android only). Menu (⋮) → **Request MTU** → `247`. The log shows `MTU changed to 247`. iOS negotiates this by itself (usually 185); there is no menu item.
   Without this step, Android stays at MTU 23 and `STREAM 1` replies `#ERR STREAM MTU`.

3. **Read INFO.** Open the service, find `…0005…` and tap the read arrow (↓). Switch the value display to **UTF-8 / Text** (tap the `"` icon). You should see:

   ```
   {"proto":1,"fw":"0.3.0","board":"devkit","rate_hz":50,"channels":11,"acc_lsb_per_g":8192,"gyro_lsb_per_dps":65.5,"flex_max":4095,"samples_per_frame":5}
   ```

   `proto` must be `1`. `board` is `devkit` or `xiao`.

4. **Subscribe to EVENT, then DATA.** Tap the notify icon (three arrows) on `…0004…` (EVENT) first, then on `…0002…` (DATA). Set EVENT's display to UTF-8 text.
   As soon as EVENT is subscribed, a battery line arrives, for example `#BAT NO_BATTERY (USB)` on USB power or `#BAT OK 3.92V 78%` on battery. If the MPU-6050 is missing, `#MPU FAIL` follows.

5. **Send commands.** Tap the write arrow (↑) on `…0003…` (CMD), choose **Text (UTF-8)**, type the command and send. Each command gets one reply on EVENT:

   | Write | Reply on EVENT |
   |---|---|
   | `GETCAL` | `#CAL {"fw":"0.3.0","v":2,"open":[…],"fist":[…],"gyro_bias_raw":[…],"roll_neutral":…,"roll_min":…,"roll_max":…,…}`, or `#CAL NONE` if the glove is not calibrated. This line is longer than one notification, so it arrives in 2–3 pieces; the last piece ends with a newline. |
   | `STREAM 1` | `#OK STREAM`, then DATA notifications start, 10 per second. |
   | `CAL OPEN` | Hold the hand open and still. After 2 s: `#CALSTEP OPEN OK`, or `#CALSTEP OPEN FAIL MOVED` if the hand moved. |
   | `CAL FIST` | Make a fist and hold still. After 2 s: `#CALSTEP FIST OK` (or `FAIL MOVED`). If a finger moved less than 300 counts between open and fist, `#FLEX WEAK <0-4>` lines come just before it (0 = thumb … 4 = pinky). |
   | `CAL TURN` | Turn the wrist palm left ↔ palm right. After 3 s: `#CALSTEP TURN OK`, or `#CALSTEP TURN FAIL RANGE` if it turned less than 30°. |
   | `CAL SAVE` | `#CAL {…}` with the new values, or `#ERR CAL MISSING OPEN` (or `FIST` / `TURN`) if a step is not done. |
   | `PING` | `#PONG` |
   | `STREAM 0` | `#OK STREAM`, DATA stops. |
   | `HELLO` | `#ERR HELLO UNKNOWN` |

   Lower case and a trailing newline are accepted (`stream 1` works). Streaming can stay on during calibration.

6. **Disconnect.** Streaming stops and unsaved calibration steps are dropped. The glove shows up in the scanner again within a second.

## Reading a DATA frame by hand

Each DATA notification is one frame of 5 samples, 114 bytes. Switch DATA's display to **Hex**. Everything is little-endian: for a 2-byte number, the **second** byte is the high one (`b1 09` = `0x09b1` = 2481).

| Bytes | Meaning |
|---|---|
| 0 | `01`: frame version |
| 1 | `05`: number of samples in the frame |
| 2–3 | `seq` of the first sample (uint16). The next frame's `seq` is 5 higher. |
| 4–25 | sample 1: 11 × int16 = `f0 f1 f2 f3 f4 ax ay az gx gy gz` |
| 26–47, … | samples 2–5, 22 bytes each |

Example: the first frame of `app/Ishara-Mobile-Kit/mock/ble_frames.txt` starts

```
01 05 00 00  05 08  b1 09  1b 09  18 09  44 0a  69 f6  9f e2  d7 f9  86 fb  5e 03  a7 fe ...
ver  n  seq   f0     f1     f2     f3     f4     ax     ay     az     gx     gy     gz
```

- `01` = version 1, `05` = 5 samples, `00 00` = seq 0
- `05 08` = 0x0805 = 2053 (thumb)
- `69 f6` = 0xf669 = 63081, which is above 32767, so subtract 65536: −2455 (ax)

That sample is `0,2053,2481,2331,2328,2628,-2455,-7521,-1577,-1146,862,-345` in the serial format. Flex values are 0–4095. Accel is 8192 per g, so a glove lying flat shows about 8192 on one axis. Gyro is 65.5 per °/s and stays near 0 when still.

`seq` should go up by exactly 5 from one frame to the next. A bigger jump means lost frames.

## Automatic check: `tools/ble_check.py`

Needs Python 3.9+ and a computer with Bluetooth LE (Linux with BlueZ, Windows 10+, or macOS).

```
pip install -r tools/requirements.txt
python tools/ble_check.py                       # first Ishara-XXXX it finds
python tools/ble_check.py --name Ishara-3FA2    # a specific glove
python tools/ble_check.py --seconds 30          # stream longer
```

It runs the contract's setup sequence (connect, MTU, read INFO and check `proto`, subscribe EVENT then DATA, `GETCAL`, `STREAM 1`), streams for 10 seconds, then sends `STREAM 0` and `PING`. It prints every EVENT line and then:

```
MTU 247 (a 5-sample frame needs at least 117)
INFO {"proto":1,...}
CAL  #CAL {...}
Streamed 10.0 s
Frames per second    10.0   (expect 10)
Samples per second   50.0   (expect 50)
Lost samples        0  (from seq)
Bad frames          0
First sample (serial format, seq is 8-bit there):
  37,1934,2397,2355,2271,2387,-474,-7970,2792,-307,-325,245
PASS
```

It exits with 0 on PASS and 1 on FAIL. It fails if `proto` is not 1, `#CAL` is missing a contract key, `STREAM 1` is refused, there are malformed frames, or the sample rate is more than 10 % off 50 Hz. Lost samples are reported but do not fail the run (a few are normal on a busy radio).

The computer's Bluetooth stack chooses the MTU itself (bleak cannot request 247). Linux, Windows and macOS all negotiate well above 117, the minimum for a 5-sample frame. If the MTU line shows 23, `STREAM 1` replies `#ERR STREAM MTU`.
