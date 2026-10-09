#!/usr/bin/env python3
"""Checks that the ported avatar engine renders like the prototype.

Renders every sign the port did not change (all prototype signs except
WATER, V-3, and I LOVE YOU, Q-A3/Q-A4; the frames the step 5 review changed
are reported but allowed, see FIXED_SIGNS) frozen at each keyframe, front view,
in both the prototype (design/prototype.html, which loads three.js from its
CDN, so this needs the network) and the app's engine page, at the same size,
and compares the pixels.

Usage (from app/tools): .venv/bin/python avatar_port_check.py [--out out/port]
Exit 1 if any frame differs by more than the threshold.
"""
from __future__ import annotations

import argparse
import io
import json
from pathlib import Path

import numpy as np
from playwright.sync_api import sync_playwright

import avatar_shots

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
CHANGED = {"water", "love"}   # V-3; Q-A3 + Q-A4 (iloveyou)
# Step 5 review (user, S5-1 / S5-2): only frames posed by a body contact
# (landmark point, at tip / palm: now measured and touching) or by an elbow
# key (E) may differ, plus YOU (asked to point level). Every other frame,
# including the other frames of those signs, must render like the prototype.
FIXED_SIGNS = {"you", "doctor"}   # DOCTOR: taps the wrist (review round 3)


def allowed_frames() -> set[tuple[str, float]]:
    lib = json.loads((REPO / "app/ishara_app/assets/packs/asl/avatar/library.json").read_text())
    out = set()
    for label, sign in lib["signs"].items():
        name = "love" if label == "iloveyou" else label
        keys = {"R": None, "L": None}
        for f in sign["frames"]:
            for h in ("R", "L"):
                if f.get(h):
                    keys[h] = f[h]
            touched = any(
                k and ("E" in k or (isinstance(k["P"][0], str) and k.get("at") in ("tip", "palm")))
                for k in keys.values()
            )
            if touched or label in FIXED_SIGNS:
                out.add((name, round(float(f["t"]), 3)))
    return out
W, H = 340, 300
# Mean absolute difference per channel (0-255). Blinks are random in both
# pages; anything else (pose, light, camera, materials) moves far more.
THRESHOLD = 1.5


