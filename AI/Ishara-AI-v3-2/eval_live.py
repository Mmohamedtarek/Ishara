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
                                         (24 شخص للجمل و30 ساعة حركة عادية: --val-hours)
                                         ويحفظها في decider.json، وبعدين بيقيّم على أشخاص تانيين خالص
  python eval_live.py --tune --model rf  نفس الكلام للـ Random Forest
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
from common import SIGN_LABELS, WINDOW, normalize, setup_console

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


def sentence_streams(seed, n_random=8, isolated=True):
    """
    الجمل التجريبية + جمل عشوائية من 1 لـ 4 كلمات، الإيد بتنتقل من كلمة للتانية على طول.
    isolated: وكمان كل إشارة من الـ 20 لوحدها مرة (إيد مرتاحة ← الإشارة ← إيد مرتاحة). من غيرها الضبط
    مكانش شايف الكلمة المفردة تقريبًا، فطلع إعدادات بتقول 81% بس من الكلمات لما تتعمل لوحدها.
    """
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
    n_sent = len(sentences)
    if isolated:
        sentences += [[w] for w in SIGN_LABELS]
    out = []
    for k, s in enumerate(sentences):
        # الكلمة المفردة بعدها 4 ثواني راحة: الإيد بتفضل مرتاحة بعدها، ومحتاجين نشوف هل اتأكدت ولا اتشالت
        seq = ["rest"] + s + (["rest", "rest"] if k >= n_sent else ["rest"])
        takes = [sim.make_sample(lbl, person) for lbl in seq]
        starts = [i * (WINDOW - 10) for i in range(len(seq))]   # stitch بيشيل 10 قراءات في كل وصلة
        raw = sim.stitch(takes)
        W, ends = windows_of(raw, o, f, b)
        out.append({"words": s, "W": W, "ends": ends, "starts": starts[1:-1], "isolated": k >= n_sent})
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


