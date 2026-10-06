"""
common.py — الحاجات المشتركة بين كل السكريبتات
------------------------------------------------
- شكل ملفات الداتا (نفس اللي record.py بيسجله)
- المعايرة (calibration) لكل شخص
- تحويل كل take (ثانيتين) لمصفوفة 100 × 11
- استخراج الـ features للـ Random Forest

كل السكريبتات (التدريب والتوقع الحي) بتستخدم نفس الدوال دي،
عشان الموديل يشوف الداتا بنفس الشكل وقت التدريب ووقت الاستخدام.
"""
import glob
import json
import os

import numpy as np
import pandas as pd

# ===== شكل الداتا =====
# كل سطر في ملفات data/*.csv:
# label, person, take, seq, 5 flex, ax ay az (تسارع), gx gy gz (دوران)
COLS = ["label", "person", "take", "seq",
        "f0", "f1", "f2", "f3", "f4",
        "ax", "ay", "az", "gx", "gy", "gz"]
FLEX = ["f0", "f1", "f2", "f3", "f4"]          # إبهام، سبابة، وسطى، بنصر، خنصر
IMU = ["ax", "ay", "az", "gx", "gy", "gz"]
CHANNELS = FLEX + IMU                            # 11 قناة

SAMPLE_RATE = 50          # 50 قراءة في الثانية
WINDOW = 100              # take = ثانيتين = 100 قراءة
ACC_SCALE = 8192.0        # MPU-6050 على ±4g  → 8192 = 1g
GYRO_SCALE = 65.5         # MPU-6050 على ±500°/s → 65.5 = 1°/s

# الـ 20 إشارة من ملف Sign Vocabulary v1، وبعدهم فئتين "مش كلام":
#   rest   الإيد مرتاحة
#   other  حركة عادية مش إشارة: كتابة، موبايل، كوباية، هرش، شنطة، إشارة بالإيد وانت بتتكلم...
#          من غيرها الموديل مضطر يختار إشارة لأي حركة يشوفها، ودي أكبر سبب للكلمات اللي بتطلع لوحدها.
SIGN_LABELS = ["one", "two", "three", "four", "five", "me", "you", "hello",
               "thanks", "please", "yes", "no", "sorry", "good", "bad", "come",
               "drink", "call", "iloveyou", "hungry"]
NON_WORDS = ["rest", "other"]
LABELS = SIGN_LABELS + NON_WORDS

# تسجيلات المعايرة: كل شخص يسجّل "إيد مفتوحة" و"قبضة" قبل ما يبدأ
CALIB_OPEN = "calib_open"
CALIB_FIST = "calib_fist"
CALIB_DIR = os.path.join("data", "calib")      # معايرة كل شخص من الجلوف: data/calib/<person>.json


# ===== المعايرة من الجلوف =====
# الجلوف بيعمل المعايرة بنفسه (افتح إيدك، اقفل إيدك، لفّ رسغك)، ولما نبعتله "j" بيرد بسطر:
#   #CAL {"v":2,"open":[...5],"fist":[...5],"gyro_bias_raw":[gx,gy,gz],"roll_neutral":..,"roll_min":..,"roll_max":..}
# بنحفظه في data/calib/<person>.json بالشكل ده:
#   {"v":2, "person":"ahmed", "open":[5 أرقام], "fist":[5 أرقام],
#    "gyro_bias":[3 أرقام بنفس وحدة الـ stream الخام], "roll":{"neutral":..,"min":..,"max":..}, "source":"glove"}

def _pick(d, *names):
    """أول مفتاح موجود من الأسامي دي (من غير ما يفرق capital/small)"""
    low = {k.lower(): v for k, v in d.items()}
    for n in names:
        if n in low:
            return low[n]
    return None


def parse_glove_cal(line):
    """
    بتحوّل سطر #CAL اللي جاي من الجلوف لنفس شكل ملف المعايرة.
    بتقبل أسامي مفاتيح مختلفة شوية، عشان لو الفيرموير اتغير.
    """
    text = line.strip()
    if text.startswith("#CAL"):
        text = text[4:].strip()
    d = json.loads(text)
    open_vals = _pick(d, "open", "open_vals", "flex_open")
    fist_vals = _pick(d, "fist", "fist_vals", "flex_fist")
    if open_vals is None or fist_vals is None or len(open_vals) != 5 or len(fist_vals) != 5:
        raise ValueError("سطر #CAL ناقص قيم open أو fist")
    bias = _pick(d, "gyro_bias_raw", "gbias_raw", "gyro_raw")
    if bias is None:                                   # لو الجلوف باعتها بـ °/s نحوّلها للوحدة الخام
        dps = _pick(d, "gyro_bias_dps", "gyro_bias", "gbias", "bias")
        bias = [v * GYRO_SCALE for v in dps] if dps is not None else [0, 0, 0]
    roll = {k: _pick(d, "roll_" + k, k) for k in ("neutral", "min", "max")}
    return {"v": int(_pick(d, "v", "version") or 1), "open": [float(v) for v in open_vals],
            "fist": [float(v) for v in fist_vals], "gyro_bias": [float(v) for v in bias],
            "roll": roll, "source": "glove"}


