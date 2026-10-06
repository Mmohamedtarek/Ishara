"""
eval_live.py — التقييم الكامل للتوقع الحي، بنفس الكود اللي live.py بيستخدمه
-----------------------------------------------------------------------------
بيعمل أشخاص جداد (الموديل مشافهمش) بالداتا الوهمية ويقيس:

  1. الجمل:  Word Error Rate = (كلمة غلط + كلمة ناقصة + كلمة زيادة) ÷ عدد الكلمات المطلوبة
  2. الكلمات اللي بتطلع لوحدها: ساعات من حركة عادية (كتابة، موبايل، كوباية، إشارة بالإيد، ...)
     من غير ولا إشارة، وأي كلمة تطلع فيهم غلط. بيطلع العدد في الدقيقة، وأقصى رقم ممكن بثقة 95%.
  3. التأخير: من أول الإشارة لحد ما الكلمة تطلع.
  4. دقة كل إشارة لوحدها، وأكتر لخبطة، واختبارات ضغط (الجلوف متلبس مايل، حساس بايظ، ...).

الاستخدام:
  python eval_live.py                    التقييم الكامل (CNN، 30 ساعة حركة عادية)
  python eval_live.py --hours 5          أسرع
  python eval_live.py --model rf
  python eval_live.py --tune             بيدوّر على أحسن إعدادات للـ Decider على أشخاص "validation"
                                         ويحفظها في decider.json، وبعدين بيقيّم على أشخاص تانيين خالص
"""
import argparse
import collections
import itertools
import json
import os
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import numpy as np

import live
import simulate_data as sim
from common import SIGN_LABELS, WINDOW, normalize

STEP = live.STEP
TEST_SEED, VAL_SEED = 1000, 5000        # أشخاص الاختبار وأشخاص الضبط مختلفين عن بعض ومختلفين عن التدريب
MIN_PER_PERSON = 30                      # كل شخص بيعمل نص ساعة حركة عادية


# ===================== الأشخاص والتيارات =====================
def new_person(seed):
    sim.rng = np.random.default_rng(seed)
    person = sim.make_person()
    o = person["straight"]
    f = person["straight"] + np.array([0.6, 1, 1, 1, 1]) * (person["bent"] - person["straight"])
    return person, o, f, sim.estimated_bias(person)


def windows_of(raw, o, f, b):
    """نفس اللي live.py بيعمله: نافذة ثانيتين كل STEP قراءات"""
    x = normalize(raw, o, f, b)
    ends = np.arange(WINDOW, len(x) + 1)
    ends = ends[ends % STEP == 0]
    return np.stack([x[e - WINDOW:e] for e in ends]), ends


def sentence_streams(seed, n_random=8):
    """الجمل التجريبية + جمل عشوائية من 1 لـ 4 كلمات، الإيد بتنتقل من كلمة للتانية على طول"""
    person, o, f, b = new_person(seed)
    rng = np.random.default_rng(seed + 7)
    sentences = [list(s) for s in live.DEMO_SENTENCES]
    for _ in range(n_random):
        k = int(rng.integers(1, 5))
        s = []
        while len(s) < k:
            w = SIGN_LABELS[rng.integers(len(SIGN_LABELS))]
            if not s or s[-1] != w:
                s.append(w)
        sentences.append(s)
    out = []
    for s in sentences:
        seq = ["rest"] + s + ["rest"]
        takes = [sim.make_sample(lbl, person) for lbl in seq]
        starts = [i * (WINDOW - 10) for i in range(len(seq))]   # stitch بيشيل 10 قراءات في كل وصلة
        raw = sim.stitch(takes)
        W, ends = windows_of(raw, o, f, b)
        out.append({"words": s, "W": W, "ends": ends, "starts": starts[1:-1]})
    return out


def everyday_stream(seed, minutes):
    """حركة عادية بس: 45% راحة و55% حركات (كل أنواع other)، ورا بعض بانتقال ناعم"""
    person, o, f, b = new_person(seed)
    n = int(minutes * 60 * sim.SAMPLE_RATE / (WINDOW - 10)) + 1
    labels = np.where(sim.rng.random(n) < 0.45, "rest", "other")
    raw = sim.stitch([sim.make_sample(l, person) for l in labels])
    W, ends = windows_of(raw, o, f, b)
    return {"W": W, "ends": ends, "minutes": len(raw) / sim.SAMPLE_RATE / 60}


