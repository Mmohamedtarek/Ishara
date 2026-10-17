#!/usr/bin/env python3
"""What the app keeps on a phone, by name and count only (never values).

Pulls the app's old key-value store (shared_preferences on DataStore) and
its database (step 10a) from a debug build with `adb run-as`, prints key
names, value types, list sizes and table counts, then deletes the pulled
copies. For the step 10a before / after check; safe to paste anywhere.

Usage: python3 app/tools/storage_probe.py [--serial RZ8R317P1EW]
"""
import argparse
import json
import os
import sqlite3
import subprocess
import sys
import tempfile

PKG = "io.github.mmohamedtarek.ishara"
PREFS = "files/datastore/FlutterSharedPreferences.preferences_pb"
DB = "files/ishara.sqlite"


def pull(serial: str, path: str, dest: str) -> bool:
    test = ["adb", "-s", serial, "shell", "run-as", PKG, "test", "-f", path, "&&", "echo", "yes"]
    if subprocess.run(test, capture_output=True, text=True).stdout.strip() != "yes":
        return False
    cmd = ["adb", "-s", serial, "exec-out", "run-as", PKG, "cat", path]
    with open(dest, "wb") as f:
        r = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE)
    ok = r.returncode == 0 and os.path.getsize(dest) > 0
    if not ok:
        os.remove(dest)
    return ok


def varint(b: bytes, i: int) -> tuple[int, int]:
    n = shift = 0
    while True:
        c = b[i]
        i += 1
        n |= (c & 0x7F) << shift
        shift += 7
        if c < 0x80:
            return n, i


def fields(b: bytes):
    """(field number, wire type, value) of one protobuf message."""
    i = 0
    while i < len(b):
        key, i = varint(b, i)
        num, wire = key >> 3, key & 7
        if wire == 0:
            v, i = varint(b, i)
        elif wire == 1:
            v, i = b[i : i + 8], i + 8
        elif wire == 2:
            n, i = varint(b, i)
            v, i = b[i : i + n], i + n
        elif wire == 5:
            v, i = b[i : i + 4], i + 4
        else:
            raise ValueError(f"wire type {wire}")
        yield num, wire, v


VALUE_TYPES = {1: "bool", 2: "float", 3: "int", 4: "long", 5: "string", 6: "string set", 7: "double", 8: "bytes"}


def describe(text: str) -> str:
    """A string value's shape: a JSON list's length, else its length."""
    try:
        v = json.loads(text)
    except ValueError:
        return f"text, {len(text)} chars"
    if isinstance(v, list):
        return f"JSON list, {len(v)} entries"
    return f"{type(v).__name__}"


def prefs_report(path: str) -> list[str]:
    out = []
    data = open(path, "rb").read()
    for num, _, entry in fields(data):
        if num != 1:
            continue
        key = value = None
        for n, _, v in fields(entry):
            if n == 1:
                key = v.decode()
            elif n == 2:
                value = v
        kind = "?"
        shape = ""
        for n, w, v in fields(value or b""):
            kind = VALUE_TYPES.get(n, str(n))
            if n == 5:
                shape = describe(v.decode("utf-8", "replace"))
        out.append(f"  {key}: {kind}{' (' + shape + ')' if shape else ''}")
    return sorted(out)


def db_report(path: str) -> list[str]:
    con = sqlite3.connect(path)
    out = []
    tables = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
    for t in tables:
        out.append(f"  {t}: {con.execute(f'SELECT COUNT(*) FROM {t}').fetchone()[0]} rows")
    out.append("  prefs keys: " + ", ".join(r[0] for r in con.execute("SELECT key FROM prefs ORDER BY key")))
    out.append("  migration markers: " + ", ".join(f"{k} {v}" for k, v in con.execute("SELECT key, value FROM meta WHERE key LIKE 'kv.migrated.%' ORDER BY key")))
    kept = list(con.execute("SELECT key, reason FROM kept_values ORDER BY id"))
    out.append("  kept aside: " + (", ".join(f"{k} ({r})" for k, r in kept) or "none"))
    out.append(f"  conversations: {con.execute('SELECT COUNT(DISTINCT COALESCE(conversation, substr(at, 1, 10))) FROM messages').fetchone()[0]}")
    out.append(f"  phrases live / tombstones: {con.execute('SELECT SUM(NOT deleted), SUM(deleted) FROM phrases').fetchone()}")
    out.append(f"  schema version: {con.execute('PRAGMA user_version').fetchone()[0]}")
    con.close()
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL", "RZ8R317P1EW"))
    a = ap.parse_args()
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "prefs.pb")
        print("old key-value store (ishara.* keys):")
        if pull(a.serial, PREFS, p):
            lines = [line for line in prefs_report(p) if line.strip().startswith("ishara.")]
            others = len(prefs_report(p)) - len(lines)
            print("\n".join(lines) if lines else "  (no ishara.* keys)")
            if others:
                print(f"  + {others} other keys (not the app's)")
        else:
            print("  (no file)")
        db = os.path.join(d, "ishara.sqlite")
        print("database:")
        if pull(a.serial, DB, db):
            for s in ("-journal", "-wal"):
                pull(a.serial, DB + s, db + s)
            print("\n".join(db_report(db)))
        else:
            print("  (no file)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
