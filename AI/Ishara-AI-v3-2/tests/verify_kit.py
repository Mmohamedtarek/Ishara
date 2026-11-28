"""
Independent check of the Ishara Mobile Kit, written from AI-SPEC.md only.
It imports nothing from the AI code: it re-implements normalize, the ensemble,
the Decider and the BLE gap rule from the spec, runs the kit's .tflite files,
and compares everything with the kit's test files.

Usage (from AI/Ishara-AI-v3-2):  python tests/verify_kit.py ../../app/Ishara-Mobile-Kit
Exit code 0 = the kit matches its spec; 1 = a mismatch (printed).
"""
import json, os, sys
import numpy as np
import tensorflow as tf

KIT = sys.argv[1] if len(sys.argv) > 1 else "../../app/Ishara-Mobile-Kit"
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
labels = [l.strip() for l in open(os.path.join(KIT, "model/labels.txt")) if l.strip()]
cfg = json.load(open(os.path.join(KIT, "model/decider.json")))["cnn"]
interps = []
for m in cfg["models"]:
    it = tf.lite.Interpreter(model_path=os.path.join(KIT, "model", m)); it.allocate_tensors(); interps.append(it)


def run_models(win):
    outs = []
    for it in interps:
        it.set_tensor(it.get_input_details()[0]["index"], win[None].astype(np.float32)); it.invoke()
        outs.append(it.get_tensor(it.get_output_details()[0]["index"])[0])
    return outs


def normalize(raw, cal):
    raw = np.asarray(raw, np.float64); x = np.zeros_like(raw)
    o, f = np.array(cal["open"], float), np.array(cal["fist"], float)
    span = f - o; span[np.abs(span) < 1] = 1
    x[:, :5] = (raw[:, :5] - o) / span
    x[:, 5:8] = raw[:, 5:8] / 8192
    x[:, 8:11] = (raw[:, 8:11] - np.array(cal["gyro_bias_raw"], float)) / 65.5 / 250
    return x.astype(np.float32)


class Decider:
    def __init__(s):
        s.smooth = cfg["smooth"]; s.recent = []; s.last = None; s.rest_seen = 0; s.step = 0
        s.active_until = -1; s.pending = None; s.pending_until = -1; s.blocked = set()
        s.L = {k: cfg[k] for k in ("idle", "tentative", "active")}; s.run = {k: (None, 0) for k in s.L}
        s.act = round(cfg["active_s"] * 5); s.conf_steps = round(cfg["confirm_s"] * 5)
        # spec v3.3: pair_level and the single-word rule (defaults = v3.2.1 behaviour)
        s.pair = cfg.get("pair_level", "active"); s.cor = cfg.get("confirm_on_rest", 0)
        s.r_conf = cfg.get("rest_conf", 0.0); s.r_run = cfg.get("rest_run", 0); s.r_null = cfg.get("rest_null", 1.0)
        s.p_rest = 0; s.p_peak = 0.0; s.p_run = 0; s.p_best = 0; s.p_null = 1.0

    def say(s, l): s.last = l; s.active_until = s.step + s.act

    def feed(s, p):
        s.step += 1; ev = []
        if s.pending is not None and s.step > s.pending_until:
            ev.append(("cancel", s.pending)); s.blocked.add(s.pending); s.pending = None
        s.recent = (s.recent + [np.asarray(p, float)])[-s.smooth:]
        avg = np.mean(s.recent, 0); top = int(np.argmax(avg)); lab = labels[top]; conf = avg[top]
        null = avg[labels.index("rest")] + avg[labels.index("other")]
        if s.pending is not None:
            T = s.L["tentative"]
            if lab == s.pending:
                s.p_peak = max(s.p_peak, conf); s.p_null = min(s.p_null, null)
                ok = conf >= T.get("per_class", {}).get(lab, T["confidence"]) and null <= T["max_null"]
                s.p_run = s.p_run + 1 if ok else 0; s.p_best = max(s.p_best, s.p_run)
            else:
                s.p_run = 0
            s.p_rest = s.p_rest + 1 if lab == "rest" else 0
        if lab in ("rest", "other"):
            if (s.pending is not None and s.cor > 0 and s.p_rest >= s.cor and s.p_peak >= s.r_conf
                    and s.p_best >= s.r_run and s.p_null <= s.r_null):
                ev.append(("confirm", s.pending)); s.say(s.pending); s.pending = None; s.p_rest = 0
            s.rest_seen += 1
            if s.rest_seen >= 2: s.last = None; s.blocked.clear()
            s.run = {k: (None, 0) for k in s.L}; return ev
        s.rest_seen = 0
        passed = {}
        for k, L in s.L.items():
            thr = L.get("per_class", {}).get(lab, L["confidence"])
            if len(s.recent) == s.smooth and conf >= thr and null <= L["max_null"]:
                rl, rc = s.run[k]; rc = rc + 1 if rl == lab else 1; s.run[k] = (lab, rc); passed[k] = rc >= L["hold"]
            else:
                s.run[k] = (None, 0); passed[k] = False
        if s.step <= s.active_until:
            if passed["active"] and lab != s.last: ev.append(("word", lab)); s.say(lab)
        elif s.pending is not None:
            if lab == s.pending:
                if passed["idle"]: ev.append(("confirm", lab)); s.say(lab); s.pending = None
            elif passed[s.pair] and lab != s.last:
                ev += [("confirm", s.pending), ("word", lab)]; s.say(lab); s.pending = None
        elif lab != s.last:
            if passed["idle"]: ev.append(("word", lab)); s.say(lab)
            elif passed["tentative"] and lab not in s.blocked:
                ev.append(("tentative", lab)); s.pending = lab; s.pending_until = s.step + s.conf_steps
                s.p_rest = 0; s.p_peak = conf; s.p_run = 1; s.p_best = 1; s.p_null = null
        return ev


