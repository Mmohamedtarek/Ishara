"""
check_words.py — كل كلمة لوحدها: بتتقال صح ولا لأ؟
----------------------------------------------------
لكل إشارة: إيد مرتاحة ← الإشارة ← إيد مرتاحة، وبعدين نفس اللي live.py بيعمله بالظبط
(نافذة ثانيتين كل 10 قراءات، الموديل، والـ Decider بإعدادات decider.json).
"اتقالت صح" = الكلمة دي بس اتقالت بصوت مرة واحدة (الكلمة المبدئية اللي اتشالت متتحسبش).

  1. من فولدر data: كل take متسجل لكل إشارة، مع takes راحة لنفس الشخص من data برضه
  2. أشخاص جداد: أشخاص وهميين الموديل عمره ما شافهم (ده الرقم الحقيقي)

التشغيل:
  python check_words.py
  python check_words.py --new 30          عدد الأشخاص الجداد (كل واحد بيعمل كل إشارة 5 مرات)
  python check_words.py --model rf
"""
import argparse
import collections
import os

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import numpy as np

import eval_live as ev
import live
import simulate_data as sim
from common import CHANNELS, SIGN_LABELS, calibration, load_raw, setup_console

NEW_SEED = 30000          # أشخاص مختلفين عن التدريب والضبط والاختبار
TAKES_NEW = 5


def decode(predictor, cfg, streams):
    """streams: [(قراءات خام، (open، fist، bias))] ← الكلمات اللي اتقالت لكل واحد"""
    Ws, sizes = [], []
    for raw, (o, f, b) in streams:
        W, _ = ev.windows_of(raw, o, f, b)
        Ws.append(W)
        sizes.append(len(W))
    P = predictor.batch(np.concatenate(Ws))
    out, s = [], 0
    for n in sizes:
        out.append([w for _, w in ev.run_decider(P[s:s + n], cfg, predictor.classes)])
        s += n
    return out


def verdict(word, said):
    # بالإنجليزي: الـ console بتاع Windows بيعرض العربي مقطّع ومقلوب
    if said == [word]:
        return "ok"
    if not said:
        return "missed"
    if word not in said:
        return "said " + " ".join(said)
    return "extra: " + " ".join(said)


def from_data(predictor, cfg, rng):
    df = load_raw("data")
    calib = calibration(df, "data")
    takes = {k: g[CHANNELS].to_numpy(float) for k, g in df.groupby(["label", "person", "take"], sort=False)}
    rest = collections.defaultdict(list)
    for (label, person, _), raw in takes.items():
        if label == "rest" and len(raw) >= 80:
            rest[person].append(raw)
    res = {}
    for word in SIGN_LABELS:
        streams = []
        for (label, person, _), raw in takes.items():
            if label != word or person not in calib or not rest[person] or len(raw) < 80:
                continue
            r = [rest[person][i] for i in rng.integers(len(rest[person]), size=3)]
            streams.append((sim.stitch([r[0], raw, r[1], r[2]]), calib[person]))
        res[word] = [verdict(word, s) for s in decode(predictor, cfg, streams)]
    return res


def new_people(predictor, cfg, n):
    res = collections.defaultdict(list)
    for p in range(n):
        person, o, f, b = ev.new_person(NEW_SEED + p)
        for word in SIGN_LABELS:
            streams = [(sim.stitch([sim.make_sample(s, person) for s in ["rest", word, "rest", "rest"]]), (o, f, b))
                       for _ in range(TAKES_NEW)]
            res[word] += [verdict(word, s) for s in decode(predictor, cfg, streams)]
    return res


def show(title, res):
    print(f"\n{title}")
    print(f"    {'word':9s} {'correct':>9s}   {'%':>6s}   most common mistakes")
    total = ok = 0
    for word in SIGN_LABELS:
        v = res[word]
        k = v.count("ok")
        total, ok = total + len(v), ok + k
        bad = collections.Counter(x for x in v if x != "ok").most_common(2)
        mark = "OK " if k == len(v) else ("~  " if k / len(v) >= 0.9 else "LOW")
        print(f"{mark} {word:9s} {k:4d}/{len(v):<4d} {k / len(v) * 100:5.1f}%   "
              + (", ".join(f"{b} x{n}" for b, n in bad)))
    print(f"    TOTAL: {ok}/{total} = {ok / total * 100:.1f}%")
    print("    (OK = 100%, ~ = 90% or more, LOW = under 90%.  missed = nothing was said, "
          "extra = another word was said too)")


def main():
    ap = argparse.ArgumentParser(description="Each word alone (rest, sign, rest): is it said correctly?")
    ap.add_argument("--model", choices=["cnn", "rf"], default="cnn")
    ap.add_argument("--new", type=int, default=20, help="number of new people")
    args = ap.parse_args()
    predictor = live.Predictor(args.model)
    cfg = live.decider_config(args.model)
    show(f"1) Every take in the data folder, each word alone ({args.model.upper()}):",
         from_data(predictor, cfg, np.random.default_rng(0)))
    show(f"2) {args.new} NEW people the model never saw, each word alone {TAKES_NEW} times:",
         new_people(predictor, cfg, args.new))


if __name__ == "__main__":
    setup_console()
    main()
