"""
simulate_data.py — داتا وهمية بنفس شكل تسجيل الجلوف الحقيقي
-------------------------------------------------------------
بيعمل فولدر data/ فيه takes لكل الـ 22 فئة من ملف Sign Vocabulary v2 (ASL)،
لكذا شخص، بنفس الأعمدة اللي record.py بيسجلها بالظبط.

الهدف: نجرّب ونقارن الموديلات دلوقتي، ولما الجلوف يجهز
نمسح فولدر data ونسجّل داتا حقيقية، وباقي الكود يفضل زي ما هو.

ملحوظة: الداتا الوهمية أسهل من الحقيقية. الأرقام اللي هتطلع
هنا بتقارن بين الموديلات، لكنها مش الدقة اللي هتقولها في المناقشة.
"""
import os
import shutil

import numpy as np

from common import ACC_SCALE, CALIB_FIST, CALIB_OPEN, GYRO_SCALE, SAMPLE_RATE, WINDOW, save_calib, setup_console, show_help

rng = np.random.default_rng(7)

PEOPLE = [f"p{i}" for i in range(1, 11)]        # 10 أشخاص، زي أقل عدد ننصح بيه في الداتا الحقيقية
TAKES_PER_SIGN = 20
OTHER_TAKES = 150                                # حركات عادية لكل شخص (أنواع كتير، فمحتاجين أكتر)
t = np.arange(WINDOW) / SAMPLE_RATE              # الوقت من 0 لـ 2 ثانية

# ===== شكل الصوابع: 0 = مفرود، 1 = مقفول (إبهام، سبابة، وسطى، بنصر، خنصر) =====
OPEN = [0, 0, 0, 0, 0]
FIST = [0.6, 1, 1, 1, 1]                          # الإبهام نايم على الصوابع
INDEX = [1, 0, 1, 1, 1]
C_SHAPE = [0.4, 0.5, 0.5, 0.5, 0.5]
B_HAND = [0.8, 0, 0, 0, 0]                        # كف مفرود والإبهام نايم على الكف (hello / thanks)
W_HAND = [0.8, 0, 0, 0, 1]                        # سبابة + وسطى + بنصر، والإبهام ماسك الخنصر (water)
NO_OPEN = [0.3, 0, 0, 1, 1]                       # سبابة + وسطى مفرودين والإبهام برّه (no، قبل القفلة)

# ===== اتجاه الإيد = اتجاه الجاذبية اللي الـ MPU-6050 حاسس بيه =====
UP = [0, 1, 0]                 # الإيد واقفة والصوابع لفوق
TO_CHEST = [0, 0.3, 0.95]      # السبابة ناحية الصدر
FORWARD = [0, 0.3, -0.95]      # السبابة لقدام
ON_CHEST = [0, 0.2, 0.98]      # الكف على الصدر
AT_FOREHEAD = [-0.3, 0.9, 0.2]  # الإيد جنب الجبهة ومايلة ناحية الراس (hello)
OUT_FOREHEAD = [0.35, 0.9, 0.2] # الإيد بعدت عن الجبهة لبرّه
AT_MOUTH = [0.3, 0.9, 0.3]      # الصوابع لفوق عند البق والكف ناحية الشمال (water، زي Lifeprint)
SHOULDER = [0, 0.75, -0.65]     # قدام الكتف والصوابع لقدام (no)

