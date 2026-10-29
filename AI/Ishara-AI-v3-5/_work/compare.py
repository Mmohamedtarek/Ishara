"""Fair comparison of several Decider configs (same models) on one big test bench.
usage: python _work/compare.py models(keras, comma) hours people cfg1.json cfg2.json ...
"""
import json
import os
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.getcwd())
sys.path.insert(0, "_work")
import eval_live as ev
import check_words as cw
from common import SIGN_LABELS, setup_console
from exp_eval_lib import KPred

setup_console()
paths, hours, people = sys.argv[1].split(","), float(sys.argv[2]), int(sys.argv[3])
pred = KPred(paths)
t0 = time.time()
tb = ev.Bench(pred, ev.TEST_SEED + 7000, people=people, hours=hours, iso_reps=2)
iso_streams = []
for p in range(40):
    person, o, f, b = ev.new_person(cw.NEW_SEED + 100 + p)
    for w in SIGN_LABELS:
        for _ in range(3):
            import simulate_data as sim
            iso_streams.append((w, sim.stitch([sim.make_sample(s, person) for s in ["rest", w, "rest", "rest", "rest"]]), (o, f, b)))
import numpy as np
Ws, sizes = [], []
for _, raw, (o, f, b) in iso_streams:
    W, _ = ev.windows_of(raw, o, f, b)
    Ws.append(W); sizes.append(len(W))
PI = pred.batch(np.concatenate(Ws))
offs = np.cumsum([0] + sizes)
print(f"bench ready ({time.time() - t0:.0f}s)", flush=True)
import glob
QUEUE = os.environ.get("QUEUE", "_work/queue")
done = set()
while not os.path.exists(os.path.join(QUEUE, "STOP")):
    todo = [q for q in sorted(glob.glob(os.path.join(QUEUE, "*.json"))) if q not in done]
    if not todo:
        time.sleep(15)
        continue
    path = todo[0]
    done.add(path)
    cfg = json.load(open(path))
    r = tb.score(cfg)
    ev.show(r, f"== {path}")
    said = [[w for _, w in ev.run_decider(PI[offs[k]:offs[k + 1]], cfg, pred.classes)] for k in range(len(iso_streams))]
    res = {w: [] for w in SIGN_LABELS}
    for (w, _, _), s in zip(iso_streams, said):
        res[w].append(s == [w])
    ok = sum(sum(v) for v in res.values())
    n = sum(len(v) for v in res.values())
    print(f"  check_words (40 new people x 3): {ok}/{n} = {ok / n * 100:.1f}%")
    print("  " + "  ".join(f"{w}:{sum(v) / len(v) * 100:.0f}" for w, v in res.items()), flush=True)