# ===================== القرار على تيار =====================
def run_decider(probs, cfg, classes, rf_top=None, stats=None):
    """بيرجع [(رقم النافذة، الكلمة)] للكلمات المتأكدة بس (اللي بتظهر وتتقال)، بنفس منطق live.Decider.
    stats (dict اختياري): بيتزود فيه عدد الكلمات المبدئية اللي ظهرت واتشالت (flicker)"""
    confirm = None
    if cfg.get("confirm_rf") and rf_top is not None:
        state = {"i": 0}

        def confirm(_, label):
            return rf_top[state["i"]] == label
    d = live.Decider(classes, cfg, confirm)
    said = []
    for i, p in enumerate(probs):
        if confirm is not None:
            state["i"] = i
        for kind, w in d.step(p):
            if kind in ("word", "confirm"):
                said.append((i, w))
            elif kind == "cancel" and stats is not None:
                stats["flicker"] = stats.get("flicker", 0) + 1
    return said


def align(ref, hyp):
    """(غلط، ناقص، زيادة) بأقل عدد تعديلات"""
    n, m = len(ref), len(hyp)
    d = [[None] * (m + 1) for _ in range(n + 1)]
    d[0] = [(j, 0, 0, j) for j in range(m + 1)]
    for i in range(1, n + 1):
        d[i][0] = (i, 0, i, 0)
        for j in range(1, m + 1):
            c = ref[i - 1] != hyp[j - 1]
            a, b_, e = d[i - 1][j - 1], d[i - 1][j], d[i][j - 1]
            d[i][j] = min((a[0] + c, a[1] + c, a[2], a[3]), (b_[0] + 1, b_[1], b_[2] + 1, b_[3]), (e[0] + 1, e[1], e[2], e[3] + 1))
    return d[n][m][1:]


def upper95(k, minutes):
    """أقصى معدل في الدقيقة متوافق مع إننا شفنا k غلطة (Poisson، ثقة 95%)"""
    table = {0: 3.00, 1: 4.74, 2: 6.30, 3: 7.75, 4: 9.15, 5: 10.51}
    up = table.get(k, k + 1.96 * np.sqrt(k) + 2)
    return up / minutes


# ===================== التقييم =====================
class Bench:
    def __init__(self, predictor, seed0, people, hours, rf=None):
        t0 = time.time()
        self.classes = predictor.classes
        self.sent = []
        for p in range(people):
            for st in sentence_streams(seed0 + p):
                st["P"] = predictor.batch(st["W"])
                st["R"] = self._rf(rf, st["W"])
                self.sent.append(st)
        self.every = []
        per = max(1, int(round(hours * 60 / MIN_PER_PERSON)))
        for p in range(per):
            st = everyday_stream(seed0 + 500 + p, hours * 60 / per)
            st["P"] = predictor.batch(st["W"])
            st["R"] = self._rf(rf, st["W"])
            st.pop("W")
            self.every.append(st)
        self.minutes = sum(s["minutes"] for s in self.every)
        print(f"  ({people} شخص للجمل، {self.minutes / 60:.1f} ساعة حركة عادية، {time.time() - t0:.0f} ثانية)")

    @staticmethod
    def _rf(rf, W):
        if rf is None:
            return None
        P = rf.batch(W)
        return [rf.classes[i] for i in P.argmax(1)]

    def score(self, cfg):
        S = D = I = words = 0
        stats, sstats = {}, {}
        lat = []
        for st in self.sent:
            said = run_decider(st["P"], cfg, self.classes, st["R"], sstats)
            hyp = [w for _, w in said]
            s, d, i = align(st["words"], hyp)
            S, D, I, words = S + s, D + d, I + i, words + len(st["words"])
            k = 0
            for idx, w in said:                           # التأخير للكلمات الصح بالترتيب
                if k < len(st["words"]) and w == st["words"][k]:
                    lat.append((st["ends"][idx] - st["starts"][k]) / sim.SAMPLE_RATE)
                    k += 1
        false = []
        for st in self.every:
            false += [w for _, w in run_decider(st["P"], cfg, self.classes, st["R"], stats)]
        return {"wer": (S + D + I) / words * 100, "S": S, "D": D, "I": I, "words": words,
                "false": len(false), "false_words": collections.Counter(false).most_common(5),
                "false_per_min": len(false) / self.minutes, "false_upper95": upper95(len(false), self.minutes),
                "minutes": self.minutes, "latency": float(np.median(lat)) if lat else None,
                "flicker_per_min": stats.get("flicker", 0) / self.minutes}