# كل إشارة: (الصوابع، الاتجاه في الأول، الاتجاه في الآخر، نوع الحركة)
# الأشكال والحركات من ملف Sign Vocabulary v2، وهي الشكل المعتاد في ASL
SIGNS = {
    "one":      (INDEX, UP, UP, "still"),
    "two":      ([1, 0, 0, 1, 1], UP, UP, "still"),
    "three":    ([0, 0, 0, 1, 1], UP, UP, "still"),
    "four":     ([1, 0, 0, 0, 0], UP, UP, "still"),
    "five":     (OPEN, UP, UP, "still"),
    "me":       (INDEX, TO_CHEST, TO_CHEST, "jab_in"),    # السبابة بتلمس الصدر (Lifeprint)، مش ثابتة زي one
    "you":      (INDEX, FORWARD, FORWARD, "jab_out"),    # السبابة بتشاور لقدام ناحية الشخص
    "hello":    (B_HAND, AT_FOREHEAD, OUT_FOREHEAD, "salute"),
    "thanks":   (B_HAND, [0, 0.6, 0.8], [0, 0.8, -0.6], "push"),
    "please":   (OPEN, ON_CHEST, ON_CHEST, "circle"),
    "yes":      (FIST, UP, UP, "nod"),
    "no":       (NO_OPEN, SHOULDER, SHOULDER, "snap"),
    "sorry":    (FIST, ON_CHEST, ON_CHEST, "circle"),
    "water":    (W_HAND, AT_MOUTH, AT_MOUTH, "tap"),
    "bye":      (OPEN, UP, UP, "flap"),
    "come":     (INDEX, [0, 0.45, -0.9], [0, 0.85, 0.5], "arc_in"),   # السبابة لقدام وتيجي ناحيتك مرة واحدة (Lifeprint)
    "drink":    (C_SHAPE, [0.6, 0.8, 0], [0.6, 0.4, 0.7], "tilt"),
    "call":     ([0, 1, 1, 1, 0], [0.8, 0.6, 0], [0.8, 0.6, 0], "still"),
    "iloveyou": ([0, 0, 1, 1, 0], UP, UP, "still"),
    "hungry":   (C_SHAPE, ON_CHEST, ON_CHEST, "down"),
}


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def rotate_small(v, deg):
    """يميل الاتجاه شوية بزاوية عشوائية، لإن كل واحد بيعمل الإشارة بميل مختلف"""
    return unit(np.asarray(v, float) + rng.normal(0, np.radians(deg), 3))


def envelope(t0, dur):
    """منحنى ناعم من 0 لـ 1 ولـ 0 تاني، بيحدد إمتى الحركة بتحصل جوه الـ take"""
    x = np.clip((t - t0) / dur, 0, 1)
    return np.sin(np.pi * x) ** 2, x


