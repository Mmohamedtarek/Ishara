#!/usr/bin/env python3
"""Prints how far each body contact lands from its target (mm), per character.

Uses the engine's own bake (`_dbg.contacts()`), in headless Chrome.
Usage (from app/tools): .venv/bin/python avatar_contacts.py [--character nour] [--json]
"""
from __future__ import annotations

import argparse
import json

from playwright.sync_api import sync_playwright

import avatar_shots


def contacts(character: str) -> list[dict]:
    srv, port = avatar_shots.serve()
    try:
        with sync_playwright() as pw:
            b = pw.chromium.launch(channel="chrome", args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader"])
            p = b.new_page(viewport={"width": 340, "height": 300})
            p.add_init_script("window.__isharaEvents = [];")
            p.goto(f"http://127.0.0.1:{port}/avatar/index.html")
            p.evaluate("c => window.__ishara.receive(c)", {"cmd": "init", "cast": "cast.json", "library": "../packs/asl/avatar/library.json", "character": character, "greet": False, "prefetch": False})
            p.wait_for_function("() => window.__isharaEvents.some(e => e.type === 'ready' || e.type === 'error')", timeout=120_000)
            out = p.evaluate("() => window.__avatarEngine._dbg.contacts()")
            b.close()
            return out
    finally:
        srv.shutdown()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--character", default="nour")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    rows = contacts(a.character)
    if a.json:
        print(json.dumps(rows))
        return 0
    for r in rows:
        print(f"{r['sign']:9s} f{r['frame']:<2d} {r['side']:5s} want={r['want']} got={r['got']} error={r['mm']} mm")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
