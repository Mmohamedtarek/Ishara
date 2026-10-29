"""Build a big bench once (model predictions included) and save it, so Decider configs score in seconds.
usage: python _work/bench_cache.py NAME val|test hours [models(keras, comma)]
"""
import os
import pickle
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.getcwd())
sys.path.insert(0, "_work")
import numpy as np

import check_words as cw
import eval_live as ev
import simulate_data as sim
from common import SIGN_LABELS, setup_console
from exp_eval_lib import KPred

setup_console()
name, which, hours = sys.argv[1], sys.argv[2], float(sys.argv[3])
paths = sys.argv[4].split(",") if len(sys.argv) > 4 else ["ishara_cnn.keras", "ishara_cnn_2.keras", "ishara_cnn_3.keras"]
seed = ev.VAL_SEED + 7000 if which == "val" else ev.TEST_SEED + 7000
iso_seed = cw.NEW_SEED + 500 if which == "val" else cw.NEW_SEED + 100
pred = KPred(paths)
t0 = time.time()
tb = ev.Bench(pred, seed, people=24, hours=hours, iso_reps=2)
for st in tb.sent:
    st.pop("W", None)
iso = []
Ws, sizes = [], []
for p in range(40):
    person, o, f, b = ev.new_person(iso_seed + p)
    for w in SIGN_LABELS:
        for _ in range(3):
            raw = sim.stitch([sim.make_sample(s, person) for s in ["rest", w, "rest", "rest", "rest"]])
            W, _ = ev.windows_of(raw, o, f, b)
            Ws.append(W)
            sizes.append(len(W))
            iso.append(w)
PI = pred.batch(np.concatenate(Ws))
offs = np.cumsum([0] + sizes)
with open(f"_work/bench_{name}.pkl", "wb") as fh:
    pickle.dump({"classes": pred.classes, "sent": tb.sent, "every": tb.every, "minutes": tb.minutes,
                 "iso_words": iso, "iso_P": [PI[offs[k]:offs[k + 1]] for k in range(len(iso))]}, fh)
print(f"saved _work/bench_{name}.pkl ({time.time() - t0:.0f}s, {tb.minutes / 60:.0f} h)", flush=True)