def motion(kind, amp, speed):
    """بيرجع (تسارع إضافي، دوران، تغيير في ثني كل صباع، تقدّم الحركة) لكل نوع حركة"""
    acc = np.zeros((WINDOW, 3))
    gyro = np.zeros((WINDOW, 3))
    bend = np.zeros((WINDOW, 5))
    t0 = rng.uniform(0.1, 0.7)
    dur = rng.uniform(1.0, 1.3) / speed
    env, x = envelope(t0, dur)
    tau = np.clip(t - t0, 0, None)
    f = speed

    if kind == "wave":          # تلويح يمين وشمال (مش إشارة في v2، بس بيتعمل وانت بتتكلم)
        s = np.sin(2 * np.pi * 2.0 * f * tau)
        gyro[:, 2] = 150 * amp * s * env
        acc[:, 0] = 0.4 * amp * s * env
    elif kind == "salute":      # hello: الإيد تبعد عن الجبهة لبرّه مرة واحدة
        gyro[:, 2] = -110 * amp * env
        acc[:, 0] = 0.35 * amp * np.sin(2 * np.pi * x) * (x > 0) * (x < 1)
        acc[:, 2] = -0.15 * amp * env
    elif kind == "snap":        # no: السبابة والوسطى بيقفلوا على الإبهام مرتين
        sn = 0.5 * (1 - np.cos(2 * np.pi * 2.2 * f * tau)) * (env > 0.05)
        bend[:, 0] = 0.4 * sn
        bend[:, 1] = 0.6 * sn
        bend[:, 2] = 0.6 * sn
        gyro[:, 0] = 25 * amp * np.sin(2 * np.pi * 2.2 * f * tau) * env
    elif kind == "flap":        # bye: الصوابع الأربعة تتني لتحت وترجع مع بعض
        sn = 0.5 * (1 - np.cos(2 * np.pi * 2.5 * f * tau)) * (env > 0.05)
        bend[:, 1:5] = 0.7 * sn[:, None]
        gyro[:, 0] = 20 * amp * np.sin(2 * np.pi * 2.5 * f * tau) * env
    elif kind == "tap":         # water: طرف السبابة يخبط على الدقن مرتين
        sn = np.sin(2 * np.pi * 2.5 * f * tau) * env
        acc[:, 2] = 0.2 * amp * sn
        gyro[:, 0] = 45 * amp * sn
    elif kind == "shake":       # هزة أسرع وأصغر (مش إشارة في v2، بس بيتعمل وانت بتتكلم)
        s = np.sin(2 * np.pi * 2.6 * f * tau)
        gyro[:, 2] = 110 * amp * s * env
        acc[:, 0] = 0.25 * amp * s * env
    elif kind == "nod":         # yes: القبضة تنزل وتطلع
        s = np.sin(2 * np.pi * 2.0 * f * tau)
        gyro[:, 0] = 150 * amp * s * env
        acc[:, 1] = 0.3 * amp * s * env
    elif kind == "circle":      # please / sorry: دوائر على الصدر
        a = 2 * np.pi * 1.2 * f * tau
        acc[:, 0] = 0.3 * amp * np.sin(a) * env
        acc[:, 1] = 0.3 * amp * np.cos(a) * env
        gyro[:, 0] = 80 * amp * np.cos(a) * env
        gyro[:, 1] = 80 * amp * np.sin(a) * env
    elif kind == "push":        # thanks: من الدقن لقدام
        gyro[:, 0] = -90 * amp * env
        acc[:, 2] = -0.5 * amp * np.sin(2 * np.pi * x) * (x > 0) * (x < 1)
    elif kind == "tilt":        # drink: الإيد تميل ناحية البق
        gyro[:, 1] = 120 * amp * env
    elif kind == "down":        # hungry: الإيد تنزل على الصدر
        acc[:, 1] = -0.4 * amp * np.sin(2 * np.pi * x) * (x > 0) * (x < 1)
        gyro[:, 0] = 25 * amp * env
    elif kind == "arc_in":      # come: حركة واحدة سريعة، السبابة مفرودة وبتلف ناحيتك
        gyro[:, 0] = 170 * amp * env
        acc[:, 2] = 0.45 * amp * np.sin(2 * np.pi * x) * (x > 0) * (x < 1)
    elif kind in ("jab_in", "jab_out"):
        # me / you: حركة قصيرة (حوالي نص ثانية) السبابة بتروح فيها ناحية الصدر أو لقدام وترجع.
        # من غيرها one و me و you مفيش فرق بينهم غير اتجاه الإيد، ولو الجلوف مايل شوية بيبقوا شبه بعض.
        sign = 1 if kind == "jab_in" else -1
        jx = np.clip((t - t0) / (rng.uniform(0.4, 0.6) / speed), 0, 1)
        acc[:, 2] = sign * 0.35 * amp * np.sin(2 * np.pi * jx) * (jx > 0) * (jx < 1)
        gyro[:, 0] = sign * 60 * amp * np.sin(np.pi * jx) ** 2
    elif kind == "beckon":      # إشارة "تعالى" بالسبابة (مش ASL، بتتعمل كحركة عادية)
        bend[:, 1] = 0.5 * (1 - np.cos(2 * np.pi * 1.5 * f * tau)) * (env > 0.05)
        gyro[:, 0] = 30 * amp * np.sin(2 * np.pi * 1.5 * f * tau) * env
    return acc, gyro, bend, x