def take_report(predictor, seed0=TEST_SEED, people=12, takes=6, stress=None):
    classes = predictor.classes
    idx = {c: i for i, c in enumerate(classes)}
    conf = np.zeros((len(classes), len(classes)), int)
    W, Y = [], []
    for p in range(people):
        person, o, f, b = new_person(seed0 + 300 + p)
        if stress == "tilt30":
            a = np.radians(30)
            person["tilt"] = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]]) @ person["tilt"]
        if stress == "fast":
            person["speed"] *= 1.6
        for lbl in classes:
            for _ in range(takes):
                raw = sim.make_sample(lbl, person).astype(float)
                if stress == "dead_finger":
                    raw[:, 3] = 2600
                W.append(normalize(raw, o, f, b))
                Y.append(idx[lbl])
    pred = predictor.batch(np.stack(W)).argmax(1)
    for t, q in zip(Y, pred):
        conf[t, q] += 1
    return conf


def show_takes(conf, classes):
    acc = np.trace(conf) / conf.sum() * 100
    rec = np.diag(conf) / conf.sum(1) * 100
    worst = sorted(zip(rec, classes))[:5]
    pairs = sorted(((conf[i, j], classes[i], classes[j]) for i in range(len(classes)) for j in range(len(classes)) if i != j), reverse=True)[:5]
    print(f"  دقة الإشارة لوحدها: {acc:.1f}%")
    print("  أضعف إشارات: " + ", ".join(f"{c} {r:.0f}%" for r, c in worst))
    print("  أكتر لخبطة:  " + ", ".join(f"{a}→{b} ({n})" for n, a, b in pairs if n))
    return acc


def show(r, title):
    print(f"\n{title}")
    print(f"  WER على الجمل: {r['wer']:.1f}%   (غلط {r['S']}، ناقص {r['D']}، زيادة {r['I']} من {r['words']} كلمة)")
    print(f"  كلمات طلعت لوحدها: {r['false']} في {r['minutes'] / 60:.1f} ساعة = {r['false_per_min']:.4f} في الدقيقة"
          f"   (أقصى رقم بثقة 95%: {r['false_upper95']:.4f})  {r['false_words']}")
    print(f"  التأخير: {r['latency']:.2f} ثانية" if r["latency"] else "  التأخير: -")
    if "flicker_per_min" in r:
        print(f"  كلمات مبدئية ظهرت واتشالت (وسط الحركة العادية): {r['flicker_per_min']:.4f} في الدقيقة")


