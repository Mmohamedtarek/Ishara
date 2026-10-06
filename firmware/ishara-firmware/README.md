# Ishara Glove firmware: calibration + BLE stage

Firmware for the Ishara sign-language glove. The same code builds for the ESP32-S3-DevKitC-1 N16R8 (development) and the Seeed XIAO ESP32-S3 (final glove), with the same GPIOs and the same output. You can run it in the Wokwi simulator inside VS Code before you have the hardware.

```
include/config.h      sensor pins (same on every board) and all constants
include/board.h       board-specific bits only: status LED, board name
src/sensors.*         flex (ADC), MPU-6050 (raw Wire), battery, roll filter
src/calibration.*     non-blocking calibration state machine
src/storage.*         NVS (Preferences, namespace "ishara")
src/console.*         "# " text lines, all ending in CRLF
src/ble.*             BLE link to the app (NimBLE), implements docs/BLE-CONTRACT.md
src/main.cpp          50 Hz loop, key handling, streams, boot banner, status line
diagram.json          Wokwi circuit (serial monitor in terminal mode)
wokwi.toml            points Wokwi at the [env:wokwi] build
test/calibration.test.yaml   wokwi-cli scenario: full calibration run
```

## Build environments

All three share the same source code and the same sensor GPIOs:

| Environment | Board | Flash / PSRAM | `Serial` | `STREAM_ON_BOOT` | Use it for |
|---|---|---|---|---|---|
| `devkit` (default) | ESP32-S3-DevKitC-1 N16R8 | 16 MB / 8 MB octal | UART port (USB-UART chip) | 1 | Development hardware |
| `xiao` | Seeed XIAO ESP32-S3 | 8 MB / 8 MB octal | native USB CDC | 1 | The final glove |
| `wokwi` | DevKitC in the simulator | board defaults | UART | 0 | The simulator. Quiet at boot: no raw stream, a `#` status line once per second instead. No BLE (`BLE_ENABLED=0`): Wokwi does not simulate the Bluetooth radio. |

`devkit` and `wokwi` define `BOARD_DEVKIT`, `xiao` defines `BOARD_XIAO`; `include/board.h` picks the status LED pin and the board name from that. The sensor pins in `config.h` are the same for every board, and the build fails (`static_assert`) if someone changes one. `pio run` builds `devkit` only. `wokwi.toml` points at `.pio/build/wokwi/`, so the simulator always runs the quiet build. `SIM_MODE` only changes the boot banner; the firmware behaves the same otherwise.

## Build and flash a board

```
pio run -e devkit -t upload          # DevKitC: plug into the port labelled UART
pio run -e xiao -t upload            # XIAO ESP32-S3
pio device monitor                   # 115200 baud, either board
```

- The `xiao` build uses an 8 MB partition table (`default_8MB.csv`), so the app never relies on the DevKit's 16 MB. NVS (where the calibration is saved) is at the same place in both tables.
- The XIAO has no USB-UART chip. `Serial` is the ESP32-S3's native USB port, which shows up as VID `0x303A` (PID `0x1001`, `/dev/ttyACM*` on Linux, a COM port on Windows). `glove.py` already looks for that VID. Opening the port does not reset the XIAO (the DevKit's UART port does), so you may not see the boot banner. Press `p` for the report, or press RESET with the monitor open.
- **If the XIAO upload fails** (no port, or `Failed to connect`): unplug USB, hold the **BOOT** button (B), plug USB back in, release BOOT, and run the upload again. After uploading, press RESET (R) or replug to start the new firmware.

## Build and run in the simulator

