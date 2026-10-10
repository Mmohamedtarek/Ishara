#!/usr/bin/env python3
"""Checks that a hidden character (cast.json `hidden`) never reaches the screen.

Starts the engine page asking for each hidden character (at init and with
setCharacter, prefetch on) and checks that the default character is shown,
no error is posted and no hidden character's model is downloaded (RB-1:
Sara is hidden in v1).

Usage (from app/tools): .venv/bin/python avatar_cast_check.py
Exit 1 on any failure.
"""
from __future__ import annotations

import json
from pathlib import Path

from playwright.sync_api import sync_playwright

import avatar_shots

CAST = Path(__file__).resolve().parent.parent / "ishara_app/assets/avatar/cast.json"


def main() -> int:
    cast = json.loads(CAST.read_text())
    hidden = [k for k, v in cast["characters"].items() if v.get("hidden")]
    default = cast["default"]
    if not hidden:
        print("no hidden characters")
        return 0
    srv, port = avatar_shots.serve()
    bad = []
    try:
        with sync_playwright() as pw:
            b = pw.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
            for h in hidden:
                p = b.new_page(viewport={"width": 200, "height": 200})
                p.add_init_script("window.__isharaEvents = []; window.__fetched = []; const f = window.fetch;"
                                  " window.fetch = function(u){ window.__fetched.push(String(u)); return f.apply(this, arguments); };")
                p.goto(f"http://127.0.0.1:{port}/avatar/index.html")
                p.evaluate("c => window.__ishara.receive(c)", {"cmd": "init", "cast": "cast.json", "library": "../packs/asl/avatar/library.json", "character": h, "greet": False, "prefetch": True})
                p.wait_for_function("() => window.__isharaEvents.some(e => e.type === 'ready' || e.type === 'error')", timeout=120_000)
                p.evaluate("c => window.__ishara.receive(c)", {"cmd": "setCharacter", "character": h, "greet": False})
                p.wait_for_timeout(6000)   # past the prefetch delays
                ev = p.evaluate("() => window.__isharaEvents")
                shown = {e.get("character") for e in ev if e["type"] in ("ready", "character")}
                errors = [e for e in ev if e["type"] == "error"]
                glbs = [u for u in p.evaluate("() => window.__fetched") if u.endswith(".glb")]
                print(f"asked for {h}: shown {sorted(shown)}, errors {len(errors)}, models fetched {glbs}")
                if shown != {default}:
                    bad.append(f"{h}: shown {shown}")
                if errors:
                    bad.append(f"{h}: errors {errors}")
                if any(cast["characters"][h]["src"] in u for u in glbs):
                    bad.append(f"{h}: its model was downloaded")
                p.close()
            b.close()
    finally:
        srv.shutdown()
    print("OK" if not bad else "FAIL: " + "; ".join(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