def make_take(sign, person):
    """take واحد = 100 قراءة خام بالظبط زي اللي الـ ESP32 بيبعتها"""
    fingers, pose0, pose1, kind = SIGNS[sign] if sign != "rest" else (None, None, None, "rest")
    amp = person["amp"] * rng.uniform(0.6, 1.3)
    speed = person["speed"] * rng.uniform(0.75, 1.3)
    if rng.random() < 0.1:                          # take مهمل: الحركة صغيرة
        amp *= 0.4

    if kind == "rest":          # إيد مرتاحة أو ماشي أو بيعمل حاجة عادية
        shape = np.clip(rng.uniform(0.1, 0.45, 5)[None] + np.cumsum(rng.normal(0, 0.01, (WINDOW, 5)), 0), 0, 1)
        pose = unit(rotate_small([0, -1, 0.1], 35) + np.cumsum(rng.normal(0, 0.02, (WINDOW, 3)), 0))
        gyro = np.cumsum(rng.normal(0, 6, (WINDOW, 3)), 0) * rng.uniform(0.2, 1.0)
        acc_dyn = rng.normal(0, 0.05, (WINDOW, 3)) + 0.15 * np.sin(2 * np.pi * rng.uniform(0.5, 2) * t)[:, None] * rng.uniform(0, 1, 3)
    else:
        acc_dyn, gyro, bend, x = motion(kind, amp, speed)
        shape = np.array(fingers, float) + person["shape_bias"] + rng.normal(0, 0.15, 5)
        shape = np.tile(shape, (WINDOW, 1))
        shape = np.clip(shape + bend, 0, 1.1)
        p0 = rotate_small(pose0, 18) @ person["tilt"].T
        p1 = rotate_small(pose1, 18) @ person["tilt"].T
        k = (3 * x ** 2 - 2 * x ** 3)[:, None]      # انتقال ناعم بين الاتجاهين
        pose = unit(p0 * (1 - k) + p1 * k)
        # أول ربع ثانية: الإيد لسه جاية من وضع الراحة
        ramp = np.clip(t / rng.uniform(0.15, 0.3), 0, 1)[:, None]
        shape = 0.25 * (1 - ramp) + shape * ramp

    flex = person["straight"] + shape * (person["bent"] - person["straight"])
    flex += rng.normal(0, 60, flex.shape)
    acc = pose + acc_dyn + rng.normal(0, 0.05, (WINDOW, 3))
    gyro = gyro + person["gyro_bias"] + rng.normal(0, 8, (WINDOW, 3))

    flex = np.clip(flex, 0, 4095).round().astype(int)
    acc = np.clip(acc * ACC_SCALE, -32768, 32767).round().astype(int)
    gyro = np.clip(gyro * GYRO_SCALE, -32768, 32767).round().astype(int)
    return np.hstack([flex, acc, gyro])


# ===== حركات عادية مش إشارات (فئة other) =====
# الهدف إن الموديل يشوف الحاجات اللي الإيد بتعملها طول اليوم، وبعضها شبه الإشارات:
# الإشارة بالصباع، الكوباية، الهزّ وانت بتتكلم. من غيرها أي حركة بتطلع كلمة.
EVERYDAY = ["typing", "phone", "cup", "scratch", "point", "talking", "carry", "reach", "fidget"]