def png_to_array(png: bytes) -> np.ndarray:
    # Decode through the browser-independent PNG reader below (no Pillow).
    import zlib
    import struct
    data = io.BytesIO(png)
    assert data.read(8) == b"\x89PNG\r\n\x1a\n"
    width = height = 0
    idat = b""
    while True:
        ln, = struct.unpack(">I", data.read(4))
        typ = data.read(4)
        body = data.read(ln)
        data.read(4)
        if typ == b"IHDR":
            width, height, depth, ctype = struct.unpack(">IIBB", body[:10])
            assert depth == 8 and ctype in (2, 6), (depth, ctype)
            ch = 4 if ctype == 6 else 3
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = width * ch
    out = np.zeros((height, stride), dtype=np.int32)
    prev = np.zeros(stride, dtype=np.int32)
    pos = 0
    for y in range(height):
        f = raw[pos]
        line = np.frombuffer(raw[pos + 1:pos + 1 + stride], dtype=np.uint8).astype(np.int32)
        pos += 1 + stride
        if f == 0:
            cur = line
        elif f == 1:
            cur = line.copy()
            for x in range(ch, stride):
                cur[x] = (cur[x] + cur[x - ch]) & 255
        elif f == 2:
            cur = (line + prev) & 255
        elif f == 3:
            cur = line.copy()
            for x in range(stride):
                left = cur[x - ch] if x >= ch else 0
                cur[x] = (cur[x] + ((left + prev[x]) >> 1)) & 255
        else:
            cur = line.copy()
            for x in range(stride):
                a = cur[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[x] = (cur[x] + pr) & 255
        out[y] = cur
        prev = cur
    return out.reshape(height, width, ch)[:, :, :3]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=HERE / "out" / "port")
    ap.add_argument("--character", default="nour")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    proto = json.loads((REPO / "app/ishara_app/test/fixtures/prototype_avatar_library.json").read_text())
    signs = [k for k in proto["signs"] if k not in CHANGED]
    srv, port = avatar_shots.serve()
    worst = 0.0
    rows = []
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
            # the prototype
            ctx = browser.new_context(viewport={"width": 430, "height": 900}, device_scale_factor=1, reduced_motion="reduce")
            pp = ctx.new_page()
            pp.add_init_script(f"try {{ localStorage.setItem('ishara-avatar', '{args.character}'); }} catch(e) {{}}")
            pp.goto((REPO / "design/prototype.html").as_uri())
            pp.wait_for_function("() => window.__avatarEngine && window.__avatarEngine._dbg && window.__avatarEngine._dbg.avatar()", timeout=180_000)
            pp.wait_for_function(f"() => window.__avatarEngine.current() === '{args.character}' && window.__avatarEngine._dbg.avatar().id === '{args.character}'", timeout=180_000)
            pp.add_style_tag(content=f"html,body{{background:transparent!important}} body>*:not(#avatar){{display:none!important}} #avatar{{position:absolute!important;left:0;top:0;width:{W}px!important;height:{H}px!important;z-index:99999;border-radius:0!important;background:transparent!important;box-shadow:none!important}} #avatar>:not(canvas){{display:none!important}}")
            pp.evaluate("() => { document.body.appendChild(document.getElementById('avatar')); }")
            pp.wait_for_timeout(300)
            pp.evaluate("() => window.__avatarEngine.reframe()")
            # the port
            ap_ = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
            ap_.add_init_script("window.__isharaEvents = [];")
            ap_.goto(f"http://127.0.0.1:{port}/avatar/index.html")
            ap_.evaluate("c => window.__ishara.receive(c)", {"cmd": "init", "cast": "cast.json", "library": "../packs/asl/avatar/library.json", "character": args.character, "reduceMotion": True, "greet": False, "prefetch": False})
            ap_.wait_for_function("() => window.__isharaEvents.some(e => e.type === 'ready' || e.type === 'error')", timeout=120_000)
            for label in signs:
                for f in proto["signs"][label]["frames"]:
                    t = float(f["t"])
                    pp.evaluate("([n, t]) => window.__avatarEngine._dbg.pose(n, t)", [label, t])
                    pp.wait_for_timeout(1500)   # the prototype eases into a frozen pose
                    a = png_to_array(pp.locator("#avatar").screenshot(omit_background=True))
                    ap_.evaluate("c => window.__ishara.receive(c)", {"cmd": "preview", "label": label, "t": t, "view": 0})
                    ap_.wait_for_timeout(150)
                    b = png_to_array(ap_.locator("#avatar").screenshot(omit_background=True))
                    d = float(np.abs(a - b).mean())
                    worst = max(worst, d)
                    rows.append((label, t, d))
                    if d > THRESHOLD:
                        (args.out / f"{label}_{t:.2f}_proto.png").write_bytes(pp.locator('#avatar').screenshot(omit_background=True))
                        (args.out / f"{label}_{t:.2f}_port.png").write_bytes(ap_.locator('#avatar').screenshot(omit_background=True))
            browser.close()
    finally:
        srv.shutdown()
    for label, t, d in rows:
        print(f"{label:8s} t={t:5.2f}  mean |diff| = {d:6.3f}" + ("  <-- DIFFERS" if d > THRESHOLD else ""))
    ok = allowed_frames()
    strict = [r for r in rows if (r[0], round(r[1], 3)) not in ok]
    worst_strict = max((d for _, _, d in strict), default=0.0)
    bad = [f"{l} t={t:.2f}" for l, t, d in strict if d > THRESHOLD]
    allowed = sorted({f"{l} t={t:.2f}" for l, t, d in rows if (l, round(t, 3)) in ok and d > THRESHOLD})
    print(f"{len(rows)} frames; {len(strict)} must match the prototype: worst {worst_strict:.3f} "
          f"(threshold {THRESHOLD}){'; DIFFER: ' + ', '.join(bad) if bad else ''}")
    print(f"contact / elbow / YOU frames that differ (allowed): {allowed}")
    return 0 if worst_strict <= THRESHOLD else 1


if __name__ == "__main__":
    raise SystemExit(main())
