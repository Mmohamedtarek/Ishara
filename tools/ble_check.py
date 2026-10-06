#!/usr/bin/env python3
"""Ishara glove BLE check (docs/BLE-CONTRACT.md v1).

Runs the contract's setup sequence (section 3) against a real glove, streams for 10 s and
prints the rates and lost samples.

    pip install -r tools/requirements.txt
    python tools/ble_check.py                  # first device named Ishara-XXXX
    python tools/ble_check.py --name Ishara-3FA2
    python tools/ble_check.py --address AA:BB:CC:DD:EE:FF --seconds 30

Exit code 0 if INFO, #CAL and the stream all look right, 1 otherwise.
"""
import argparse
import asyncio
import json
import struct
import sys
import time

from bleak import BleakClient, BleakScanner

SERVICE = "6e1a0001-7b5c-4f3a-9a62-1d2c3b4a5f60"
DATA = "6e1a0002-7b5c-4f3a-9a62-1d2c3b4a5f60"
CMD = "6e1a0003-7b5c-4f3a-9a62-1d2c3b4a5f60"
EVENT = "6e1a0004-7b5c-4f3a-9a62-1d2c3b4a5f60"
INFO = "6e1a0005-7b5c-4f3a-9a62-1d2c3b4a5f60"

PROTO = 1
FRAME_VER = 1
CHANNELS = 11
SAMPLE = struct.Struct("<11h")  # f0 f1 f2 f3 f4 ax ay az gx gy gz


class Glove:
    def __init__(self):
        self.buf = b""
        self.lines = asyncio.Queue()
        self.frames = 0
        self.samples = 0
        self.lost = 0
        self.bad = 0
        self.expected = None  # next seq
        self.first = None     # (seq, values) of the first sample
        self.counting = False

    # EVENT: join bytes until "\n" (a long line arrives in several notifications).
    def on_event(self, _, data: bytearray):
        self.buf += bytes(data)
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            text = line.decode("utf-8", "replace")
            print(f"  EVENT {text}")
            self.lines.put_nowait(text)

    # DATA: ver, n, seq (uint16), then n x 11 int16, all little-endian.
    def on_data(self, _, data: bytearray):
        if not self.counting:
            return
        if len(data) < 4 or data[0] != FRAME_VER or len(data) != 4 + 22 * data[1] or data[1] == 0:
            self.bad += 1
            return
        n = data[1]
        seq = struct.unpack_from("<H", data, 2)[0]
        if self.expected is not None:
            gap = (seq - self.expected) & 0xFFFF
            if gap < 0x8000:
                self.lost += gap
        self.expected = (seq + n) & 0xFFFF
        if self.first is None:
            self.first = (seq, SAMPLE.unpack_from(data, 4))
        self.frames += 1
        self.samples += n

    async def wait_line(self, prefix, timeout=2.0):
        end = time.monotonic() + timeout
        while True:
            left = end - time.monotonic()
            if left <= 0:
                return None
            try:
                line = await asyncio.wait_for(self.lines.get(), left)
            except asyncio.TimeoutError:
                return None
            if line.startswith(prefix):
                return line


async def find(args):
    if args.address:
        return args.address
    print("Scanning for Ishara-XXXX ...")
    dev = await BleakScanner.find_device_by_filter(
        lambda d, ad: (d.name or ad.local_name or "").startswith(args.name or "Ishara-"),
        timeout=10.0)
    if not dev:
        sys.exit("No Ishara glove found (is it powered and not connected to a phone?)")
    print(f"Found {dev.name} {dev.address}")
    return dev


async def send(client, cmd):
    print(f"  CMD   {cmd}")
    await client.write_gatt_char(CMD, cmd.encode(), response=True)


async def main(args):
    ok = True
    target = await find(args)
    g = Glove()
    async with BleakClient(target) as client:
        # Step 2: MTU. bleak cannot request a value; BlueZ / Windows / macOS negotiate it
        # themselves when connecting. On BlueZ, _acquire_mtu() makes mtu_size accurate.
        if client._backend.__class__.__name__ == "BleakClientBlueZDBus":
            try:
                await client._backend._acquire_mtu()
            except Exception:
                pass
        print(f"MTU {client.mtu_size} (a 5-sample frame needs at least 117)")

        # Step 3: INFO.
        info_raw = await client.read_gatt_char(INFO)
        info = json.loads(info_raw.decode())
        print(f"INFO {info_raw.decode()}")
        if info.get("proto") != PROTO:
            print(f"FAIL proto is {info.get('proto')}, expected {PROTO}: update the app / firmware")
            return False

        # Step 4: EVENT, then DATA.
        await client.start_notify(EVENT, g.on_event)
        await client.start_notify(DATA, g.on_data)
        await asyncio.sleep(0.3)  # #BAT arrives right after the EVENT subscription

        # Step 5: GETCAL.
        await send(client, "GETCAL")
        cal = await g.wait_line("#CAL")
        if cal is None:
            print("FAIL no #CAL reply within 2 s")
            ok = False
        else:
            print(f"CAL  {cal}")
            if cal != "#CAL NONE":
                d = json.loads(cal[5:])
                missing = [k for k in ("v", "open", "fist", "gyro_bias_raw", "roll_neutral",
                                       "roll_min", "roll_max") if k not in d]
                if missing:
                    print(f"FAIL #CAL is missing {missing}")
                    ok = False

        # Step 6: STREAM 1.
        await send(client, "STREAM 1")
        reply = await g.wait_line(("#OK STREAM", "#ERR STREAM"))
        if reply != "#OK STREAM":
            print(f"FAIL STREAM 1 replied {reply!r}")
            return False
        g.counting = True
        start = time.monotonic()
        await asyncio.sleep(args.seconds)
        g.counting = False
        secs = time.monotonic() - start
        await send(client, "STREAM 0")
        await g.wait_line("#OK STREAM")

        await send(client, "PING")
        if await g.wait_line("#PONG") is None:
            print("FAIL no #PONG")
            ok = False

    rate = info.get("rate_hz", 50)
    spf = info.get("samples_per_frame", 5)
    fps, sps = g.frames / secs, g.samples / secs
    print()
    print(f"Streamed {secs:.1f} s")
    print(f"Frames per second   {fps:5.1f}   (expect {rate / spf:.0f})")
    print(f"Samples per second  {sps:5.1f}   (expect {rate})")
    print(f"Lost samples        {g.lost}  (from seq)")
    print(f"Bad frames          {g.bad}")
    if g.first:
        seq, v = g.first
        print("First sample (serial format, seq is 8-bit there):")
        print("  " + ",".join(str(x) for x in (seq & 0xFF, *v)))
    if not g.frames or abs(sps - rate) > rate * 0.1 or g.bad:
        ok = False
    print("PASS" if ok else "FAIL")
    return ok


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--name", help="device name, e.g. Ishara-3FA2 (default: first Ishara-*)")
    p.add_argument("--address", help="BLE address (macOS: the CoreBluetooth UUID)")
    p.add_argument("--seconds", type=float, default=10.0, help="stream duration (default 10)")
    sys.exit(0 if asyncio.run(main(p.parse_args())) else 1)
