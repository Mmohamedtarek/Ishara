# Windows 11 conversion: changes and verification

Date: 2026-10-11. Machine: Windows 11 Pro, Python 3.12.10, venv `.venv` (TF 2.21, CPU only).
Backup of the project before any change (without `.venv`): `E:\Ishara-AI-v3-2_backup_before_windows`.
All checks ran in temporary copies under `E:\Ishara-AI-v3-2_wintest\` (logs in `...\logs\`, one line per run in `runs.tsv`).
The project folder's shipped models, `decider.json`, `labels.txt` and `data/` were never written (MD5 check at the end).

The known bugs from the earlier test report (gyro_bias vs gyro_bias_raw, uint8 seq, stale RF / data) were **not** touched.

## Files changed and why

| File | Change |
|---|---|
| `common.py` | New `setup_console()`: reconfigures stdout/stderr/stdin to UTF-8 (`errors="replace"`), so Arabic output never raises `UnicodeEncodeError` on a cp1252/cp1256 console or pipe. New `show_help(doc)` for scripts without argparse. `save_calib` writes LF (`newline="\n"`). |
| `glove.py` | `find_port`: ESP32-S3 by VID 0x303A, then CP210x (0x10C4) / CH340-CH343 (0x1A86) by VID, then any port whose description **or hwid** contains "USB" (case-insensitive; Windows driver names like `USB-SERIAL CH340 (COM7)`, `USB Serial Device (COM5)`), then the old "only one port" fallback, which now skips Windows built-in ports (`PCI\`, `ACPI\`, `BTHENUM\` hwid, Bluetooth). Error messages list ports with descriptions and show COM5 + Device Manager and `/dev/ttyACM0`. `open_glove` turns `SerialException` (port busy / missing) into a clear message instead of a traceback. Protocol unchanged. |
| `record.py` | `encoding="utf-8"` on the CSV opens (still `newline=""`, see decisions). `ask()` wraps `input()`: Ctrl+C / EOF at the prompt = quit cleanly. Ctrl+C during a countdown/take exits with a message, no traceback (the file is closed by `with`). `--help` exits 0. |
| `live.py` | Windows TTS rewritten: one persistent `powershell` process reads one line per word from stdin (UTF-8) and speaks it; text is never put inside the command, so quotes/apostrophes are safe; restarted automatically if it dies. Linux path (espeak-ng / espeak / spd-say) unchanged. File handles closed (`with`). Ctrl+C / EOF while loading or during the quick calibration exits cleanly. |
| `simulate_data.py` | `write_take` opens with `encoding="utf-8", newline="\n"` (CSV now LF on Windows). `--help`. |
| `mine_negatives.py` | `to_csv(..., encoding="utf-8", lineterminator="\n")` (pandas defaults to `os.linesep` = CRLF on Windows). |
| `train_cnn.py` | `labels.txt` written with `encoding="utf-8", newline="\n"`; `.tflite` writes use `with`. `--help` (before, `train_cnn.py --help` started a training). |
| `train_rf.py` | `--help` (before, it started a ~45 min training and overwrote the model). |
| `eval_live.py` | `--tune` reads/writes `decider.json` with `with` and LF. |
| `build_kit.py` | All mock/test/model files written through `write_text` / `write_json` (UTF-8, LF, closed handles), so the kit is byte-identical on Windows and Linux. `--help` (before, it created a folder named `--help`). |
| `run_pipeline.py` (new) | The pipeline steps, one source of truth for both OSes. Same steps, order and output filtering as the old `.sh` (`tail -9` for train_rf, `grep -E "الدقة|KB|labels"` for train_cnn, `KB` for members 2/3). Stops at the first failing step, prints the last 60 unfiltered lines and exits with that code. Runs in its own folder, uses `sys.executable`, optional `--kit`. |
| `run_pipeline.ps1` (new) | Thin Windows wrapper: `.venv\Scripts\python.exe run_pipeline.py @args`. UTF-8 with BOM + CRLF so Windows PowerShell 5.1 reads the Arabic text correctly. |
| `run_pipeline.sh` | Now a thin wrapper: `exec "${PY:-python}" run_pipeline.py "$@"` (LF). |
| `README.md` | New "التسطيب على Windows 11 (PowerShell)" section: Python 3.12 64-bit, venv activation, ExecutionPolicy, Device Manager / COM port, CP210x and CH34x drivers, Windows Terminal, ASCII-only path. Pipeline usage (`.ps1` / `.sh` / `.py`), deleting `data` on both OSes, training commands one per line (PowerShell 5.1 has no `&&`), `--port` examples for both OSes. Ubuntu section kept. |
| `requirements.txt` | Comment: Python 3.12 64-bit; TF is CPU-only on Windows. No new dependency. |

## Decisions

1. **Console fix = `reconfigure` in each entry point**, called in `if __name__ == "__main__":` (not on import, so tests/libraries importing `common` are not affected). stdin is reconfigured too, so Arabic typed into `input()` works through pipes.
2. **`--help` for the four scripts without argparse** (`simulate_data`, `train_rf`, `train_cnn`, `build_kit`): before, `--help` ran them (regenerated data / retrained / made a `--help` folder). Required for verification step 1; it only triggers on `-h`/`--help`.
3. **`record.py` CSV keeps `newline=""` + `csv.writer`**, which writes CRLF rows **on Linux too**. That is already byte-identical between OSes and is the existing data format, so I did not change it (rule 3).
4. **TTS: persistent PowerShell instead of pyttsx3** — built-in, no new dependency, so no separate fallback is needed. If the process dies it is restarted (tested by killing it). On exit, PowerShell finishes the words already sent, then quits when stdin closes.
5. **`run_pipeline.sh` became a wrapper** for one source of truth. Behavior change on Linux too: the old `.sh` did **not** stop on training failures (`| tail -9` without `pipefail`, and `|| true` after grep); now it stops. Requested ("don't hide training errors").
6. **`find_port` single-port fallback skips Windows built-in ports**: on this PC the only port is `COM3` = Intel AMT Serial-over-LAN; the old code opened it and said "glove connected but no data". The glove is always USB (ESP32-S3 has no Bluetooth Classic SPP). Linux ports (`/dev/ttyS0`, hwid `PNP0501`) are not filtered, so Linux behavior is unchanged.
7. **Line endings of edited sources: LF**, the same as before (all project text files were already LF; I first misread a grep and briefly thought they were CRLF). Only `run_pipeline.ps1` is CRLF + BOM.
8. **TensorFlow SavedModel export path left unchanged**: relative paths work on Windows, and TF 2.21 uses `from_keras_model` (no `*_savedmodel` folder was created in any run). The problem I did find is **non-ASCII paths**: `tf.lite.Interpreter` can't open a `.tflite` file in a folder with Arabic characters (`ValueError: Could not open ...`; `.keras` loads fine). I documented this in the README instead of changing model-loading code.
9. `build_kit.py` default `../Ishara-Mobile-Kit` left as is (Python accepts `/` on Windows). `run_pipeline.py` resolves its default next to the project folder, so it works from any working directory.

## Verification (Windows 11, venv Python, PYTHONUTF8 / PYTHONIOENCODING removed, output redirected to files = the case that crashed)

| # | Check | Before (original code) | After | Result |
|---|---|---|---|---|
| 1 | `--help` / usage of every script | record, live, eval_live, mine_negatives: **UnicodeEncodeError (cp1252)**, exit 1 | all 13 commands run; `--help` exit 0 (`record.py` with no args exits 1 with usage, as before) | PASS |
| 1b | Real console window (conhost), `live.py --sim --fast --mute` | exit 0 | exit 0 | PASS |
| 1c | Arabic-locale Windows simulated (stdout cp1256) | **UnicodeEncodeError** (🗣 / ✗ / ← not in cp1256) | exit 0 | PASS |
| 1d | `input()` with Arabic prompt + Arabic answer through pipes | UnicodeEncodeError | `'أحمد'` read back | PASS |
| 2 | `simulate_data.py` | 34 files, all CRLF | 34 files, **0 CR**; equal to before after CRLF→LF (34/34); byte-identical to shipped Linux `data/` for 32/34 | PASS (see note A) |
| 3 | `live.py --sim --fast --mute` | (needs PYTHONUTF8) | exit 0, 15/15 or 16 words as usual (random person each run) | PASS |
| 3b | `live.py --sim --fast` with sound | piped: crash, 0 words | exit 0, 15 words spoken, **1** speech PowerShell process | PASS |
| 3c | TTS, 5 words incl. `it's` | **5** PowerShell processes; `it's` = PowerShell parse error, silently not spoken | **1** process, quotes/`$()`/backtick spoken literally, exit 0 | PASS |
| 4 | `eval_live.py --hours 1` | WER 8.8% (S7 D26 I4 / 419), 0 false words, latency 2.00 s, flicker 0.0166/min, single sign 96.1%, tilt 96.2%, broken sensor 87.1%, fast 95.5% | **identical** (only the elapsed-time line differs: 120 s vs 126 s) | PASS |
| 5 | `train_rf.py` | — | exit 0, LOPO 94.3% (same as the earlier report), 2,653 s under load | PASS |
| 5b | `train_cnn.py` (quick) | — | exit 0, p9 94.7%, `.keras` + `.tflite` 159.7 KB + int8 55.2 KB, `labels.txt` LF and byte-identical to the shipped one; 1,017 s | PASS |
| 6 | `build_kit.py <temp>` | 96 files, 91 text files CRLF | 96 files, **0 CR**; 91 text files equal to before after CRLF→LF, 5 binaries byte-identical; same report (88 mocks, same 9 mismatches, 302 retries, gaps 2787/24) | PASS |
| 7 | `run_pipeline.ps1` end to end (with `-ExecutionPolicy Bypass`) | — | exit 0 in 6,905 s (1 h 55 min, sharing CPU with other checks); kit 93 text files + data 74 text files, 0 CR | PASS (see note B) |
| 7b | Pipeline stops on failure (stub train_cnn raising ValueError) | old `.sh`: `\|\| true` continues | stops at train_cnn, full traceback shown, exit 1, later steps not run | PASS |
| 8 | No glove: `record.py water ahmed`, `record.py calib ahmed`, `live.py --mute` | opened COM3 (Intel AMT) → "connected but not sending data" (misleading) | "مش لاقي الجلوف. البورتات الموجودة: COM3 (Intel(R) Active Management Technology - SOL (COM3))" + help, no traceback | PASS |
| 8b | Bad port `--port COM99` / `record.py ... COM99` | **SerialException traceback** | clear Arabic message with the reason, no traceback | PASS |
| — | 24 unit checks (find_port with ESP32-S3 / CP210x / CH340 / CH343 / FTDI / AMT / COM1 / Bluetooth / Linux lists, setup_console, show_help, ask, LF writers) | — | 24/24 | PASS |
| — | Earlier pytest suite (68 tests) on the converted copy | 68 passed | 68 passed | PASS |
| 9 | MD5 of shipped models, `decider.json`, `labels.txt`, `data/` in the project folder (86 files) | — | all unchanged | PASS |

**Pipeline numbers (7)**, converted code vs the earlier run of the original code (Git Bash + PYTHONUTF8, from the previous test report):

| | before | after |
|---|---|---|
| RF round 0 / 1 / 2 | 95.2 / 94.5 / 94.5% | 95.2 / 94.7 / 94.7% |
| CNN round 0 / 1 / 2 (1 test person) | 94.9 / 94.6 / 96.0% | 93.0 / 95.4 / 93.0% |
| mined "other" takes round 1 / 2 | 1546 / 246 | 1478 / 230 |
| sentence WER (30 h) | 9.5% | 7.6% |
| false words in 30 h | 1 (five) | 1 (five) |
| flicker / min | 0.0194 | 0.0200 |
| single sign / tilt 30° / broken sensor / fast | 94.8 / 96.0 / 87.4 / 94.3% | 95.7 / 96.8 / 86.2 / 95.1% |
| sessions 60 h: false words / WER | 5 (0.0014/min) / 11.6% | 8 (0.0022/min) / 9.9% |
| kit mocks not matching | 10/88 | 10/88 |

**Note A:** `come.csv` and `other.csv` in the shipped `data/` differ from what the current `simulate_data.py` produces **with the original code too** (byte-for-byte the same as mine). `other.csv`: 84 of 1,500 takes differ, besides the appended mined negatives. This is the stale-data issue from the earlier report, not a Windows issue.
**Note B:** The first RF result is identical because the RF uses a fixed seed. CNN training with TensorFlow on CPU is not bit-reproducible from run to run (oneDNN / thread scheduling). The earlier run of the original code differed in the same way, so the downstream numbers move within normal variation. The training code was not changed.
**Other observations:** one failure-test run crashed once with Windows status 0xC000010A before printing anything; it did not happen again in the retry, so the cause is unknown. Also, `train_cnn.py --member 2/3` prints the file name `ishara_cnn.tflite` although it writes `ishara_cnn_2.tflite` (a pre-existing cosmetic print, not changed).

## Not verified (no real glove / no Linux here)

- Real serial I/O with a glove: port auto-detection on real ESP32-S3 / CP210x / CH34x hardware (tested only with realistic fake port lists), the 2 s reset wait, `#CAL` request, Ctrl+C during `record.py wear` while blocked in `readline` (the code path is unchanged; on Windows, pyserial returns within the 0.5 s timeout and then the KeyboardInterrupt is handled).
- Driver installation steps in the README (CP210x / CH34x) are standard guidance, not tested here.
- Linux: no WSL / Linux machine here. Linux paths were kept unchanged (espeak, `/dev/tty*`, `newline` choices give identical bytes), and `run_pipeline.sh` is LF, but it was not executed on Linux.
- Audible quality of the speech: the processes ran and finished with exit 0 and the expected duration, but nobody listened.
