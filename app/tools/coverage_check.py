#!/usr/bin/env python3
"""Fail if line coverage of the given lib/ folders is below the bar (prompt: >= 90 % on
lib/core/ and on the domain layers). Generated files (*.g.dart, *.freezed.dart, l10n/gen) and
temporary skeleton UI are not counted.

lcov only lists files some test imported, so every .dart file found on disk under a folder must
appear in lcov.info: a file that no test loads fails the gate (it would otherwise be invisible).
A folder pattern that matches no files on disk is reported, not failed (e.g. no domain layer yet).

Usage (from app/ishara_app, after `flutter test --coverage`):
  python3 ../tools/coverage_check.py coverage/lcov.info --min 90 lib/core 'lib/features/*/domain'
"""
import argparse
import fnmatch
import glob
import sys

SKIP = ["*.g.dart", "*.freezed.dart", "lib/l10n/gen/*", "lib/core/ui/skeleton_screen.dart",
        "lib/core/ui/ishara_icon_data.dart"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("lcov")
    ap.add_argument("folders", nargs="+")
    ap.add_argument("--min", type=float, default=90)
    a = ap.parse_args()
    files, cur = {}, None
    for line in open(a.lcov, encoding="utf-8"):
        line = line.strip()
        if line.startswith("SF:"):
            cur = line[3:]
            files[cur] = [0, 0]
        elif line.startswith("DA:") and cur:
            hits = int(line[3:].split(",")[1])
            files[cur][1] += 1
            files[cur][0] += hits > 0
    if not files:
        print(f"FAIL: {a.lcov} has no files", file=sys.stderr)
        return 1
    ok = True
    for folder in a.folders:
        def wanted(f: str) -> bool:
            return fnmatch.fnmatch(f, folder.rstrip("/") + "/*") and not any(fnmatch.fnmatch(f, s) for s in SKIP)

        on_disk = {f for f in glob.glob(folder.rstrip("/") + "/**/*.dart", recursive=True) if wanted(f)}
        if not on_disk:
            print(f"{folder}: no source files yet")
            continue
        untested = sorted(on_disk - files.keys())
        if untested:
            ok = False
            print(f"{folder}: FAIL, no test loads: {', '.join(untested)}")
        sel = {f: v for f, v in files.items() if wanted(f)}
        hit, total = sum(v[0] for v in sel.values()), sum(v[1] for v in sel.values())
        if total == 0:
            ok = False
            print(f"{folder}: FAIL, files exist but no lines were measured")
            continue
        pct = 100 * hit / total
        print(f"{folder}: {pct:.1f} % ({hit}/{total} lines)")
        for f, (h, t) in sorted(sel.items()):
            if t and h < t:
                print(f"    {f}: {100 * h / t:.0f} % ({t - h} lines missed)")
        ok &= pct >= a.min
    if not ok:
        print(f"FAIL: coverage gate (minimum {a.min} %, every file loaded by a test)", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