1. Install VS Code, then the **PlatformIO IDE** and **Wokwi Simulator** extensions.
2. Open this folder (`File > Open Folder…`).
3. Build: `pio run -e wokwi` in a terminal (or PlatformIO's ✓ button, which builds both environments). The simulator firmware goes to `.pio/build/wokwi/`.
4. The first time, press `F1`, run **Wokwi: Request a New License**, and follow the browser prompt. The license is free.
5. Open `diagram.json` and press `F1`, then **Wokwi: Start Simulator**.
6. Click inside the Wokwi terminal at the bottom of the simulator tab to type keys.

After you change the code, run `pio run -e wokwi` again and restart the simulator.

`diagram.json` sets `"serialMonitor": { "display": "terminal", "convertEol": true }`, so the Wokwi terminal handles typed keys and line endings properly. The firmware also ends every line with CRLF, so other terminals (`pio device monitor`, PuTTY, screen) show it correctly too.

Headless run (optional): set `WOKWI_CLI_TOKEN` (from https://wokwi.com/dashboard/ci), then run

```
wokwi-cli --timeout 5000 --expect-text "Ishara Glove" .
```

## Automated calibration test

`test/calibration.test.yaml` is a [wokwi-cli scenario](https://docs.wokwi.com/wokwi-ci/automation-scenarios). It boots the `wokwi` build, checks the banner says `NOT CALIBRATED`, sends `c`, and for each step moves the controls with `set-control` and sends `y`:

- step 1: all five finger sliders to `position: 0`, MPU left at rest (accel 0, 0, 1 g), so the gyro bias is 0 and there is no "hand moved" warning
- step 2: all five sliders to `position: 1`
- step 3: `accelY` +1 / `accelZ` 0 during the countdown (palm left, +90°), then `accelY` −1 when capture starts (palm right, −90°)

It passes when it sees `===== CALIBRATION REPORT =====` and then a `#CAL {...}` line containing `"gyro_bias_raw":` after sending `j`.

```
export WOKWI_CLI_TOKEN=...        # from https://wokwi.com/dashboard/ci
pio run -e wokwi
wokwi-cli --timeout 60000 --scenario test/calibration.test.yaml .
```

The run takes about 20 s of simulated time. The exit code is 0 on success and non-zero on a timeout or failure.

## BLE

The BLE protocol is defined in [`docs/BLE-CONTRACT.md`](../../docs/BLE-CONTRACT.md) at the repo root (v1). That file is the spec; this section only lists what the firmware adds or chooses. The library is NimBLE-Arduino 1.4 (`lib_deps` in `platformio.ini`, downloaded on the first build).

- The glove advertises as `Ishara-XXXX` from boot (the banner shows the name). Serial keeps working as before while BLE is connected; both can be used at the same time.
- DATA frames carry the same raw samples as the serial stream, every sample, even while the serial stream is off or the serial calibration wizard is running. The BLE `seq` is 16-bit; the serial `seq` is its low 8 bits, so the two match.
- Serial prints `# BLE connected`, `# BLE disconnected, advertising` and `# BLE command <CMD>` for each command, which helps when testing with nRF Connect.
- `#BAT` is sent when the app subscribes to EVENT (a line sent before that would be lost), then on every change. `#MPU FAIL` is sent at the same moment if the MPU-6050 is missing.
- **App calibration** (`CAL OPEN` / `FIST` / `TURN`): capture starts as soon as the command arrives (no countdown, the app shows its own). `#CALSTEP <step> FAIL <reason>` reasons: `MOVED` (gyro std dev over 3 °/s during OPEN or FIST, same limit as the serial warning), `RANGE` (TURN under 30°), `MPU` (no MPU-6050 for OPEN or TURN, after `#MPU FAIL`), `CANCELLED` (`CAL CANCEL` during the step). `#FLEX WEAK <i>` lines come right before the OPEN/FIST reply, once both steps are done. TURN lasts 3 s over BLE (4 s in the serial wizard).
- Only one calibration runs at a time: `CAL <step>` while the serial wizard runs (or while another step captures) gets `#ERR CAL BUSY`; pressing `c` while an app step captures prints a busy message. Pressing `c` or `r` drops the app's unsaved steps, and so does a disconnect.
- Other `#ERR` reasons: `#ERR STREAM ARG` (not `0`/`1`), `#ERR CAL UNKNOWN` (unknown step), `#ERR CAL NVS` (saving failed).
- Commands are trimmed and upper-cased before parsing, so `stream 1\r\n` from a terminal app works too.

## Pins

Same GPIOs on both boards. All analog inputs are on ADC1, so they keep working while the radio (BLE) is on.

| Signal | GPIO | DevKitC-1 pin | XIAO ESP32-S3 pin |
|---|---|---|---|
| Thumb / index flex | 1 / 2 (ADC1) | J3-4 / J3-5 | D0 / D1 |
| Middle / ring / pinky flex | 3 / 4 / 7 (ADC1) | J1-13 / J1-4 / J1-7 | D2 / D3 / D8 |
| MPU-6050 SDA / SCL (addr 0x68, AD0 to GND) | 5 / 6 | J1-5 / J1-6 | D4 / D5 |
| Battery sense (220k/220k divider) | 8 (ADC1) | J1-12 | D9 |

## Why slide pots stand in for flex sensors

A flex sensor is a variable resistor. On the glove each one sits in a voltage divider with a fixed resistor, and the ADC reads the midpoint. A potentiometer is a divider too, and its wiper is the midpoint. So a slide pot (ends on 3V3 and GND, wiper on the ADC pin) produces exactly the kind of signal the firmware will see.

Real values:

| Sensor | Flat | Bent | Fixed resistor |
|---|---|---|---|
| 4.5" (index to pinky) | ~10k | ~20k | 15k |
| 2.2" (thumb) | ~25k | ~100k | 47k |

On the real circuit, **bending makes the voltage go down**. The firmware doesn't assume a direction. Calibration stores `open` and `fist` for each finger, and normalization uses `(raw - open) / (fist - open)`, so either direction works. In the simulator you can bend by moving a slider either way.

## Serial output

- **Raw stream** (on at boot in the hardware build, off in the `wokwi` build; 50 Hz): `seq,f0,f1,f2,f3,f4,ax,ay,az,gx,gy,gz`. `seq` is a uint8 that wraps. Flex values are 0–4095 (average of 8 reads). IMU values are raw int16 (±4 g, ±500 °/s).
- **Normalized stream** (`n`): `N,f0,f1,f2,f3,f4,roll,gx,gy,gz`. Fingers run 0 (open) to 1 (fist), clamped. Roll is in degrees relative to the neutral roll from step 1 (open hand). Gyro is in °/s with the bias removed.
- **Everything else** starts with `#`, so `record.py` and `live.py` ignore it. Apart from the `#CAL` JSON line, text lines contain no commas. While a stream is on, `# BAT xx% (mV)` appears every 10 s.
- Every line ends with CRLF (`\r\n`). The 12 fields are unchanged; strip the line (Python's `line.strip()`) before splitting if a tool doesn't already.
- Streams and the status line **pause while calibration runs**, so the prompts stay readable. `seq` keeps counting, so the tools will see a gap.

### Boot banner

```
# ========================================
# Ishara Glove - firmware v0.3.0 (Wokwi simulation build)
# ========================================
# Board        devkit
# MPU-6050     OK
# Calibration  NOT CALIBRATED - press c
# Battery      82% 4010 mV (analogReadMilliVolts)
# Raw stream   OFF at boot (s toggles)
# BLE          off (simulation build)
# Keys: ...
```

The board is `devkit` or `xiao` (`BOARD_NAME` in `board.h`). The build type is "hardware" or "Wokwi simulation", and the calibration line says `loaded (format v2)` (or `v1` for an older one) when NVS has a calibration.

### Status line

When no stream is on and calibration isn't running, one line prints every second:

```
# BAT 82% 4010 mV | CAL ok | Thumb 0   0% | Index 2047  50% | ... | roll 3.2 deg (rel 3.2)
```

- `BAT 82% 4010 mV`: battery percentage and voltage. The ADC method in use is shown in the banner and the report (see [Battery](#battery)).
- `CAL ok` or `NOT CALIBRATED`.
- Each finger's raw ADC value (0–4095). When calibrated, it's followed by the bend: 0% is the `open` value and 100% is the `fist` value, clamped.
- `roll`: filtered roll in degrees. When calibrated, `rel` is the roll relative to the neutral roll from step 1. It shows `n/a (no MPU)` if the MPU-6050 isn't answering.

The status line stops as soon as you press `c`, `s` or `n`, and comes back when calibration finishes or both streams are off again.

### Calibration report (`p`, and after the last `y`)

```
# ===== CALIBRATION REPORT =====
# Firmware 0.3.0  uptime 0:00:27
# Battery 82% (4010 mV via analogReadMilliVolts)
# MPU-6050 OK
# Calibration format v2
# Steps 1+2  finger medians (raw ADC)
# Finger    open   fist  range  flag
# Thumb        0   4095   4095  ok
# ...
# Step 1    gyro bias deg/s  x 0.00  y 0.00  z 0.00
# Step 1    neutral roll 0.0 deg
# Step 3    roll deg  min -86.8  max 85.5  range 172.3  ok
# ===== END REPORT =====
```

- **open / fist**: raw medians from steps 1 and 2. **range** = fist − open. It is negative on the real glove, where bending lowers the voltage.
- **flag** `LOW`: |range| is under 300 counts, so the sensor didn't bend or is disconnected. The roll line is flagged `LOW` if the range is under 30°.
- **Gyro bias**: the mean gyro reading during step 1 (the hand is held still there), in °/s. It is subtracted before the roll filter integrates.
- **Neutral roll**: the accelerometer roll during step 1. **min / max**: from step 3.
- **Calibration format v2**: the version of the saved data (`CAL_VERSION` in `config.h`). New calibrations are always saved as v2. A v1 calibration (from the old 4-step flow) has the same fields, so it still loads and the report says `Calibration format v1 (loaded)`; press `c` to replace it with a v2 one. Any other version is ignored at boot.
- **uptime** is the time since boot when the report was printed.

If there is no calibration, the report shows `NOT CALIBRATED` in place of the table.

After each step, a small table shows just that step's result: per-finger open medians plus gyro bias, gyro std dev and gravity per axis and the neutral roll (step 1), fist medians with open, range and flag (step 2), or roll min / neutral / max / range (step 3).

### `#CAL` JSON line (`j`)

`j` prints the saved calibration as one line, so you can copy it into the app or the AI tools:

```
#CAL {"fw":"0.3.0","v":2,"open":[0,0,0,0,0],"fist":[4095,4095,4095,4095,4095],"gyro_bias_raw":[0.00,0.00,0.00],"roll_neutral":0.00,"roll_min":-86.80,"roll_max":85.50,"gyroBias":[0.00,0.00,0.00],"gravity":[0.00,0.00,8192.00],"rollNeutral":0.00,"rollMin":-86.80,"rollMax":85.50,"gyroLsbPerDps":65.5,"accelLsbPerG":8192}
```

The app and the AI tools read the contract keys `v`, `open`, `fist`, `gyro_bias_raw`, `roll_neutral`, `roll_min`, `roll_max` (`docs/BLE-CONTRACT.md` section 6). `gyroBias`, `rollNeutral`, `rollMin`, `rollMax` are copies with the same values, kept for older readers. Finger order is thumb, index, middle, ring, pinky. `open` / `fist` are raw ADC counts. `gyro_bias_raw` / `gyroBias` and `gravity` are raw IMU counts, in the same units as the raw stream; divide by `gyroLsbPerDps` or `accelLsbPerG` to get °/s or g. Roll values are in degrees. `v` is the calibration format version (2 for anything saved by this firmware, 1 for an older calibration still loaded from NVS). Take everything after `#CAL `. If there is no calibration, `j` prints `# NOT CALIBRATED - nothing to export`.

## Keys

| Key | Action |
|---|---|
| `c` | Start full calibration (press it again during calibration to restart from step 1) |
| `y` / `x` | Accept / redo the step just captured |
| `q` | Cancel calibration and keep the previous one |
| `s` | Raw stream on/off |
| `n` | Normalized stream on/off (needs a calibration) |
| `p` | Print the calibration report (works any time outside calibration) |
| `j` | Print the saved calibration as one `#CAL {json}` line |
| `r` | Reset (erase) calibration |
| `h` | Help |

## Walking through calibration in Wokwi

Press `c`. There are three steps, in the same order as the app's Calibrate screen. Each step shows a prompt, a 3-2-1 countdown, a capture window with live `#` progress bars, and a result. Then press `y` to accept or `x` to redo. Click the MPU-6050 in the diagram to get its sliders (accelX/Y/Z in g, rotationX/Y/Z in °/s).

1. **Open hand (2 s).** Before `GO`, set the five finger sliders to one end (for example, all the way left). Leave them, and the MPU, still during capture. Each finger's median is saved as `open`. Because the hand is held still here, this step also measures the gyro bias (mean gyro) and the neutral roll (mean accelerometer roll). The default MPU values (accel 0,0,1 g, rotation 0) give a bias of 0 and a neutral roll of 0°. To test bias removal, set rotationX to 5 °/s before `GO`; the result shows a bias of about 5. If the gyro std dev on any axis is above 3 °/s (`CAL_STILL_GYRO_STD_DPS` in `config.h`), you'll see `# WARN hand moved during open-hand step, gyro bias may be off - press x to redo`. Try it by dragging a rotation slider during capture.
2. **Fist (2 s).** Move all five sliders to the other end before `GO`. If any finger differs from `open` by less than 300 counts, you'll see a `WARNING … not bending or disconnected`. Try it by leaving one slider where it was.
3. **Turn the wrist (4 s).** Palm left, then palm right. Min and max roll are saved; the neutral roll comes from step 1. Roll = `atan2(ay, az)`, fused with the X gyro. Palm left means roughly accelY = +1 and accelZ = 0 (about +90°). Palm right means accelY = −1 (about −90°). During the 4 s capture, drag **accelY** from about +0.8 to about −0.8. The filter follows the accelerometer with about 1 s lag, so move steadily rather than jumping at the last moment. If the range is under 30°, you'll get a warning; press `x` to redo.

After the last `y`, the calibration is saved to NVS and the full calibration report is printed. Press `n` to see normalized values react to the sliders. The simulator starts with blank flash every time, so expect `# NOT CALIBRATED` after each restart. On real hardware the calibration survives reboots.

If you delete the MPU-6050 (or its SDA wire) from the diagram, you'll see `MPU-6050 NOT FOUND` at boot and a warning in steps 1 and 3.

## Battery

Charging isn't simulated. Wokwi has no Li-Po or charger, and charging needs no code. Only the reading is implemented. GPIO 8 reads the midpoint of a 220k/220k divider, and the firmware multiplies it by 2. 3300 mV is 0% and 4150 mV is 100%. In Wokwi, the **Battery (sim)** slider *is* that midpoint, so 1650–2075 mV on the pin covers 0–100%. The default slider value is 620/1023, which gives about 4.0 V (about 82%).

Each reading takes both `analogReadMilliVolts()` (uses the chip's ADC calibration) and `analogRead()` scaled to 3.3 V. The firmware uses `analogReadMilliVolts()` unless it is impossible (over 3300 mV) or more than 250 mV from the scaled raw value. In that case it falls back to the scaled raw reading. That can happen in the simulator, which may not model the ADC calibration. The banner and report name the method in use (`analogReadMilliVolts` or `analogRead scaled to 3.3 V (fallback)`). The status line shows only the voltage.

Each reading averages 16 samples. Every 0.5 s the battery voltage sets a state, printed as one line at boot and whenever it changes:

- `#BAT NO_BATTERY (USB)`: under 2.5 V. No battery on the divider (a Li-Po's protection cuts off long before that), so the board runs from USB. It never sleeps or shuts down in this state.
- `#BAT LOW 3.38V`: 2.5–3.40 V for 5 s in a row. It returns to OK only above 3.50 V.
- `#BAT OK 3.92V 78%`: above 3.40 V.

The thresholds and the 5 s debounce are in `config.h` (`BAT_NONE_MV`, `BAT_LOW_MV`, `BAT_LOW_HYST_MV`, `BAT_LOW_DEBOUNCE_MS`). The CSV streams don't change.

The battery code is the same on both boards. It only reads the divider on GPIO 8 and never looks at the charger. On the DevKit build the charger is our TP4056 + boost circuit; on the XIAO it is the board's own charger on the BAT pads.
