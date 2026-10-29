"""
Budgeted tuning on the cached 120 h validation bench:
maximize single-word accuracy (+ sentences) while stray words stay <= the current settings (the budget).
Per-word single-word rules (rest_per_class) for the words that get missed, and stricter per-word rules
(idle per_class + rest_per_class) for the words that come out as stray words, to win budget back.
usage: python _work/budget_tune.py base_cfg.json out.json
"""
import json
import os
import sys

sys.path.insert(0, os.getcwd())
sys.path.insert(0, "_work")
import score_cached as sc
from common import setup_console

setup_console()
base = json.load(open(sys.argv[1], encoding="utf-8"))
if "cnn" in base:
    base = base["cnn"]
r0 = sc.score(base, "val")
budget = r0["false"]
print("base :", sc.line(r0), flush=True)


def gain(r):
    return r["iso2"] + 0.5 * r["iso_ok"] / r["iso_n"] - 0.02 * r["wer"] / 100


def ok(r):
    return r["false"] <= budget


cfg, r = json.loads(json.dumps(base)), r0
RELAX = {"null": [0.05, 0.08, 0.12, 0.2, 0.3], "conf": [0.6, 0.65], "run": [1, 2]}
TIGHT_REST = {"null": [0.02, 0.01, 0.005], "conf": [0.8, 0.9], "run": [4, 5]}
TIGHT_IDLE = [0.9, 0.95, 0.98]
for rnd in range(3):
    # words that get missed alone: relax their single-word rule
    missed = sorted(r["iso2_per"], key=lambda w: r["iso2_per"][w])[:8]
    for w in missed:
        for k, vals in RELAX.items():
            for v in vals:
                cand = json.loads(json.dumps(cfg))
                cand.setdefault("rest_per_class", {}).setdefault(w, {})[k] = v
                rc = sc.score(cand, "val")
                if ok(rc) and gain(rc) > gain(r) + 1e-9:
                    cfg, r = cand, rc
                    print(f"  relax {w} {k}={v}: " + sc.line(r), flush=True)
    # words that come out as stray words: tighten them, if it costs less than it gives back
    stray = [w for w, _ in r["false_words"]]
    for w in stray:
        for k, vals in TIGHT_REST.items():
            for v in vals:
                cand = json.loads(json.dumps(cfg))
                cand.setdefault("rest_per_class", {}).setdefault(w, {})[k] = v
                rc = sc.score(cand, "val")
                if rc["false"] < r["false"] and gain(rc) >= gain(r) - 0.002:
                    cfg, r = cand, rc
                    print(f"  tighten-rest {w} {k}={v}: " + sc.line(r), flush=True)
        for v in TIGHT_IDLE:
            cand = json.loads(json.dumps(cfg))
            cand["idle"]["per_class"][w] = v
            rc = sc.score(cand, "val")
            if rc["false"] < r["false"] and gain(rc) >= gain(r) - 0.002:
                cfg, r = cand, rc
                print(f"  tighten-idle {w}={v}: " + sc.line(r), flush=True)
    print(f"round {rnd + 1}:", sc.line(r), flush=True)
json.dump(cfg, open(sys.argv[2], "w", encoding="utf-8"), indent=1)
print("rest_per_class:", json.dumps(cfg.get("rest_per_class")), "idle per_class:", json.dumps(cfg["idle"]["per_class"]))