def extra_words(ref, hyp):
    """الكلمات الزيادة في hyp (اللي اتقالت ومكانتش في الجملة)، بنفس المحاذاة بأقل عدد تعديلات"""
    n, m = len(ref), len(hyp)
    d = np.zeros((n + 1, m + 1), int)
    d[:, 0], d[0, :] = np.arange(n + 1), np.arange(m + 1)
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i, j] = min(d[i - 1, j - 1] + (ref[i - 1] != hyp[j - 1]), d[i - 1, j] + 1, d[i, j - 1] + 1)
    i, j, out = n, m, []
    while j:
        if i and d[i, j] == d[i - 1, j - 1] + (ref[i - 1] != hyp[j - 1]):
            i, j = i - 1, j - 1
        elif i and d[i, j] == d[i - 1, j] + 1:
            i -= 1
        else:
            out.append(hyp[j - 1])
            j -= 1
    return out


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
        iso_ok = iso_n = iso_err = 0
        stats, sstats = {}, {}
        lat, extra = [], collections.Counter()
        for st in self.sent:
            said = run_decider(st["P"], cfg, self.classes, st["R"], sstats)
            hyp = [w for _, w in said]
            s, d, i = align(st["words"], hyp)
            if st.get("isolated"):                        # كلمة لوحدها: بتتحسب لوحدها مش في WER الجمل
                iso_n, iso_ok, iso_err = iso_n + 1, iso_ok + (hyp == st["words"]), iso_err + s + d + i
                continue
            S, D, I, words = S + s, D + d, I + i, words + len(st["words"])
            if i:
                extra.update(extra_words(st["words"], hyp))
            k = 0
            for idx, w in said:                           # التأخير للكلمات الصح بالترتيب
                if k < len(st["words"]) and w == st["words"][k]:
                    lat.append((st["ends"][idx] - st["starts"][k]) / sim.SAMPLE_RATE)
                    k += 1
        false = []
        for st in self.every:
            false += [w for _, w in run_decider(st["P"], cfg, self.classes, st["R"], stats)]
        return {"wer": (S + D + I) / words * 100, "S": S, "D": D, "I": I, "words": words,
                "iso_ok": iso_ok, "iso_n": iso_n,
                # الغلط الكلي اللي الضبط بيقلله: كلمات الجمل والكلمات المفردة مع بعض
                "err": (S + D + I + iso_err) / (words + iso_n) * 100,
                "extra_words": extra.most_common(5), "false": len(false), "false_words": collections.Counter(false).most_common(5),
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
    if r.get("iso_n"):
        print(f"  كل كلمة لوحدها: {r['iso_ok']}/{r['iso_n']} = {r['iso_ok'] / r['iso_n'] * 100:.1f}% اتقالت صح")
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


# (0.98 و active_s 8 عمرهم ما اتختاروا في كل مرات الضبط، فاتشالوا عشان الضبط ياخد نص الوقت)
IDLE_GRID = {"confidence": [0.85, 0.9, 0.95], "hold": [2, 3, 4, 5], "max_null": [0.02, 0.05, 0.1], "active_s": [4, 6]}
ACTIVE_GRID = {"confidence": [0.5, 0.6, 0.7, 0.8], "hold": [1, 2], "max_null": [0.3, 0.6, 1.0]}
TENTATIVE_GRID = {"confidence": [0.5, 0.6, 0.7], "max_null": [0.2, 0.3, 0.5]}
# الكلمة المفردة: تتأكد لما الإيد ترجع ترتاح، لو كانت واضحة (rest_conf) لفترة (rest_run) واحتمال "مش كلام" وصل لأقل من
# rest_null. 0 = مقفول. على 110 ساعة وأشخاص جداد: 0.7 / 3 / 0.03 ← الكلمة لوحدها 82% ← 88%، والكلمات الغلط من كلمة كل
# 5.5 ساعة لكلمة كل 3.8. بـ 0.05: الكلمة لوحدها 90% بس الكلمات الغلط كلمة كل 2.75 ساعة
REST_GRID = {"confirm_on_rest": [0, 2, 3], "rest_conf": [0.7, 0.9], "rest_run": [1, 3], "rest_null": [0.03, 0.05, 1.0]}
# الـ Random Forest احتمالاته أوطى من الـ CNN (متوسط 300 شجرة)، فمحتاج أرقام أوطى. قبل كده ملوش إعدادات
# في decider.json خالص، فكان بيشتغل بالـ DEFAULTS، والـ WER على الجمل كان 70%.
# (جربنا أرقام أوطى من كده: الـ WER بينزل شوية، بس الكلمات اللي بتطلع لوحدها بتزيد 6 مرات على أشخاص جداد)
RF_GRIDS = {"idle": {"confidence": [0.5, 0.6, 0.7, 0.8], "hold": [2, 3, 4, 5], "max_null": [0.1, 0.2, 0.3], "active_s": [4, 6, 8]},
            "active": {"confidence": [0.3, 0.4, 0.5, 0.6], "hold": [1, 2], "max_null": [0.4, 0.6, 1.0]},
            "tentative": {"confidence": [0.35, 0.45, 0.55], "max_null": [0.3, 0.5, 0.7]},
            "rest": {"confirm_on_rest": [0, 2, 3], "rest_conf": [0.5, 0.6, 0.7], "rest_run": [1, 4], "rest_null": [0.3, 1.0]}}


def tune(bench, kind, target):
    """
    الضبط على 4 مراحل، والهدف بالترتيب: الكلمات اللي بتطلع لوحدها تحت target، بعدها أقل غلط
    (كلمات الجمل والكلمات المفردة مع بعض)، بعدها أقل تأخير.
      1. حالة idle (أول كلمة واضحة جدًا) + مدة active، والكلمة المبدئية والـ active ثابتين على إعدادات سهلة
      2. حالة active (جوه المحادثة) بأحسن idle
      3. الكلمة المبدئية (أول كلمة في الجملة لما تكون واضحة بس مش جدًا)
      4. تأكيد الكلمة المفردة لما الإيد ترجع ترتاح (confirm_on_rest)
    """
    def key(r):
        over = max(0.0, r["false_per_min"] - target)
        return (over > 0, over, r.get("err", r["wer"]), r["latency"] or 9)

    grids = RF_GRIDS if kind == "rf" else {"idle": IDLE_GRID, "active": ACTIVE_GRID, "tentative": TENTATIVE_GRID,
                                           "rest": REST_GRID}
    tent0 = {"confidence": 0.45, "max_null": 0.5} if kind == "rf" else {"confidence": 0.6, "max_null": 0.3}
    # pair_level: الكلمة اللي بتأكد كلمة مبدئية لازم تعدّي مستوى tentative مش active بس. على أشخاص جداد
    # الـ WER فضل زي ما هو، والكلمات اللي بتطلع لوحدها قلّت من 9 لـ 5 في 20 ساعة
    base = {"smooth": 3, "confirm_rf": False, "confirm_s": 3.5, "pair_level": "tentative",
            "confirm_on_rest": 2, "rest_conf": 0.7 if kind == "cnn" else 0.6, "rest_run": 3,
            "rest_null": 0.03 if kind == "cnn" else 1.0,
            "tentative": dict(tent0, hold=1, per_class={})}   # الكلمة المبدئية
    if kind == "cnn":
        base["models"] = [m for m in live.ENSEMBLE if os.path.exists(m + ".tflite")]
    active = {"confidence": min(grids["active"]["confidence"]), "hold": 1, "max_null": 0.3 if kind == "cnn" else 0.6,
              "per_class": {}}
    best = None
    for c, h, m, a_s in itertools.product(*grids["idle"].values()):
        cfg = dict(base, active_s=a_s, idle={"confidence": c, "hold": h, "max_null": m, "per_class": {}}, active=dict(active))
        r = bench.score(cfg)
        if best is None or key(r) < key(best[1]):
            best = (cfg, r)
    cfg, r = best
    for c, h, m in itertools.product(*grids["active"].values()):
        cand = dict(cfg, active={"confidence": c, "hold": h, "max_null": m, "per_class": {}})
        rc = bench.score(cand)
        if key(rc) < key(r):
            cfg, r = cand, rc
    for c, m in itertools.product(*grids["tentative"].values()):
        cand = dict(cfg, tentative={"confidence": c, "hold": 1, "max_null": m, "per_class": {}})
        rc = bench.score(cand)
        if key(rc) < key(r):
            cfg, r = cand, rc
    keys = list(grids["rest"])
    for vals in itertools.product(*grids["rest"].values()):
        p = dict(zip(keys, vals))
        if p["confirm_on_rest"] == 0 and any(p[k] != grids["rest"][k][0] for k in keys[1:]):
            continue                                       # مقفول: الباقي مش فارق
        cand = dict(cfg, **p)
        rc = bench.score(cand)
        if key(rc) < key(r):
            cfg, r = cand, rc
    # كلمات بتطلع زيادة جوه الجمل: غالبًا إشارة ثابتة شكلها زي آخر إشارة متحركة
    # (آخر bye = إيد مفتوحة ثابتة = five، وآخر thanks شبه four). نرفع حدها في active لو ده بيقلل الـ WER
    for w, _n in r["extra_words"]:
        for conf in (0.6, 0.7, 0.8, 0.9):
            cand = json.loads(json.dumps(cfg))
            cand["active"]["per_class"][w] = conf
            rc = bench.score(cand)
            if key(rc) < key(r):
                cfg, r = cand, rc
    # إشارات لسه بتطلع لوحدها كأول كلمة: نرفع حدها في idle بس
    # (على نسخة: قبل كده التعديل كان بيفضل في الإعدادات حتى لو النتيجة بقت أوحش)
    for _ in range(4):
        if r["false_per_min"] <= target or not r["false_words"]:
            break
        cand = json.loads(json.dumps(cfg))
        idle = cand["idle"]
        for w, _n in r["false_words"]:
            idle["per_class"][w] = round(min(0.995, max(idle["per_class"].get(w, idle["confidence"]), idle["confidence"]) + 0.02), 3)
        rc = bench.score(cand)
        if key(rc) >= key(r):
            break
        cfg, r = cand, rc
    return cfg, r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=["cnn", "rf"], default="cnn")
    ap.add_argument("--hours", type=float, default=30, help="ساعات الحركة العادية في الاختبار")
    ap.add_argument("--people", type=int, default=12)
    ap.add_argument("--tune", action="store_true")
    ap.add_argument("--val-hours", type=float, default=30,
                    help="ساعات الحركة العادية وقت الضبط. الكلمات اللي بتطلع لوحدها نادرة، فلو الساعات قليلة (10) "
                         "كل الإعدادات بتطلّع نفس العدد، والضبط بيختار أسهل إعدادات وبتطلّع كلمات أكتر على ناس جداد")
    # 0.005 = حوالي كلمة غلط كل 3.3 ساعة حركة عادية (الإعداد "المتوازن": الكلمة لوحدها 89%، والجمل WER 3.2%).
    # أقل من كده الضبط بيختار hold 5: الكلمات الغلط بتقل لكلمة كل 20 ساعة، بس الكلمة المفردة بتنزل لـ 85%
    # والـ WER بيوصل 5.6%، لإن أول كلمة في الجملة بتضيع أكتر
    ap.add_argument("--target", type=float, default=0.005,
                    help="أقصى كلمات لوحدها في الدقيقة وقت الضبط (0 = أقل عدد ممكن، حتى لو كلمات أكتر هتضيع من الجمل)")
    ap.add_argument("--no-stress", action="store_true")
    ap.add_argument("--sessions", type=int, default=0, help="جلسات لبس 3 ساعات مع talk mode")
    ap.add_argument("--talk-off", type=float, default=None, help="لو عايز تقيس talk mode: بيقفل بعد كام ثانية (من غيره: الترجمة شغالة على طول)")
    args = ap.parse_args()

    predictor = live.Predictor(args.model)
    rf = live.Predictor("rf") if args.model == "cnn" and os.path.exists("ishara_rf.joblib") else None

    if args.tune:
        print("الضبط على أشخاص validation:")
        # 24 شخص للجمل (الجمل رخيصة جنب ساعات الحركة العادية): مع 8 بس الكلمات الزيادة كانت نادرة
        # لدرجة إن الضبط مكانش بيشوفها، وبتظهر على أشخاص الاختبار
        vb = Bench(predictor, VAL_SEED, people=24, hours=args.val_hours, rf=None)
        cfg, r = tune(vb, args.model, args.target)
        show(r, "أحسن إعدادات على validation:")
        try:
            with open(live.DECIDER_FILE, encoding="utf-8") as f:
                allcfg = json.load(f)
        except (OSError, ValueError):
            allcfg = {}
        allcfg[args.model] = cfg
        with open(live.DECIDER_FILE, "w", encoding="utf-8", newline="\n") as f:      # LF زي Linux
            json.dump(allcfg, f, indent=2, ensure_ascii=False)
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
    setup_console()
    main()