def play(path):
    cal, win, n, d, events = None, [], 0, Decider(), []
    for line in open(path):
        line = line.strip()
        if not line: continue
        if line.startswith("#"):
            if line.startswith("#CAL "): cal = json.loads(line[5:]); win, n, d = [], 0, Decider()
            continue
        raw = [float(v) for v in line.split(",")[1:]]
        win = (win + [normalize([raw], cal)[0]])[-100:]; n += 1
        if len(win) == 100 and n % 10 == 0:
            p = np.mean(run_models(np.array(win)), 0)
            events += [(d.step - 1, e, w) for e, w in d.feed(p)]   # files use 0-based model-run index
    return events


bad = 0
tv = json.load(open(os.path.join(KIT, "test/test_vectors.json")))
cal0 = tv["calibration"]
for c in tv["normalize"]["cases"]:
    x = normalize(c["raw_window"], cal0)
    ok = np.allclose(x[0], c["normalized_first_row"], atol=1e-4) and abs(x.sum() - c["normalized_sum"]) < 1e-4 * max(1, abs(c["normalized_sum"])) * 10
    bad += not ok
for c in tv["model"]["cases"]:
    each = run_models(normalize(c["raw_window"], cal0))
    ok = all(np.allclose(e, w, atol=1e-3) for e, w in zip(each, c["probs_each"])) and np.allclose(np.mean(each, 0), c["probs"], atol=1e-3)
    bad += not ok
dt = tv["decider"]; d = Decider()
got = [(d.step - 1, e, w) for p in dt["probs"] for e, w in d.feed(p)]
want = [(x["step"], x["event"], x["word"]) for x in dt["expected"]]
bad += got != want
if "gaps" in tv:
    g = tv["gaps"]; cal_g = g["calibration"]
    win, n, d, exp_seq, last, got, dropped = [], 0, Decider(), None, None, [], 0
    def push(raw, i):
        global win, n
        win = (win + [normalize([raw], cal_g)[0]])[-100:]; n += 1
        if len(win) == 100 and n % 10 == 0:
            got.extend((i, e, w) for e, w in d.feed(np.mean(run_models(np.array(win)), 0)))
    for i, line in enumerate(g["input"]):
        seq, raw = line[0], [float(v) for v in line[1:]]
        if exp_seq is not None:
            gap = (seq - exp_seq) % 65536
            if gap >= 32768:
                dropped += 1
                if dropped <= 10:
                    continue
                gap = 11                    # spec v3.3: an 11th drop in a row = the glove restarted
            dropped = 0
            if 1 <= gap <= 5:
                for _ in range(gap): push(last, i)
            elif gap > 5:
                if d.pending is not None: got.append((i, "cancel", d.pending))
                win, n, d = [], 0, Decider()
        push(raw, i); last, exp_seq = raw, (seq + 1) % 65536
    want_g = [(x["input"], x["event"], x["word"]) for x in g["expected"]]
    if got != want_g:
        bad += 1; print("GAPS MISMATCH", got[:8], want_g[:8])
    print(f"gaps: {len(g['input'])} samples, {len(want_g)} events -> {'OK' if got == want_g else 'FAIL'}")
print(f"test_vectors: normalize {len(tv['normalize']['cases'])} + model {len(tv['model']['cases'])} cases, decider {len(want)} events -> {'OK' if bad == 0 else 'FAIL'}")
exp = json.load(open(os.path.join(KIT, "mock/expected.json")))["files"]
for name, want in sorted(exp.items()):
    ev = play(os.path.join(KIT, "mock", name))
    words = [w for _, e, w in ev if e in ("word", "confirm")]
    want_words = [x["word"] if isinstance(x, dict) else x for x in want["words"]]
    want_ev = [(x["step"], x["event"], x["word"]) for x in want["events"]]
    got_ev = ev
    ok = words == want_words and got_ev == want_ev
    bad += not ok
    if not ok: print("MISMATCH", name, words, want_words, got_ev[:6], want_ev[:6])
print(f"mock files: {len(exp) - bad}/{len(exp)} match")
sys.exit(1 if bad else 0)
