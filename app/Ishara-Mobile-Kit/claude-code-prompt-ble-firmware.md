I'm working on the Ishara glove firmware (ESP32-S3-DevKitC-1, Arduino/PlatformIO). Today the glove talks only over USB serial: a 12-field CSV line per sample at 50 Hz (`seq,f0..f4,ax,ay,az,gx,gy,gz`), `#` status lines, and single-letter commands (`s` toggles the stream, `c` runs the 3-step calibration, `j` prints `#CAL {json}`, `p` prints a report). There is no BLE code yet.

Add BLE so the mobile app can do everything over Bluetooth. The app team is already building against a fixed contract, so **implement `BLE-CONTRACT.md` exactly** (I'm putting it in the repo as `docs/BLE-CONTRACT.md`; read it fully before writing code). Do not invent UUIDs, field orders, command names or reply texts: copy them from the contract.

Steps:

1. First, read the firmware and show me how the code is organized: where sensors are sampled (and whether a timer drives the 50 Hz), where the CSV line is printed, how commands are read, and how calibration works (the `c` flow, where open/fist/gyro bias/roll are stored, how `#CAL` is built). Tell me your plan before changing anything.

2. Use **NimBLE-Arduino** (lighter than the stock Bluedroid BLE library). Add it to `platformio.ini`.

3. Implement, following the contract section by section:
   - Advertising name `Ishara-XXXX` from the MAC; one connection at a time; restart advertising after disconnect; stop streaming on disconnect.
   - The service and the 4 characteristics with the contract's UUIDs and properties. INFO returns the JSON from section 2 (put the firmware version in one constant). Fill `"board"` from `BOARD_NAME` in `include/board.h` (it already exists: `devkit` / `xiao`). BLE must work the same in both `pio run -e devkit` and `pio run -e xiao`.
   - Request MTU 247 and a 15–30 ms connection interval on connect.
   - DATA: binary frames, little-endian, `ver`=1, `n`=min(5, ⌊(MTU−7)/22⌋), 16-bit `seq` of the first sample, 11 raw int16 values per sample in the contract's order. **The values must be the same raw numbers the serial line prints for that sample**: take them from the same sampling point, don't sample twice.
   - Sampling stays timer-driven at 50 Hz. Building and sending frames must never delay sampling. Use a small queue or ring buffer between the sampling code and BLE, and if BLE can't keep up, drop whole frames (the app detects gaps with `seq`) rather than blocking.
   - CMD: parse the text commands of section 5. Reply with exactly one EVENT line per command, as specified.
   - EVENT: `\n`-terminated lines, split into several notifications when longer than MTU−3.
   - Calibration over BLE (section 7): `CAL OPEN`, `CAL FIST`, `CAL TURN`, `CAL SAVE`, `CAL CANCEL`. **Reuse the existing calibration code** (same measurements, same stored result, same gyro-bias-during-OPEN rule), just driven step by step by commands instead of by the serial flow. Add the FAIL checks with clear reasons (hand moved during OPEN/FIST, not enough wrist rotation in TURN, finger range < 300 → also send `#FLEX WEAK <i>`).
   - `#BAT` lines on connect, on battery state change, and on `BAT`, using the existing battery state code (NO_BATTERY / LOW / OK).
   - `#MPU FAIL` if the MPU-6050 doesn't answer.

4. Keep the USB serial interface exactly as it is (lines, commands, `c` flow, `#CAL` format). The Python tools (`glove.py`, `record.py`, `live.py`) must keep working unchanged. Serial and BLE can both be active at the same time.

5. Put all BLE constants (UUIDs, name prefix, MTU, samples per frame, proto version) in one header, e.g. `include/ble_contract.h`, with a comment pointing to `docs/BLE-CONTRACT.md`.

6. Don't change anything else: pins, sampling rate, sensor reading, normalization, the CSV format, the battery logic.

When you're done:
- show me the diff and make sure `pio run -e devkit` and `pio run -e xiao` both build with no new warnings;
- report flash and RAM use before and after;
- add a short `docs/BLE-TESTING.md` explaining how to test with **nRF Connect** on a phone, step by step: find `Ishara-XXXX`, read INFO, subscribe to EVENT and DATA, write `GETCAL`, `STREAM 1`, the calibration commands, `PING`; what each reply should look like; how to check a DATA frame by hand (byte 0 = 01, byte 1 = 05, then seq, then 11 int16 values);
- add a small Python script `tools/ble_check.py` using the `bleak` library that connects, does the contract's setup sequence, streams for 10 seconds and prints: frames per second (expect 10), samples per second (expect 50), lost samples (from `seq`), and the first decoded sample next to the serial line format, so we can compare it with the USB output.