def make_everyday(person, kind=None):
    """take واحد (100 قراءة خام) لحركة عادية"""
    kind = kind or EVERYDAY[rng.integers(len(EVERYDAY))]
    amp = person["amp"] * rng.uniform(0.5, 1.4)
    speed = person["speed"] * rng.uniform(0.6, 1.5)
    gyro = rng.normal(0, 4, (WINDOW, 3)).cumsum(0) * 0.3
    acc_dyn = np.zeros((WINDOW, 3))
    if kind == "typing":        # الإيد على الكيبورد والصوابع بتتحرك بسرعة وخفيف
        shape = rng.uniform(0.25, 0.5, 5)[None] + 0.12 * np.abs(np.sin(2 * np.pi * rng.uniform(4, 8, 5) * t[:, None] + rng.uniform(0, 6, 5)))
        pose = np.tile(rotate_small([0, 0.2, -0.98], 20), (WINDOW, 1))
    elif kind == "phone":       # ماسك موبايل والإبهام بيعمل scroll
        shape = np.tile(rng.uniform(0.45, 0.75, 5), (WINDOW, 1))
        shape[:, 0] = 0.3 + 0.25 * (np.sin(2 * np.pi * rng.uniform(1, 3) * t) > 0)
        pose = np.tile(rotate_small([0, 0.6, 0.8], 25), (WINDOW, 1))
    elif kind == "cup":         # ماسك كوباية وبيشرب أو بيحطها (شبه drink)
        shape = np.tile(rng.uniform(0.35, 0.8, 5), (WINDOW, 1))
        a0, a1 = rotate_small([0, 0.2, -0.98], 25), rotate_small([0.3, 0.6, 0.7], 30)
        k = np.clip((t - rng.uniform(0, 0.8)) / rng.uniform(0.6, 1.4), 0, 1)[:, None]
        pose = unit(a0 * (1 - k) + a1 * k)
        gyro[:, rng.integers(3)] += 60 * amp * np.sin(np.pi * k[:, 0]) ** 2
    elif kind == "scratch":     # بيهرش: الصوابع بتتني وتتفرد بسرعة
        base = rng.uniform(0.2, 0.5, 5)
        shape = base + 0.35 * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(3, 6) * speed * t))[:, None] * (rng.random(5) > 0.3)
        pose = np.tile(rotate_small([0, 0.8, 0.5], 40), (WINDOW, 1))
        acc_dyn[:, rng.integers(3)] = 0.15 * amp * np.sin(2 * np.pi * 4 * t)
    elif kind == "point":       # بيشاور على حاجة وهو بيتحرك (شبه one / you / me)
        shape = np.tile(np.array(INDEX, float) + rng.normal(0, 0.15, 5), (WINDOW, 1))
        p0, p1 = rotate_small(unit(rng.normal(0, 1, 3)), 0), rotate_small(unit(rng.normal(0, 1, 3)), 0)
        k = (0.5 - 0.5 * np.cos(np.pi * np.clip(t / rng.uniform(0.8, 2.0), 0, 1)))[:, None]
        pose = unit(p0 * (1 - k) + p1 * k)
        gyro += rng.normal(0, 40, 3) * amp
    elif kind == "talking":     # بيحرّك إيده وهو بيتكلم: أي شكل، أي حركة
        shape = np.tile(rng.uniform(0.05, 0.9, 5), (WINDOW, 1))
        pose = np.tile(rotate_small(unit(rng.normal(0, 1, 3)), 0), (WINDOW, 1))
        mk = ["wave", "shake", "nod", "circle", "push", "tilt", "down", "salute", "beckon"][rng.integers(9)]
        a, g, _, _ = motion(mk, amp * rng.uniform(0.3, 0.9), speed)
        acc_dyn, gyro = acc_dyn + a, gyro + g
    elif kind == "carry":       # ماسك شنطة وماشي: قبضة والإيد بتتمرجح
        shape = np.tile(np.array(FIST, float) + rng.normal(0, 0.1, 5), (WINDOW, 1))
        pose = np.tile(rotate_small([0, -1, 0], 15), (WINDOW, 1))
        f = rng.uniform(1.6, 2.2)
        acc_dyn[:, 2] = 0.3 * amp * np.sin(2 * np.pi * f * t)
        gyro[:, 0] += 70 * amp * np.cos(2 * np.pi * f * t)
    elif kind == "reach":       # بيمد إيده يمسك حاجة: مفتوحة ← مقفولة
        k = np.clip((t - rng.uniform(0, 1)) / rng.uniform(0.3, 0.8), 0, 1)[:, None]
        shape = rng.uniform(0, 0.2, 5) * (1 - k) + rng.uniform(0.5, 1, 5) * k
        pose = np.tile(rotate_small([0, 0.3, -0.95], 35), (WINDOW, 1))
        acc_dyn[:, 2] = -0.4 * amp * np.sin(np.pi * k[:, 0])
    else:                       # fidget: الصوابع بتتحرك ببطء من غير سبب
        shape = np.clip(rng.uniform(0.1, 0.7, 5)[None] + np.cumsum(rng.normal(0, 0.04, (WINDOW, 5)), 0), 0, 1)
        pose = np.tile(rotate_small(unit(rng.normal(0, 1, 3)), 0), (WINDOW, 1))
    shape = np.clip(shape + person["shape_bias"] * 0.5, -0.1, 1.1)
    pose = unit(pose @ person["tilt"].T)
    flex = person["straight"] + shape * (person["bent"] - person["straight"]) + rng.normal(0, 60, (WINDOW, 5))
    acc = pose + acc_dyn + rng.normal(0, 0.05, (WINDOW, 3))
    gyro = gyro + person["gyro_bias"] + rng.normal(0, 8, (WINDOW, 3))
    flex = np.clip(flex, 0, 4095).round().astype(int)
    acc = np.clip(acc * ACC_SCALE, -32768, 32767).round().astype(int)
    gyro = np.clip(gyro * GYRO_SCALE, -32768, 32767).round().astype(int)
    return np.hstack([flex, acc, gyro])


def make_sample(label, person):
    """take لأي فئة: إشارة أو rest أو other"""
    return make_everyday(person) if label == "other" else make_take(label, person)


