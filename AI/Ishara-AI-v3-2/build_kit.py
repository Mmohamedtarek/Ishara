"""
build_kit.py — بيجهز Ishara-Mobile-Kit لفريق الموبايل من الموديل الحالي
------------------------------------------------------------------------
  model/   ishara_cnn.tflite + ishara_cnn_2.tflite + ishara_cnn_3.tflite (ensemble) + labels.txt + decider.json
  mock/    جلافز وهمية بنفس سطر الـ USB serial: ملف لكل فئة لشخصين (A و B)، جمل، وحركة عادية
           + expected.json (الكلمات اللي التطبيق لازم يطلّعها من كل ملف) + ble_frames.txt
  test/    test_vectors.json: normalize، الموديل، والـ Decider: أرقام التطبيق لازم تطابقها

التشغيل (بعد train_cnn.py و eval_live.py --tune):
  python build_kit.py ../Ishara-Mobile-Kit
"""
import json
import os
import shutil
import struct
import sys

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import numpy as np

import live
import simulate_data as sim
from common import LABELS, SIGN_LABELS, WINDOW, normalize

OUT = sys.argv[1] if len(sys.argv) > 1 else "../Ishara-Mobile-Kit"
PERSONS = {"A": 777, "B": 778}       # أشخاص وهميين مش في التدريب ولا الاختبار
REPEATS = 3                          # كل ملف: (راحة، الإشارة، راحة) 3 مرات


def glove_cal_line(person):
    c = sim.glove_cal(person)
    cal = {"v": 2, "open": c["open"], "fist": c["fist"], "gyro_bias_raw": c["gyro_bias"],
           "roll_neutral": 0.0, "roll_min": -45.0, "roll_max": 45.0}
    return cal, "#CAL " + json.dumps(cal, separators=(",", ":"))


def to_lines(raw):
    return [",".join(str(int(v)) for v in [k % 256, *row]) for k, row in enumerate(np.asarray(raw).round().astype(int))]


def decode(predictor, cfg, raw, cal):
    o, f, b = (np.asarray(cal[k], float) for k in ("open", "fist", "gyro_bias_raw"))
    x = normalize(np.asarray(raw, float), o, f, b)
    ends = np.array([e for e in range(WINDOW, len(x) + 1) if e % live.STEP == 0])
    W = np.stack([x[e - WINDOW:e] for e in ends])
    P = predictor.batch(W)
    d = live.Decider(predictor.classes, cfg)
    said, events = [], []
    for i, p in enumerate(P):
        for kind, w in d.step(p):
            events.append({"step": i, "sample": int(ends[i]), "event": kind, "word": w})
            if kind in ("word", "confirm"):
                said.append({"word": w, "sample": int(ends[i])})
    decode.events = events
    return said, W, P, ends


def main():
    cfg = live.decider_config("cnn")
    members = cfg.get("models") or live.ENSEMBLE
    predictor = live.Predictor("cnn", members=members)
    cfg_out = {k: v for k, v in cfg.items() if k not in live.Decider.LEVEL_KEYS and k != "confirm_on_rest"}
    cfg_out.update(confirm_rf=False, models=[m + ".tflite" for m in members])     # التطبيق مفيهوش Random Forest
    for d in ("model", "mock", "test"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)
    for f in os.listdir(os.path.join(OUT, "model")):     # الموديلات القديمة تتشال
        if f.endswith(".tflite"):
            os.remove(os.path.join(OUT, "model", f))
    for m in members:
        shutil.copy(m + ".tflite", os.path.join(OUT, "model"))
    shutil.copy("labels.txt", os.path.join(OUT, "model"))
    json.dump({"cnn": cfg_out}, open(os.path.join(OUT, "model", "decider.json"), "w"), indent=2)

    expected, report = {}, []
    for name, seed in PERSONS.items():
        sim.rng = np.random.default_rng(seed)
        person = sim.make_person()
        cal, cal_line = glove_cal_line(person)
        folder = os.path.join(OUT, "mock", name)
        os.makedirs(folder, exist_ok=True)
        for f in os.listdir(folder):                  # ملفات كلمات قديمة اتشالت من الـ labels تتمسح
            if f.endswith(".csv"):
                os.remove(os.path.join(folder, f))
        for label in LABELS:
            want = [label] * REPEATS if label in SIGN_LABELS else []
            for attempt in range(25):                # بناخد أمثلة الموديل بيفهمها (دي داتا تطوير، مش اختبار)
                seq = []
                for _ in range(REPEATS):
                    seq += ["rest", label, "rest"] if label in SIGN_LABELS else ["rest", label, label]
                raw = sim.stitch([sim.make_sample(s, person) for s in seq])
                said, *_ = decode(predictor, cfg_out, raw, cal)
                if [s["word"] for s in said] == want:
                    break
            open(os.path.join(folder, f"{label}.csv"), "w").write("\n".join([cal_line] + to_lines(raw)) + "\n")
            expected[f"{name}/{label}.csv"] = {"words": said, "events": decode.events}
            report.append((f"{name}/{label}", attempt + 1, [s["word"] for s in said] == want))
        # جمل متصلة
        sents = [list(s) for s in live.DEMO_SENTENCES]
        seq, words = [], []
        for s in sents:
            seq += ["rest"] + s + ["rest"]
            words += s
        for attempt in range(25):
            raw = sim.stitch([sim.make_sample(s, person) for s in seq])
            said, *_ = decode(predictor, cfg_out, raw, cal)
            if [s["word"] for s in said] == words:
                break
        open(os.path.join(folder, "sentences.csv"), "w").write("\n".join([cal_line] + to_lines(raw)) + "\n")
        expected[f"{name}/sentences.csv"] = {"words": said, "events": decode.events}
        report.append((f"{name}/sentences", attempt + 1, [s["word"] for s in said] == words))
        # 5 دقايق حركة عادية: مفيش ولا كلمة المفروض تطلع
        n = int(5 * 60 * 50 / (WINDOW - 10)) + 1
        raw = sim.stitch([sim.make_sample("rest" if r < 0.45 else "other", person) for r in sim.rng.random(n)])
        said, *_ = decode(predictor, cfg_out, raw, cal)
        open(os.path.join(folder, "everyday.csv"), "w").write("\n".join([cal_line] + to_lines(raw)) + "\n")
        expected[f"{name}/everyday.csv"] = {"words": said, "events": decode.events}
        report.append((f"{name}/everyday", 1, not said))
        if name == "A":
            hello_raw = np.loadtxt(os.path.join(folder, "hello.csv"), delimiter=",", skiprows=1)[:, 1:]
            write_frames(os.path.join(OUT, "mock", "ble_frames.txt"), hello_raw[:50])
            test_vectors(os.path.join(OUT, "test", "test_vectors.json"), predictor, cfg_out, raw_for_tests(folder), cal)
    json.dump({"note": "for each file: 'words' = confirmed words the app must show and speak, with the sample index (1-based "
                       "count of samples read) when each is confirmed; 'events' = every Decider event (word / tentative / "
                       "confirm / cancel) at its model step. Same as the Python reference.",
               "files": expected}, open(os.path.join(OUT, "mock", "expected.json"), "w"), indent=1)
    bad = [r for r in report if not r[2]]
    print(f"mock: {len(report)} ملف، {len(bad)} مش مطابق للمطلوب: {bad}")
    print("محاولات:", sum(r[1] for r in report) - len(report), "إعادة")