def save_calib(person, cal, folder=CALIB_DIR):
    os.makedirs(folder, exist_ok=True)
    cal = dict(cal, person=person)
    with open(os.path.join(folder, f"{person}.json"), "w", encoding="utf-8") as f:
        json.dump(cal, f, ensure_ascii=False, indent=1)
    return cal


def load_calib(person, folder=CALIB_DIR):
    path = os.path.join(folder, f"{person}.json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_raw(folder="data"):
    """بتقرا كل ملفات CSV اللي في فولدر data وتجمعهم في جدول واحد"""
    paths = sorted(glob.glob(os.path.join(folder, "*.csv")))
    if not paths:
        raise SystemExit(f"مفيش ملفات CSV في فولدر '{folder}'. سجّل داتا الأول أو شغّل simulate_data.py")
    return pd.concat((pd.read_csv(p, names=COLS) for p in paths), ignore_index=True)


def calibration(df, folder="data"):
    """
    لكل شخص: (قراءة الصوابع مفرودة، قراءة الصوابع مقفولة، الـ gyro bias).
    الأولوية لملف المعايرة اللي جاي من الجلوف (data/calib/<person>.json).
    لو مش موجود، بنحسبها من تسجيلات calib_open و calib_fist القديمة:
    الإيد بتبقى ثابتة في calib_open، فمتوسط الجيروسكوب وقتها هو الـ bias.
    """
    calib = {}
    cdir = os.path.join(folder, "calib")
    for person, g in df.groupby("person"):
        cal = load_calib(person, cdir)
        if cal is not None:
            calib[person] = (np.asarray(cal["open"], float), np.asarray(cal["fist"], float),
                             np.asarray(cal.get("gyro_bias", [0, 0, 0]), float))
            continue
        open_rows = g[g["label"] == CALIB_OPEN]
        fist_rows = g[g["label"] == CALIB_FIST]
        if open_rows.empty or fist_rows.empty:
            print(f"تحذير: الشخص '{person}' ملوش معايرة (python record.py calib {person})، هيتشال من الداتا")
            continue
        calib[person] = (open_rows[FLEX].median().to_numpy(float),
                         fist_rows[FLEX].median().to_numpy(float),
                         open_rows[["gx", "gy", "gz"]].median().to_numpy(float))
    return calib


def normalize(raw, open_vals, fist_vals, gyro_bias=None):
    """
    raw: مصفوفة (عدد القراءات × 11) بالأرقام الخام من الجلوف
    بترجع: flex من 0 لـ 1 تقريباً، والتسارع بوحدة g، والدوران (بعد طرح الـ bias) مقسوم على 250°/s
    """
    raw = np.asarray(raw, dtype=float)
    out = np.empty_like(raw)
    span = fist_vals - open_vals
    span[np.abs(span) < 1] = 1                      # حماية من القسمة على صفر
    out[:, :5] = (raw[:, :5] - open_vals) / span
    out[:, 5:8] = raw[:, 5:8] / ACC_SCALE
    bias = np.zeros(3) if gyro_bias is None else np.asarray(gyro_bias, float)
    out[:, 8:11] = (raw[:, 8:11] - bias) / GYRO_SCALE / 250.0
    return out.astype(np.float32)


def fix_length(arr, n=WINDOW):
    """بتخلي كل take طوله 100 بالظبط: تقص الزيادة أو تكرر آخر قراءة"""
    if len(arr) >= n:
        return arr[:n]
    pad = np.repeat(arr[-1:], n - len(arr), axis=0)
    return np.concatenate([arr, pad])


def load_takes(folder="data"):
    """
    بترجع:
      X       مصفوفة (عدد الـ takes × 100 × 11)
      y       اسم الإشارة لكل take
      persons مين اللي سجّل كل take (عشان نختبر على شخص الموديل مشافوش)
    """
    df = load_raw(folder)
    calib = calibration(df, folder)
    df = df[df["label"].isin(LABELS)]          # من غير المعايرة القديمة وتسجيلات wear الطويلة
    df = df[df["person"].isin(calib)]

    X, y, persons = [], [], []
    for (label, person, take), g in df.groupby(["label", "person", "take"], sort=False):
        if len(g) < WINDOW * 0.8:                  # take ناقص قراءات كتير (BLE قطع مثلاً)
            continue
        # من غير sort على seq: الـ seq في الفيرموير uint8 وبيلف من 255 لـ 0،
        # فلو take عدى على اللفة الترتيب هيبوظ. السطور متسجلة بترتيب وصولها أصلاً.
        arr = normalize(g[CHANNELS].to_numpy(), *calib[person])
        X.append(fix_length(arr))
        y.append(label)
        persons.append(person)
    return np.stack(X), np.array(y), np.array(persons)


def context_windows(X, y, persons, copies=3, max_shift=30, seed=0):
    """
    في التوقع الحي النافذة بتتحرك، فالإشارة نادراً ما بتيجي في نص النافذة بالظبط.
    هنا بنحط كل take بين تسجيلين rest لنفس الشخص (زي ما بيحصل في الحقيقة:
    إيد مرتاحة، إشارة، إيد مرتاحة) وناخد نافذة مزاحة لحد 0.6 ثانية.
    كده الموديل يتعلم يعرف الإشارة حتى لو بدأت بدري أو متأخر.
    """
    rng = np.random.default_rng(seed)
    out_X, out_y = [], []
    for p in np.unique(persons):
        rest = X[(persons == p) & np.isin(y, NON_WORDS)]   # قبل وبعد الإشارة: راحة أو حركة عادية
        if len(rest) == 0:
            continue
        for i in np.where(persons == p)[0]:
            for _ in range(copies):
                before = rest[rng.integers(len(rest))]
                after = rest[rng.integers(len(rest))]
                long = np.concatenate([before, X[i], after])
                shift = int(rng.integers(-max_shift, max_shift + 1))
                out_X.append(long[WINDOW + shift: 2 * WINDOW + shift])
                out_y.append(y[i])
    if not out_X:                                  # مفيش تسجيلات rest: نكمل من غيرها
        print("تحذير: مفيش takes لـ rest، سجّلها عشان التوقع الحي يشتغل كويس")
        return X[:0], y[:0]
    return np.stack(out_X), np.array(out_y)


def transition_windows(X, y, persons, per_take=2, blur=25, max_off=45, seed=1):
    """
    في الجملة الإيد بتنتقل من إشارة للتانية على طول من غير rest في النص،
    والنافذة اللي في نص الانتقال فيها نص إشارة ونص التانية.
    هنا بنحط كل take جنب take تاني لنفس الشخص وناخد نوافذ حوالين نقطة الانتقال:
    لو نص النافذة قريب من نقطة الانتقال (أقل من blur قراءة) بنسميها rest
    عشان الموديل ميقولش كلمة غلط وقت الانتقال، وغير كده بنسميها الإشارة الغالبة.
    """
    rng = np.random.default_rng(seed)
    out_X, out_y = [], []
    for p in np.unique(persons):
        idx = np.where((persons == p) & ~np.isin(y, NON_WORDS))[0]
        for i in idx:
            for _ in range(per_take):
                j = idx[rng.integers(len(idx))]
                if y[j] == y[i]:
                    continue
                pair = np.concatenate([X[i], X[j]])
                off = int(rng.integers(-max_off, max_off + 1))    # نص النافذة بالنسبة لنقطة الانتقال
                start = WINDOW // 2 + off
                out_X.append(pair[start:start + WINDOW])
                out_y.append("rest" if abs(off) < blur else (y[i] if off < 0 else y[j]))
    if not out_X:
        return X[:0], y[:0]
    return np.stack(out_X), np.array(out_y)


def features(X):
    """
    للـ Random Forest: بيحوّل كل take (100 × 11) لـ 77 رقم.
    لكل قناة: المتوسط، التذبذب، أقل وأعلى قيمة، متوسط أول ربع وآخر ربع
    (عشان يعرف الإيد راحت فين)، وكمية الحركة.
    """
    q = X.shape[1] // 4
    parts = [X.mean(1), X.std(1), X.min(1), X.max(1),
             X[:, :q].mean(1), X[:, -q:].mean(1),
             np.abs(np.diff(X, axis=1)).mean(1)]
    return np.concatenate(parts, axis=1)