def stitch(takes, blend=10):
    """بيلزق takes ورا بعض بانتقال ناعم (زي الإيد في الحقيقة، من غير قفزات)"""
    out = np.asarray(takes[0], float)
    w = np.linspace(0, 1, blend)[:, None]
    for tk in takes[1:]:
        tk = np.asarray(tk, float)
        out[-blend:] = out[-blend:] * (1 - w) + tk[:blend] * w
        out = np.concatenate([out, tk[blend:]])
    return out


def make_person():
    """كل شخص إيده وحساساته ولبسه للجلوف مختلفين شوية"""
    straight = rng.normal(2600, 120, 5)
    straight[0] = rng.normal(2300, 120)              # حساس الإبهام 2.2″ ومقاومته غير
    bent = straight - rng.normal(900, 120, 5)
    a = np.radians(rng.normal(0, 20, 3))              # الجلوف متلبس بميل مختلف
    rx = np.array([[1, 0, 0], [0, np.cos(a[0]), -np.sin(a[0])], [0, np.sin(a[0]), np.cos(a[0])]])
    rz = np.array([[np.cos(a[2]), -np.sin(a[2]), 0], [np.sin(a[2]), np.cos(a[2]), 0], [0, 0, 1]])
    return {"straight": straight, "bent": bent, "tilt": rz @ rx,
            "amp": rng.uniform(0.5, 1.4), "speed": rng.uniform(0.7, 1.3),
            "shape_bias": rng.normal(0, 0.12, 5),                # طريقة كل واحد في ثني صوابعه
            "gyro_bias": rng.normal(0, 2, 3)}


def estimated_bias(person):
    """الـ gyro bias زي ما الجلوف هيقيسه: متوسط ثانيتين والإيد ثابتة، فيه غلطة صغيرة"""
    return (person["gyro_bias"] + rng.normal(0, 8 / np.sqrt(100), 3)) * GYRO_SCALE


def glove_cal(person):
    """نفس ملف المعايرة اللي record.py calib بيحفظه من الجلوف الحقيقي"""
    fist = person["straight"] + np.array([0.6, 1, 1, 1, 1]) * (person["bent"] - person["straight"])
    return {"v": 2, "open": (person["straight"] + rng.normal(0, 8, 5)).round().tolist(),
            "fist": (fist + rng.normal(0, 8, 5)).round().tolist(),
            "gyro_bias": estimated_bias(person).round(1).tolist(),
            "roll": {"neutral": 0.0, "min": -45.0, "max": 45.0}, "source": "sim"}


def write_take(folder, label, person_name, take_id, rows):
    with open(os.path.join(folder, f"{label}.csv"), "a", encoding="utf-8", newline="\n") as f:   # LF على Windows كمان
        for seq, r in enumerate(rows):
            f.write(",".join(map(str, [label, person_name, take_id, seq % 256, *r])) + "\n")


def main(folder="data"):
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    take_id = 1_700_000_000_000
    for name in PEOPLE:
        person = make_person()
        save_calib(name, glove_cal(person), os.path.join(folder, "calib"))
        # المعايرة: 3 takes إيد مفتوحة و3 قبضة
        for label, shape in [(CALIB_OPEN, [0, 0, 0, 0, 0]), (CALIB_FIST, [0.6, 1, 1, 1, 1])]:
            for _ in range(3):
                flex = person["straight"] + np.array(shape) * (person["bent"] - person["straight"])
                flex = (flex + rng.normal(0, 25, (WINDOW, 5))).round().astype(int)
                imu = np.tile([0, int(ACC_SCALE), 0, 0, 0, 0], (WINDOW, 1))
                take_id += 1
                write_take(folder, label, name, take_id, np.hstack([flex, imu]))
        for sign in list(SIGNS) + ["rest"]:
            for _ in range(TAKES_PER_SIGN):
                take_id += 1
                write_take(folder, sign, name, take_id, make_take(sign, person))
        for _ in range(OTHER_TAKES):
            take_id += 1
            write_take(folder, "other", name, take_id, make_everyday(person))
    n = len(PEOPLE) * ((len(SIGNS) + 1) * TAKES_PER_SIGN + OTHER_TAKES)
    print(f"اتعمل فولدر {folder}/ فيه {n} take لـ {len(PEOPLE)} أشخاص و{len(SIGNS) + 2} فئة")


if __name__ == "__main__":
    setup_console()
    show_help(__doc__)
    main()
