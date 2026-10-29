"""Score Decider configs on cached benches.  import score_cached as sc; sc.load('val'); sc.score(cfg)"""
import collections
import os
import pickle
import sys

sys.path.insert(0, os.getcwd())
import numpy as np

import eval_live as ev

_B = {}


class _Bench(ev.Bench):
    def __init__(self, d):
        self.classes, self.sent, self.every, self.minutes = d["classes"], d["sent"], d["every"], d["minutes"]


def load(name):
    if name not in _B:
        with open(f"_work/bench_{name}.pkl", "rb") as fh:
            d = pickle.load(fh)
        _B[name] = (_Bench(d), d)
    return _B[name]


def score(cfg, name):
    b, d = load(name)
    r = b.score(cfg)
    per = collections.defaultdict(list)
    for w, P in zip(d["iso_words"], d["iso_P"]):
        said = [x for _, x in ev.run_decider(P, cfg, d["classes"])]
        per[w].append(said == [w])
    r["iso2_per"] = {w: float(np.mean(v)) for w, v in per.items()}
    r["iso2"] = float(np.mean([x for v in per.values() for x in v]))
    return r


def line(r):
    return (f"single {r['iso2'] * 100:5.1f}% (bench {r['iso_ok'] / r['iso_n'] * 100:4.1f}%) | stray {r['false']:3d} "
            f"in {r['minutes'] / 60:.0f}h | WER {r['wer']:.1f}% | " +
            " ".join(f"{w}:{r['iso2_per'][w] * 100:.0f}" for w in ("one", "five", "drink", "hungry")))
