"""
build_kit.py — بيجهز Ishara-Mobile-Kit لفريق الموبايل من الموديل الحالي
------------------------------------------------------------------------
  model/   ishara_cnn.tflite + ishara_cnn_2.tflite + ishara_cnn_3.tflite (ensemble) + labels.txt + decider.json
  mock/    جلافز وهمية بنفس سطر الـ USB serial: ملف لكل فئة لشخصين (A و B)، جمل، وحركة عادية
           + practice/: كل إشارة ممسوكة (أو متكررة) زي المتعلم في الـ Learn، المفروض تطلّع الكلمة مرة واحدة
           + calibration/: open.csv و fist.csv و turn.csv للمعايرة (بنفس قواعد الفيرموير)
           + expected.json (الكلمات اللي التطبيق لازم يطلّعها من كل ملف) + ble_frames.txt
  test/    test_vectors.json: normalize، الموديل، والـ Decider، والفجوات في BLE (gaps): أرقام التطبيق لازم تطابقها

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

OUT = sys.argv[1] if len(sys.argv) > 1 else ("../../app/Ishara-Mobile-Kit" if os.path.isdir("../../app/Ishara-Mobile-Kit") else "../Ishara-Mobile-Kit")
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
        # تمرين الـ Learn: (راحة، الإشارة ممسوكة ضعف الوقت، راحة) → الكلمة مرة واحدة
        pfolder = os.path.join(folder, "practice")
        os.makedirs(pfolder, exist_ok=True)
        for f in os.listdir(pfolder):
            if f.endswith(".csv"):
                os.remove(os.path.join(pfolder, f))
        for label in SIGN_LABELS:
            for attempt in range(25):
                raw = sim.stitch([sim.make_sample(s, person) for s in ["rest", label, label, "rest"]])
                said, *_ = decode(predictor, cfg_out, raw, cal)
                if [s["word"] for s in said] == [label]:
                    break
            open(os.path.join(pfolder, f"{label}.csv"), "w").write("\n".join([cal_line] + to_lines(raw)) + "\n")
            expected[f"{name}/practice/{label}.csv"] = {"words": said, "events": decode.events}
            report.append((f"{name}/practice/{label}", attempt + 1, [s["word"] for s in said] == [label]))
        if name == "A":
            hello_raw = np.loadtxt(os.path.join(folder, "hello.csv"), delimiter=",", skiprows=1)[:, 1:]
            write_frames(os.path.join(OUT, "mock", "ble_frames.txt"), hello_raw[:50])
            test_vectors(os.path.join(OUT, "test", "test_vectors.json"), predictor, cfg_out, raw_for_tests(folder), cal)
            gaps = gap_case(predictor, cfg_out, raw_for_tests(folder), cal)
    tv_path = os.path.join(OUT, "test", "test_vectors.json")
    tv = json.load(open(tv_path))
    tv["gaps"] = gaps
    json.dump(tv, open(tv_path, "w"))
    json.dump({"note": "for each file: 'words' = confirmed words the app must show and speak, with the sample index (1-based "
                       "count of samples read) when each is confirmed; 'events' = every Decider event (word / tentative / "
                       "confirm / cancel) at its model step. Same as the Python reference.",
               "files": expected}, open(os.path.join(OUT, "mock", "expected.json"), "w"), indent=1)
    calibration_mocks()
    bad = [r for r in report if not r[2]]
    print(f"mock: {len(report)} ملف، {len(bad)} مش مطابق للمطلوب: {bad}")
    print("محاولات:", sum(r[1] for r in report) - len(report), "إعادة")


CAL_STILL_GYRO_STD_DPS = 3.0     # firmware config.h: a still hand is below this, per gyro axis
CAL_MIN_ROLL_RANGE_DEG = 30.0    # firmware config.h: TURN must cover at least this much roll


def calibration_mocks(out=None):
    """
    mock/<person>/calibration/{open,fist,turn}.csv: what the glove's sensors read during the three
    calibration steps, consistent with that person's #CAL line (the first line of every file):
      open / fist: 2.4 s, hand still (gyro noise ~0.8 deg/s), fingers at the #CAL open / fist values
      turn:        3.4 s, palm turned left and right (+-42 deg roll about the forearm), then still
    Roll follows the firmware: roll = atan2(ay, az), roll rate on gyro X. Gyro values include the
    person's raw gyro bias, so after subtracting gyro_bias_raw a still hand reads ~0.
    """
    out = out or OUT
    for name, seed in PERSONS.items():
        sim.rng = np.random.default_rng(seed)          # the same person and #CAL as the other mock files
        person = sim.make_person()
        cal, cal_line = glove_cal_line(person)
        rng = np.random.default_rng(seed + 9000)       # separate noise, so no other file changes
        o, f, bias = (np.asarray(cal[k], float) for k in ("open", "fist", "gyro_bias_raw"))
        g1 = sim.ACC_SCALE if hasattr(sim, "ACC_SCALE") else 8192.0
        gs = sim.GYRO_SCALE if hasattr(sim, "GYRO_SCALE") else 65.5

        def rows(flex, roll_deg, rate_dps):
            n = len(roll_deg)
            r = np.radians(roll_deg)
            acc = np.stack([np.zeros(n), np.sin(r), np.cos(r)], 1) * g1 + rng.normal(0, 30, (n, 3))
            gyro = np.tile(bias, (n, 1)) + rng.normal(0, 0.8 * gs, (n, 3))
            gyro[:, 0] += np.asarray(rate_dps) * gs
            fl = np.asarray(flex, float) + rng.normal(0, 8, (n, 5))
            return np.hstack([np.clip(fl, 0, 4095), np.clip(acc, -32768, 32767), np.clip(gyro, -32768, 32767)])

        folder = os.path.join(out, "mock", name, "calibration")
        os.makedirs(folder, exist_ok=True)
        still = np.zeros(120)
        files = {"open": rows(np.tile(o, (120, 1)), still, still),
                 "fist": rows(np.tile(f, (120, 1)), still, still)}
        t = np.arange(150) / 50.0
        roll = 42.0 * np.sin(2 * np.pi * t / 3.0)
        rate = 42.0 * (2 * np.pi / 3.0) * np.cos(2 * np.pi * t / 3.0)
        roll, rate = np.concatenate([roll, np.zeros(20)]), np.concatenate([rate, np.zeros(20)])
        relaxed = o + 0.15 * (f - o)
        files["turn"] = rows(np.tile(relaxed, (len(roll), 1)), roll, rate)
        for step, raw in files.items():
            with open(os.path.join(folder, f"{step}.csv"), "w") as fh:
                fh.write("\n".join([cal_line] + to_lines(raw)) + "\n")
    print("calibration mocks: open / fist / turn for", ", ".join(PERSONS))


def gap_case(predictor, cfg, raw, cal):
    """
    نفس الجمل، بس بـ seq (16 bit، بيلف من 65535 لـ 0) وفيها مشاكل BLE زي الحقيقة:
    فجوة 3 قراءات، seq مكرر، seq راجع لورا، وفجوة 12 قراءة بعد كلمة مبدئية على طول (لازم تتلغي).
    """
    raw = np.asarray(raw).round().astype(int)
    n = len(raw)
    seqs = [(65500 + k) % 65536 for k in range(n)]
    sr, tent_at = live.StreamRecognizer(predictor, cfg, cal), None
    for k in range(n):
        if any(e == "tentative" for e, _ in sr.feed(seqs[k], raw[k])) and k > 800 and tent_at is None:
            tent_at = k
    assert tent_at is not None, "no tentative word after sample 800"
    lines, k = [], 0
    while k < n:
        if k == 300:                        # فجوة 3: القراءات 300-302 ضاعت
            k += 3
            continue
        if k == tent_at + 1:                # فجوة 12 بعد الكلمة المبدئية
            k += 12
            continue
        lines.append([seqs[k], *raw[k].tolist()])
        if k == 500:                        # نفس الرسالة وصلت مرتين
            lines.append([seqs[k], *raw[k].tolist()])
        if k == 700:                        # رسالة قديمة وصلت متأخر
            lines.append([seqs[k - 5], *raw[k - 5].tolist()])
        k += 1
    sr, expected = live.StreamRecognizer(predictor, cfg, cal), []
    for i, ln in enumerate(lines):
        for e, w in sr.feed(ln[0], ln[1:]):
            expected.append({"input": i, "event": e, "word": w})
    assert any(e["event"] == "cancel" for e in expected), "the 12-sample gap should cancel a tentative word"
    print(f"gaps: {len(lines)} قراءة، {len(expected)} حدث، أول seq {lines[0][0]}، الكلمة المبدئية عند القراءة {tent_at}")
    return {"note": "feed 'input' one sample at a time: [seq, f0..f4, ax, ay, az, gx, gy, gz]. seq is uint16 and wraps "
                    "65535 -> 0. Gap rule (AI-SPEC section 4): 1-5 missing samples -> repeat the last good sample that many "
                    "times (they count as samples); more than 5 -> clear the window, restart the sample counter, reset the "
                    "Decider, and emit cancel for a pending tentative word first; a duplicate or older seq "
                    "((seq - expected) mod 65536 >= 32768) is dropped and not counted. 'expected' = every event, with the "
                    "0-based index of the input sample that produced it. The file has a 3-sample gap, a duplicate, an older "
                    "seq, a wrap, and a 12-sample gap right after a tentative word.",
            "calibration": cal, "config": cfg, "input": lines, "expected": expected}


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