def raw_for_tests(folder):
    return np.loadtxt(os.path.join(folder, "sentences.csv"), delimiter=",", skiprows=1)[:, 1:]


def write_frames(path, raw):
    lines = ["# DATA frames encoded from mock/A/hello.csv samples 0-49, per BLE-CONTRACT.md section 4",
             "# format: <hex frame> | then one line per decoded sample: seq f0 f1 f2 f3 f4 ax ay az gx gy gz"]
    for k in range(0, len(raw), 5):
        block = np.asarray(raw[k:k + 5]).round().astype(int)
        frame = struct.pack("<BBH", 1, len(block), k) + b"".join(struct.pack("<11h", *r) for r in block)
        lines.append(frame.hex())
        for j, r in enumerate(block):
            lines.append("  " + " ".join(str(v) for v in [k + j, *r]))
    open(path, "w").write("\n".join(lines) + "\n")


def test_vectors(path, predictor, cfg, raw, cal):
    said, W, P, ends = decode(predictor, cfg, raw, cal)
    o, f, b = (np.asarray(cal[k], float) for k in ("open", "fist", "gyro_bias_raw"))
    pick = np.linspace(0, len(W) - 1, 6).round().astype(int)
    # نفس النوافذ دي من ملفات الـ tflite نفسها (اللي في الـ Kit): كل موديل لوحده، والمتوسط
    import tensorflow as tf
    its = []
    for m in cfg["models"]:
        it = tf.lite.Interpreter(model_path=m)
        it.allocate_tensors()
        its.append((it, it.get_input_details()[0]["index"], it.get_output_details()[0]["index"]))
    model_cases = []
    for i in pick:
        each = []
        for it, inp, out in its:
            it.set_tensor(inp, W[i][None].astype(np.float32))
            it.invoke()
            each.append(it.get_tensor(out)[0])
        e = int(ends[i])
        model_cases.append({"raw_window": np.asarray(raw[e - WINDOW:e]).round().astype(int).tolist(),
                            "normalized_first_row": [round(float(v), 6) for v in W[i][0]],
                            "normalized_sum": round(float(W[i].sum()), 4),
                            "probs_each": [[round(float(v), 6) for v in p] for p in each],
                            "probs": [round(float(v), 6) for v in np.mean(each, axis=0)]})
    json.dump({
        "labels": predictor.classes,
        "calibration": cal,
        "normalize": {"note": "flex = (raw - open) / (fist - open), |fist-open|<1 -> 1; acc = raw / 8192; "
                              "gyro = (raw - gyro_bias_raw) / 65.5 / 250. Tolerance 1e-4.",
                      "cases": [{"raw_window": c["raw_window"], "normalized_first_row": c["normalized_first_row"],
                                 "normalized_sum": c["normalized_sum"]} for c in model_cases]},
        "model": {"note": "each model: input float32 [1,100,11] = normalized window, oldest sample first; output 22 "
                          "probabilities in labels order. probs_each = each model in decider.json 'models' order; probs = "
                          "their average (what the Decider gets). Tolerance 1e-3.",
                  "cases": [{"raw_window": c["raw_window"], "probs_each": c["probs_each"], "probs": c["probs"]} for c in model_cases]},
        "decider": {"note": "feed these probability vectors one by one (one per model run, every 10 samples) into the "
                            "Decider with this config; it must emit exactly these events at these steps.",
                    "config": cfg, "probs": [[round(float(v), 6) for v in p] for p in P],
                    "expected": [{"step": e["step"], "event": e["event"], "word": e["word"]} for e in decode.events]},
    }, open(path, "w"))
    print(f"test vectors: {len(model_cases)} نافذة، {len(P)} خطوة decider، {len(said)} كلمة")


if __name__ == "__main__":
    main()