# ===================== جلسات لبس طويلة مع talk mode =====================
def wear_sessions(predictor, cfg, sessions=10, hours=3.0, convs_per_hour=6, talk_off_s=None, seed0=TEST_SEED + 2000):
    """
    جلسة = الجلوف ملبوس 3 ساعات: حركة عادية طول الوقت، ومحادثات قليلة (كل محادثة 1-4 جمل).
    المستخدم بيفتح talk mode أول المحادثة، وبيقفل لوحده بعد talk_off_s ثانية من غير كلام.
    بنعدّ: الكلمات اللي طلعت لوحدها والـ talk mode مفتوح (برّاه مستحيل تطلع)، والـ WER في المحادثات.
    """
    rng = np.random.default_rng(seed0)
    false = total_min = 0
    S = D = I = words = 0
    for k in range(sessions):
        person, o, f, b = new_person(seed0 + k)
        plan = []                                   # [(label, conv_id أو -1)]
        n_takes = int(hours * 3600 * sim.SAMPLE_RATE / (WINDOW - 10))
        conv_at = set(rng.choice(n_takes, int(convs_per_hour * hours), replace=False))
        conv, refs, i = 0, {}, 0
        while i < n_takes:
            if i in conv_at:
                sent = []
                for _ in range(int(rng.integers(1, 5))):
                    w = SIGN_LABELS[rng.integers(len(SIGN_LABELS))]
                    if not sent or sent[-1] != w:
                        sent.append(w)
                plan += [("rest", conv)] + [(w, conv) for w in sent] + [("rest", conv)]
                refs[conv] = sent
                conv += 1
                i += len(sent) + 2
            else:
                plan.append(("rest" if sim.rng.random() < 0.45 else "other", -1))
                i += 1
        raw = sim.stitch([sim.make_sample(l, person) for l, _ in plan])
        W, ends = windows_of(raw, o, f, b)
        P = predictor.batch(W)
        take_of = np.minimum(ends // (WINDOW - 10), len(plan) - 1)
        d = live.Decider(predictor.classes, cfg)
        talk_until, said = -1.0, {c: [] for c in refs}
        for j, p in enumerate(P):
            tsec = ends[j] / sim.SAMPLE_RATE
            lbl, cid = plan[take_of[j]]
            if cid >= 0 and plan[take_of[j]][0] == "rest" and (take_of[j] == 0 or plan[take_of[j] - 1][1] != cid):
                talk_until = max(talk_until, tsec + (talk_off_s or 0))   # المستخدم داس "اتكلم" (لو فيه talk mode)
            for w in [w for kind, w in d.step(p) if kind in ("word", "confirm")]:   # الكلمات المتأكدة بس
                if talk_off_s is not None and tsec > talk_until:
                    continue
                talk_until = tsec + (talk_off_s or 0)
                if cid >= 0:
                    said[cid].append(w)
                else:
                    false += 1
        for c, ref in refs.items():
            s_, d_, i_ = align(ref, said[c])
            S, D, I, words = S + s_, D + d_, I + i_, words + len(ref)
        total_min += len(raw) / sim.SAMPLE_RATE / 60
    return {"sessions": sessions, "hours": total_min / 60, "false": false, "false_per_min": false / total_min,
            "false_upper95": upper95(false, total_min), "wer": (S + D + I) / words * 100, "S": S, "D": D, "I": I, "words": words}


# ===================== الضبط =====================
GRID = {"confidence": [0.85, 0.9, 0.95, 0.97, 0.98, 0.99, 0.995], "hold": [2, 3, 4, 6, 8],
        "max_null": [0.01, 0.03, 0.1], "confirm_rf": [False, True]}


IDLE_GRID = {"confidence": [0.85, 0.9, 0.95, 0.98], "hold": [2, 3, 4, 5], "max_null": [0.02, 0.05, 0.1], "active_s": [4, 6, 8]}
ACTIVE_GRID = {"confidence": [0.5, 0.6, 0.7, 0.8], "hold": [1, 2], "max_null": [0.3, 0.6, 1.0]}


def tune(bench, kind, target):
    """
    الضبط على مرحلتين، والهدف بالترتيب: الكلمات اللي بتطلع لوحدها تحت target، بعدها أقل WER، بعدها أقل تأخير.
      1. حالة idle (أول كلمة واضحة جدًا) + مدة active، والكلمة المبدئية والـ active ثابتين على إعدادات سهلة
      2. حالة active (جوه المحادثة) بأحسن idle
    """
    def key(r):
        over = max(0.0, r["false_per_min"] - target)
        return (over > 0, over, r["wer"], r["latency"] or 9)

    models = [m for m in live.ENSEMBLE if os.path.exists(m + ".tflite")]
    base = {"smooth": 3, "confirm_rf": False, "models": models, "confirm_s": 3.5,
            "tentative": {"confidence": 0.6, "hold": 1, "max_null": 0.3, "per_class": {}}}   # الكلمة المبدئية
    active = {"confidence": 0.5, "hold": 1, "max_null": 0.3, "per_class": {}}
    best = None
    for c, h, m, a_s in itertools.product(*IDLE_GRID.values()):
        cfg = dict(base, active_s=a_s, idle={"confidence": c, "hold": h, "max_null": m, "per_class": {}}, active=dict(active))
        r = bench.score(cfg)
        if best is None or key(r) < key(best[1]):
            best = (cfg, r)
    cfg, r = best
    for c, h, m in itertools.product(*ACTIVE_GRID.values()):
        cand = dict(cfg, active={"confidence": c, "hold": h, "max_null": m, "per_class": {}})
        rc = bench.score(cand)
        if key(rc) < key(r):
            cfg, r = cand, rc
    # إشارات لسه بتطلع لوحدها كأول كلمة: نرفع حدها في idle بس
    for _ in range(4):
        if r["false_per_min"] <= target or not r["false_words"]:
            break
        idle = cfg["idle"]
        for w, _n in r["false_words"]:
            idle["per_class"][w] = round(min(0.995, max(idle["per_class"].get(w, idle["confidence"]), idle["confidence"]) + 0.02), 3)
        rc = bench.score(cfg)
        if key(rc) < key(r):
            r = rc
    return cfg, r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=["cnn", "rf"], default="cnn")
    ap.add_argument("--hours", type=float, default=30, help="ساعات الحركة العادية في الاختبار")
    ap.add_argument("--people", type=int, default=12)
    ap.add_argument("--tune", action="store_true")
    ap.add_argument("--target", type=float, default=0.0, help="أقصى كلمات لوحدها في الدقيقة وقت الضبط (0 = ولا كلمة في ساعات الـ validation)")
    ap.add_argument("--no-stress", action="store_true")
    ap.add_argument("--sessions", type=int, default=0, help="جلسات لبس 3 ساعات مع talk mode")
    ap.add_argument("--talk-off", type=float, default=None, help="لو عايز تقيس talk mode: بيقفل بعد كام ثانية (من غيره: الترجمة شغالة على طول)")
    args = ap.parse_args()

    predictor = live.Predictor(args.model)
    rf = live.Predictor("rf") if args.model == "cnn" and os.path.exists("ishara_rf.joblib") else None

    if args.tune:
        print("الضبط على أشخاص validation:")
        vb = Bench(predictor, VAL_SEED, people=8, hours=max(5.0, args.hours * 2 / 3), rf=None)
        cfg, r = tune(vb, args.model, args.target)
        show(r, "أحسن إعدادات على validation:")
        try:
            allcfg = json.load(open(live.DECIDER_FILE, encoding="utf-8"))
        except (OSError, ValueError):
            allcfg = {}
        allcfg[args.model] = cfg
        json.dump(allcfg, open(live.DECIDER_FILE, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
        print(f"  اتحفظت في {live.DECIDER_FILE}: {cfg}")

    cfg = live.decider_config(args.model)
    if args.sessions:
        r = wear_sessions(predictor, cfg, sessions=args.sessions, talk_off_s=args.talk_off)
        mode = f"مع talk mode بيقفل بعد {args.talk_off:.0f} ث" if args.talk_off else "الترجمة شغالة على طول، من غير talk mode"
        print(f"\nجلسات لبس ({r['sessions']} × 3 ساعات = {r['hours']:.0f} ساعة، {mode}):")
        print(f"  كلمات طلعت لوحدها: {r['false']} = {r['false_per_min']:.4f} في الدقيقة (أقصى رقم بثقة 95%: {r['false_upper95']:.4f})")
        print(f"  WER في المحادثات: {r['wer']:.1f}%  (غلط {r['S']}، ناقص {r['D']}، زيادة {r['I']} من {r['words']})")
        return
    print(f"\nالاختبار على أشخاص جداد خالص ({args.model.upper()}):")
    tb = Bench(predictor, TEST_SEED, people=args.people, hours=args.hours, rf=rf)
    show(tb.score(cfg), f"النتيجة بإعدادات {live.DECIDER_FILE}:")
    print()
    show_takes(take_report(predictor), predictor.classes)
    if not args.no_stress:
        print("  اختبارات ضغط (دقة الإشارة لوحدها):")
        for s, name in (("tilt30", "الجلوف متلبس مايل 30°"), ("dead_finger", "حساس البنصر بايظ"), ("fast", "إشارات أسرع 1.6×")):
            c = take_report(predictor, stress=s)
            print(f"    {name}: {np.trace(c) / c.sum() * 100:.1f}%")


if __name__ == "__main__":
    main()
