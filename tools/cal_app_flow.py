#!/usr/bin/env python3
"""Ishara glove: run the APP's calibration flow over BLE (docs/BLE-CONTRACT.md section 7).

Sends exactly what the Flutter app sends, in the same order and with the same timeouts:
    CAL OPEN (2 s) -> CAL FIST (2 s) -> CAL TURN (3 s) -> CAL SAVE -> #CAL {json}
It does NOT use the USB-serial 'c' wizard (that one has a countdown and a 4 s TURN).

    pip install -r tools/requirements.txt         # bleak
    python cal_app_flow.py                         # first device named Ishara-XXXX
    python cal_app_flow.py --name Ishara-3FA2

Ctrl+C at any time sends CAL CANCEL (unsaved steps are dropped, the stored calibration stays).
"""
import argparse
import asyncio
import json
import sys

from bleak import BleakClient, BleakScanner

SERVICE = "6e1a0001-7b5c-4f3a-9a62-1d2c3b4a5f60"
CMD = "6e1a0003-7b5c-4f3a-9a62-1d2c3b4a5f60"
EVENT = "6e1a0004-7b5c-4f3a-9a62-1d2c3b4a5f60"
INFO = "6e1a0005-7b5c-4f3a-9a62-1d2c3b4a5f60"

REPLY_TIMEOUT = 1.5  # same margin as the app (glove_client.dart replyTimeout)
STEPS = [
    # (wire name, capture seconds, what to do)
    ("OPEN", 2, "Open your hand flat, fingers straight, and keep it STILL"),
    ("FIST", 2, "Make a fist and keep it STILL"),
    ("TURN", 3, "Turn your wrist left and right (palm left <-> palm right)"),
]
FINGERS = ["thumb", "index", "middle", "ring", "pinky"]


class Events:
    def __init__(self):
        self.buf = b""
        self.lines = asyncio.Queue()

    def on_event(self, _, data: bytearray):
        self.buf += bytes(data)
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            text = line.decode("utf-8", "replace").strip()
            if text:
                self.lines.put_nowait(text)

    def drain(self):
        while not self.lines.empty():
            self.lines.get_nowait()

    async def wait(self, prefix, timeout):
        """Return the first line starting with prefix; print every other line seen meanwhile."""
        loop = asyncio.get_running_loop()
        end = loop.time() + timeout
        while True:
            left = end - loop.time()
            if left <= 0:
                return None
            try:
                line = await asyncio.wait_for(self.lines.get(), left)
            except asyncio.TimeoutError:
                return None
            if line.startswith(prefix) or line.startswith("#ERR CAL") or line == "#MPU FAIL":
                if line == "#MPU FAIL":
                    print("  glove: #MPU FAIL (MPU-6050 not responding)")
                    continue
                return line
            if line.startswith("#FLEX WEAK"):
                i = int(line.split()[-1])
                print(f"  WARNING #FLEX WEAK {i}: the {FINGERS[i]} sensor barely changed between open and fist")
            elif not line.startswith("#BAT"):
                print(f"  glove: {line}")


async def send(client, cmd):
    print(f"  -> {cmd}")
    await client.write_gatt_char(CMD, cmd.encode(), response=True)


async def ask(prompt):
    return (await asyncio.to_thread(input, prompt)).strip().lower()


async def main(args):
    print("Scanning for the glove (10 s)...")
    if args.name:
        dev = await BleakScanner.find_device_by_name(args.name, timeout=10)
    else:
        dev = await BleakScanner.find_device_by_filter(
            lambda d, ad: (d.name or ad.local_name or "").startswith("Ishara-"), timeout=10)
    if not dev:
        print("No Ishara glove found. Is it powered, advertising, and not connected to a phone?")
        return 1
    print(f"Found {dev.name} ({dev.address})")

    ev = Events()
    async with BleakClient(dev) as client:
        info = json.loads(await client.read_gatt_char(INFO))
        print(f"INFO fw {info.get('fw')} board {info.get('board')} proto {info.get('proto')}")
        if info.get("proto") != 1:
            print("proto != 1: app and firmware don't match. Stopping.")
            return 1
        await client.start_notify(EVENT, ev.on_event)
        await asyncio.sleep(0.5)  # #BAT / #MPU FAIL arrive right after subscribing

        ev.drain()
        await send(client, "GETCAL")
        cur = await ev.wait("#CAL", REPLY_TIMEOUT)
        print(f"  stored now: {cur}\n")

        try:
            i = 0
            while i < len(STEPS):
                name, secs, what = STEPS[i]
                print(f"Step {i + 1} of 3: {what}.")
                await ask(f"  Get into position, then press Enter (capture = {secs} s)... ")
                ev.drain()
                await send(client, f"CAL {name}")
                print(f"  capturing {secs} s, hold it...")
                reply = await ev.wait("#CALSTEP", secs + REPLY_TIMEOUT)
                if reply is None:
                    print("  no reply from the glove (timeout).")
                elif reply == f"#CALSTEP {name} OK":
                    print(f"  OK {name}\n")
                    i += 1
                    continue
                else:
                    print(f"  {reply}")
                    if reply.endswith("MOVED"):
                        print("  Your hand moved: keep it still for the whole capture.")
                    elif reply.endswith("RANGE"):
                        print("  The wrist turned less than 30 degrees: turn it further.")
                    elif reply.endswith("MPU"):
                        print("  The MPU-6050 is not responding: check SDA GPIO5 / SCL GPIO6.")
                    elif "BUSY" in reply:
                        print("  The glove is busy (serial 'c' wizard running?).")
                if await ask("  Try this step again? [Y/n] ") == "n":
                    raise KeyboardInterrupt
            ev.drain()
            await send(client, "CAL SAVE")
            saved = await ev.wait("#CAL", REPLY_TIMEOUT + 1)
            if not saved or not saved.startswith("#CAL {"):
                print(f"Save failed: {saved}")
                return 1
            cal = json.loads(saved[5:])
            print("\nSAVED. #CAL line (send this for review):")
            print(saved)
            print("\nSummary:")
            for f in range(5):
                o, s = cal["open"][f], cal["fist"][f]
                flag = "  <-- WEAK (< 300)" if abs(s - o) < 300 else ""
                print(f"  {FINGERS[f]:6} open {o:5}  fist {s:5}  range {abs(s - o):5}{flag}")
            print(f"  roll neutral {cal['roll_neutral']:.1f}  min {cal['roll_min']:.1f}"
                  f"  max {cal['roll_max']:.1f}  range {cal['roll_max'] - cal['roll_min']:.1f} deg")
            print(f"  gyro bias raw {cal['gyro_bias_raw']}")
            return 0
        except (KeyboardInterrupt, asyncio.CancelledError):
            print("\nCancelled: sending CAL CANCEL (the stored calibration is unchanged).")
            ev.drain()
            await send(client, "CAL CANCEL")
            await ev.wait("#OK CAL", REPLY_TIMEOUT)
            return 1


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--name", help="device name, e.g. Ishara-3FA2 (default: first Ishara-*)")
    try:
        sys.exit(asyncio.run(main(p.parse_args())))
    except KeyboardInterrupt:
        sys.exit(1)
