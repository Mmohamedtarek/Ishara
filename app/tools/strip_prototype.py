#!/usr/bin/env python3
"""Split design/prototype.html into a readable copy and the embedded .glb avatars.

The prototype embeds each avatar as a base64 string inside `window.__ISHARA_GLB = {"name":"<b64>", ...}`.
This script:
  * writes each blob, decoded, to <out>/glb/<name>.glb (and checks the glTF binary magic);
  * writes <out>/prototype.stripped.html with every blob replaced by "<<GLB:name, N bytes>>";
  * prints the sha256 of every extracted file.

It never modifies design/. Run again whenever the prototype changes:
  python3 app/tools/strip_prototype.py [--src design/prototype.html] [--out app/tools/out/prototype]
"""
import argparse
import base64
import hashlib
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
BLOB = re.compile(r'"([A-Za-z0-9_-]+)"\s*:\s*"([A-Za-z0-9+/=]{1000,})"')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=REPO / "design" / "prototype.html", type=pathlib.Path)
    ap.add_argument("--out", default=REPO / "app" / "tools" / "out" / "prototype", type=pathlib.Path)
    args = ap.parse_args()

    html = args.src.read_text(encoding="utf-8")
    anchor = html.find("window.__ISHARA_GLB")
    end = html.find("};", anchor) if anchor >= 0 else -1
    if anchor < 0 or end < 0:
        print("error: window.__ISHARA_GLB = {...}; not found", file=sys.stderr)
        return 1

    glb_dir = args.out / "glb"
    glb_dir.mkdir(parents=True, exist_ok=True)
    found = []

    def replace(m: re.Match) -> str:
        if m.start() < anchor or m.end() > end:
            return m.group(0)
        name, b64 = m.group(1), m.group(2)
        data = base64.b64decode(b64, validate=True)
        if data[:4] != b"glTF":
            raise SystemExit(f"error: blob {name!r} is not a binary glTF")
        path = glb_dir / f"{name}.glb"
        path.write_bytes(data)
        found.append((name, len(data), hashlib.sha256(data).hexdigest()))
        return f'"{name}":"<<GLB:{name}, {len(data)} bytes>>"'

    stripped = BLOB.sub(replace, html)
    if not found:
        print("error: no GLB blobs found", file=sys.stderr)
        return 1
    leftover = re.search(r"[A-Za-z0-9+/=]{5000,}", stripped)
    if leftover:
        print(f"warning: a large base64-like run remains at offset {leftover.start()} (not a GLB)", file=sys.stderr)

    out_html = args.out / "prototype.stripped.html"
    out_html.write_text(stripped, encoding="utf-8")
    for name, size, sha in found:
        print(f"{name}.glb  {size} bytes  sha256 {sha}")
    print(f"{out_html}  {len(stripped)} chars ({len(stripped.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
