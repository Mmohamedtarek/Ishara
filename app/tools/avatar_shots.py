#!/usr/bin/env python3
"""Renders avatar signs with the app's own engine page, for review.

Serves app/ishara_app/assets/ on 127.0.0.1, opens assets/avatar/index.html in
the system Chrome (Playwright, WebGL through SwiftShader), freezes each sign at
several moments and shoots it from the front and the side. One contact sheet
per sign: rows = views, columns = moments.

Usage (from app/tools, with the venv):
  .venv/bin/python avatar_shots.py [labels...] [--character nour] [--views 0,90]
      [--times auto|0,0.2,...] [--out out/avatar] [--pack asl]
Views are camera angles: 0 = front, -90 = from the signer's right side.
No label = every sign in the pack's library. Never edits assets.
"""
from __future__ import annotations

import argparse
import base64
import functools
import http.server
import json
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / "ishara_app" / "assets"   # --assets to render another copy (e.g. an older commit)


class _Quiet(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".js": "text/javascript", ".json": "application/json", ".glb": "model/gltf-binary"}

    def log_message(self, *a):  # noqa: D401
        pass


def serve(assets: Path | None = None) -> tuple[http.server.ThreadingHTTPServer, int]:
    h = functools.partial(_Quiet, directory=str(assets or ASSETS))
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), h)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def auto_times(frames: list[dict]) -> list[float]:
    """Every keyframe time, plus the midpoints of long gaps (max 8 columns)."""
    ts = sorted({float(f["t"]) for f in frames})
    if len(ts) > 8:
        step = (len(ts) - 1) / 7
        ts = [ts[round(i * step)] for i in range(8)]
    return ts


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("labels", nargs="*")
    ap.add_argument("--character", default="nour")
    ap.add_argument("--views", default="0,-90")
    ap.add_argument("--times", default="auto")
    ap.add_argument("--pack", default="asl")
    ap.add_argument("--size", default="340x300")
    ap.add_argument("--out", type=Path, default=HERE / "out" / "avatar")
    ap.add_argument("--crop", default="", help="x,y,w,h of each shot to keep (close-ups of the hand)")
    ap.add_argument("--assets", type=Path, default=None, help="assets folder to serve (default: the app's)")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    w, h = (int(x) for x in args.size.split("x"))
    lib_rel = f"packs/{args.pack}/avatar/library.json"
    assets = args.assets or ASSETS
    lib = json.loads((assets / lib_rel).read_text(encoding="utf-8"))
    labels = args.labels or list(lib["signs"])
    views = [float(v) for v in args.views.split(",")]

    srv, port = serve(assets)
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
            page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
            page.add_init_script("window.__isharaEvents = [];")
            errors: list[str] = []
            page.on("console", lambda m: errors.append(m.text) if m.type in ("error", "warning") else None)
            page.goto(f"http://127.0.0.1:{port}/avatar/index.html")
            page.evaluate("""c => window.__ishara.receive(c)""", {
                "cmd": "init", "cast": "cast.json", "library": f"../{lib_rel}",
                "character": args.character, "reduceMotion": True, "greet": False, "prefetch": False})
            page.wait_for_function("() => window.__isharaEvents.some(e => e.type === 'ready' || e.type === 'error')", timeout=120_000)
            ev = page.evaluate("() => window.__isharaEvents")
            bad = [e for e in ev if e["type"] == "error"]
            if bad:
                print("engine errors:", bad, errors)
                return 1
            sheets = []
            for label in labels:
                frames = lib["signs"][label]["frames"]
                times = auto_times(frames) if args.times == "auto" else [float(t) for t in args.times.split(",")]
                rows = []
                for v in views:
                    cells = []
                    for t in times:
                        page.evaluate("c => window.__ishara.receive(c)", {"cmd": "preview", "label": label, "t": t, "view": v})
                        page.wait_for_timeout(120)
                        if args.crop:
                            x, y, cw, chh = (int(v) for v in args.crop.split(","))
                            png = page.screenshot(omit_background=True, clip={"x": x, "y": y, "width": cw, "height": chh})
                        else:
                            png = page.locator("#avatar").screenshot(omit_background=True)
                        cells.append((t, base64.b64encode(png).decode()))
                    rows.append((v, cells))
                sheets.append((label, rows))
                out = args.out / f"{label}_{args.character}.png"
                cw_, ch_ = ((int(v) for v in args.crop.split(",")[2:]) if args.crop else (w, h))
                _sheet(browser, out, label, args.character, rows, cw_, ch_)
                print("wrote", out)
            ev = page.evaluate("() => window.__isharaEvents")
            bad = [e for e in ev if e["type"] == "error"]
            if bad:
                print("engine errors:", bad)
                return 1
            browser.close()
    finally:
        srv.shutdown()
    return 0


def _sheet(browser, out: Path, label: str, character: str, rows, w: int, h: int) -> None:
    cols = len(rows[0][1])
    view_name = {0.0: "front", -90.0: "side (signer's right)", 90.0: "side (signer's left)"}
    html = ["<html><body style='margin:0;background:#33363F;font:13px sans-serif;color:#eee'>",
            f"<div style='padding:8px 10px;font-size:16px;font-weight:700'>{label} · {character}</div>"]
    for v, cells in rows:
        html.append(f"<div style='padding:2px 10px'>{view_name.get(v, f'{v:g}°')}</div><div style='display:flex;gap:4px;padding:0 6px 6px'>")
        for t, b64 in cells:
            html.append(f"<div><img src='data:image/png;base64,{b64}' width='{w}' height='{h}' style='display:block;background:radial-gradient(120% 90% at 50% 15%,#4A4D57 0%,#33363F 55%,#24262D 100%)'><div style='text-align:center'>t = {t:.2f} s</div></div>")
        html.append("</div>")
    html.append("</body></html>")
    p = browser.new_page(viewport={"width": 12 + cols * (w + 4), "height": 40 + len(rows) * (h + 44)}, device_scale_factor=1)
    p.set_content("".join(html))
    p.screenshot(path=str(out), full_page=True)
    p.close()


if __name__ == "__main__":
    raise SystemExit(main())
