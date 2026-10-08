"""
live.py — التوقع الحي: الجلوف بيتحرك ← الكلمة تظهر وتتقال بصوت
-----------------------------------------------------------------
بيقرا القراءات باستمرار، وكل 0.2 ثانية ياخد آخر ثانيتين ويدخّلهم للموديل (أو متوسط 3 موديلات).
الترجمة شغالة على طول، من غير أي زرار. الـ Decider (تحت) بيعرف لوحده الشخص بيتكلم ولا بيعمل حاجة عادية:
  - إشارة واضحة جدًا ← الكلمة بتطلع على طول
  - إشارة واضحة بس ← بتظهر "مبدئية" (…؟)، وبتتأكد لو جت بعدها كلمة تانية أو فضلت واضحة، وتتشال لو مجاش حاجة
  - جوه محادثة ← الانتقال من كلمة لكلمة أسرع
الأرقام دي بتيجي من decider.json اللي eval_live.py --tune بيطلّعه.

التشغيل:
  python live.py --sim            تجربة من غير جلوف: جمل وهمية من شخص جديد
  python live.py                  مع الجلوف الحقيقي (بياخد المعايرة من الجلوف نفسه)
  python live.py --person ahmed   بيستخدم معايرة ahmed المحفوظة لو الجلوف مش متعاير
  python live.py --port COM5      لو عايز تحدد البورت بنفسك
  python live.py --model rf       استخدم Random Forest بدل الـ CNN
  python live.py --mute           من غير صوت
"""
import argparse
import collections
import os
import platform
import queue
import subprocess
import threading
import time

import numpy as np

import json

from common import NON_WORDS, SAMPLE_RATE, WINDOW, features, normalize

STEP = 10               # توقع كل 10 قراءات = 5 مرات في الثانية
DECIDER_FILE = "decider.json"
# القيم الافتراضية لو مفيش decider.json. eval_live.py --tune بيدوّر على الأحسن ويحفظه.
DEFAULTS = {
    "cnn": {"confidence": 0.9, "smooth": 4, "hold": 3, "max_null": 0.05, "confirm_rf": False, "per_class": {}},
    "rf": {"confidence": 0.45, "smooth": 4, "hold": 3, "max_null": 0.25, "confirm_rf": False, "per_class": {}},
}
SMOOTH = DEFAULTS["cnn"]["smooth"]       # للتوافق مع السكريبتات القديمة


def decider_config(kind, path=DECIDER_FILE):
    cfg = dict(DEFAULTS[kind])
    try:
        cfg.update(json.load(open(path, encoding="utf-8")).get(kind, {}))
    except (OSError, ValueError):
        pass
    return cfg

# الكلمة اللي هتتقال بصوت لكل label
WORDS = {"one": "one", "two": "two", "three": "three", "four": "four", "five": "five",
         "me": "me", "you": "you", "hello": "hello", "thanks": "thank you",
         "please": "please", "yes": "yes", "no": "no", "sorry": "sorry", "water": "water",
         "bye": "bye", "come": "come", "drink": "drink", "call": "call",
         "iloveyou": "I love you", "hungry": "hungry"}


# ===================== الموديل =====================
ENSEMBLE = ["ishara_cnn", "ishara_cnn_2", "ishara_cnn_3"]


class Predictor:
    """
    بياخد آخر ثانيتين (100 × 11) ويرجع احتمال كل إشارة (بترتيب self.classes).
    الـ CNN: لو فيه أكتر من موديل (ensemble)، بياخد متوسط احتمالاتهم. الموديلات اللي هتستخدم
    مكتوبة في decider.json ("models")، ولو مش مكتوبة بياخد كل اللي موجود من ENSEMBLE.
    """

    def __init__(self, kind, members=None):
        self.kind = kind
        if kind == "rf":
            import joblib
            self.clf = joblib.load("ishara_rf.joblib")
            self.classes = list(self.clf.classes_)
            return
        os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
        import tensorflow as tf
        self.classes = open("labels.txt", encoding="utf-8").read().split()
        if members is None:
            members = decider_config("cnn").get("models") or [m for m in ENSEMBLE if os.path.exists(m + ".tflite")]
        self.members = list(members)
        self.interps = []
        for m in self.members:          # نفس ملفات .tflite اللي هتشتغل على الموبايل
            it = tf.lite.Interpreter(model_path=m + ".tflite")
            it.allocate_tensors()
            self.interps.append((it, it.get_input_details()[0]["index"], it.get_output_details()[0]["index"]))

    def batch(self, windows):
        """احتمالات لنوافذ كتير مرة واحدة (للتقييم: أسرع بكتير من نافذة نافذة)"""
        windows = np.asarray(windows, np.float32)
        if self.kind == "rf":
            self.clf.n_jobs = -1
            out = self.clf.predict_proba(features(windows))
            self.clf.n_jobs = 1
            return out
        if not hasattr(self, "models"):
            import tensorflow as tf
            self.models = [tf.keras.models.load_model(m + ".keras") for m in self.members]
        return np.mean([mdl.predict(windows, batch_size=4096, verbose=0) for mdl in self.models], axis=0)

    def __call__(self, window):
        x = window[None].astype(np.float32)
        if self.kind == "rf":
            return np.asarray(self.clf.predict_proba(features(x))[0], dtype=float)
        outs = []
        for it, i, o in self.interps:
            it.set_tensor(i, x)
            it.invoke()
            outs.append(it.get_tensor(o)[0])
        return np.mean(outs, axis=0).astype(float)


# ===================== القرار: إمتى نقول الكلمة =====================
class Decider:
    """
    بيقرر إمتى نقول الكلمة، زي مترجم حقيقي. الترجمة شغالة على طول، من غير أي زرار.

    حالتين:
      idle    الشخص مش بيتكلم. أي كلمة لازم يبان إنها كلام حقيقي مش حركة عادية:
                - strict     لو الإشارة واضحة جدًا، الكلمة بتطلع على طول
                - tentative  لو واضحة بس مش جدًا، بتظهر "مبدئية" (باهتة) وبتستنى confirm_s ثانية:
                               • جت بعدها كلمة تانية ← ده كلام حقيقي: الاتنين يتأكدوا
                               • نفس الإشارة فضلت لحد ما عدّت شروط strict ← تتأكد
                               • مجاش حاجة ← غالبًا حركة عادية: الكلمة تتشال (cancel)
      active  جوه محادثة (بعد أي كلمة متأكدة): الشروط أسهل والانتقال من كلمة لكلمة أسرع.
              بعد active_s ثانية من غير كلام بيرجع idle لوحده.

    كل مستوى (strict / tentative / active) ليه:
      confidence / per_class   أقل ثقة لمتوسط آخر smooth توقعات
      hold       كام توقع ورا بعض لازم نفس الإشارة تفضل الأولى وتعدّي الشروط (كل توقع = 0.2 ثانية)
      max_null   أقصى احتمال لـ "مش كلام" (rest + other)

    step() بترجع أحداث: ("word", w) كلمة متأكدة، ("tentative", w) كلمة مبدئية،
    ("confirm", w) المبدئية اتأكدت، ("cancel", w) المبدئية اتشالت.
    """

    LEVEL_KEYS = ("confidence", "hold", "max_null", "per_class")

    def __init__(self, classes, cfg, confirm=None):
        if not isinstance(cfg, dict):                      # التوافق مع Decider(classes, 0.8)
            cfg = dict(DEFAULTS["cnn"], confidence=float(cfg), hold=1, max_null=1.0)
        self.classes = list(classes)
        self.cfg = cfg
        flat = {k: cfg[k] for k in self.LEVEL_KEYS if k in cfg}
        self.levels = {"strict": dict(flat, **cfg.get("idle", {})), "active": dict(flat, **cfg.get("active", {}))}
        if "tentative" in cfg:
            self.levels["tentative"] = dict(flat, **cfg["tentative"])
        for lv in self.levels.values():
            lv.setdefault("per_class", {})
        rate = SAMPLE_RATE / STEP
        self.active_steps = int(round(cfg.get("active_s", 0) * rate))
        self.confirm_steps = int(round(cfg.get("confirm_s", 3) * rate))
        self.null_idx = [i for i, c in enumerate(self.classes) if c in NON_WORDS]
        self.recent = collections.deque(maxlen=int(cfg["smooth"]))
        self.confirm = confirm if cfg.get("confirm_rf") else None
        self.last_said = None
        self.rest_seen = 0
        self.runs = {k: [None, 0] for k in self.levels}    # لكل مستوى: (الإشارة، كام مرة ورا بعض)
        self.step_no, self.active_until = 0, -1
        self.pending, self.pending_until, self.blocked = None, -1, set()
        self.rest_after = int(cfg.get("confirm_on_rest", 0))   # 0 = مقفول. غير كده: كام توقع راحة بعد المبدئية يأكدها
        self.pending_rest = 0

    @property
    def state(self):
        return "active" if self.step_no <= self.active_until else "idle"

    def _passes(self, level, label, conf, null):
        lv = self.levels[level]
        ok = (len(self.recent) == self.recent.maxlen and conf >= lv["per_class"].get(label, lv["confidence"])
              and null <= lv["max_null"])
        run = self.runs[level]
        if not ok:
            run[0], run[1] = None, 0
            return False
        run[1] = run[1] + 1 if run[0] == label else 1
        run[0] = label
        return run[1] >= lv["hold"]

    def _say(self, label):
        self.last_said = label
        self.active_until = self.step_no + self.active_steps

    def step(self, probs, window=None):
        self.step_no += 1
        events = []
        if self.pending is not None and self.step_no > self.pending_until:
            events.append(("cancel", self.pending))
            self.blocked.add(self.pending)               # متطلعهاش مبدئية تاني لحد ما الإيد ترتاح
            self.pending = None
        self.recent.append(probs)
        avg = np.mean(self.recent, axis=0)
        i = int(np.argmax(avg))
        label, conf = self.classes[i], float(avg[i])
        if label in NON_WORDS:
            if self.pending is not None and self.rest_after:
                # إشارة لوحدها وبعدها الإيد رجعت ترتاح (مش كملت حركة عادية) ← كلمة حقيقية
                self.pending_rest = self.pending_rest + 1 if label == "rest" else 0
                if self.pending_rest >= self.rest_after:
                    events.append(("confirm", self.pending))
                    self._say(self.pending)
                    self.pending, self.pending_rest = None, 0
            self.rest_seen += 1
            if self.rest_seen >= 2:          # الإيد رجعت لراحة أو حركة عادية: نسمح بنفس الكلمة تاني
                self.last_said = None
                self.blocked.clear()
            for run in self.runs.values():
                run[0], run[1] = None, 0
            return events
        self.rest_seen = 0
        null = float(avg[self.null_idx].sum()) if self.null_idx else 0.0
        passed = {lv: self._passes(lv, label, conf, null) for lv in self.levels}
        if self.confirm is not None and any(passed.values()) and not self.confirm(window, label):
            return events
        if self.state == "active":
            if passed["active"] and label != self.last_said:
                events.append(("word", label))
                self._say(label)
        elif self.pending is not None:
            if label == self.pending:
                if passed["strict"]:                    # نفس الإشارة فضلت واضحة: تتأكد
                    events.append(("confirm", label))
                    self._say(label)
                    self.pending = None
            elif passed["active"] and label != self.last_said:
                events.append(("confirm", self.pending))  # كلمة تانية جت: الاتنين كلام حقيقي
                events.append(("word", label))
                self._say(label)
                self.pending = None
        elif label != self.last_said:
            if passed["strict"]:
                events.append(("word", label))
                self._say(label)
            elif passed.get("tentative") and label not in self.blocked:
                events.append(("tentative", label))
                self.pending, self.pending_until, self.pending_rest = label, self.step_no + self.confirm_steps, 0
        return events

    def update(self, probs, window=None):
        """للتوافق مع الكود القديم: (أول كلمة متأكدة في الخطوة دي أو None، الثقة)"""
        ev = self.step(probs, window)
        words = [w for kind, w in ev if kind in ("word", "confirm")]
        avg = np.mean(self.recent, axis=0)
        return (words[0] if words else None), float(avg.max())


def rf_confirm(min_prob=0.2):
    """الـ Random Forest كموافقة تانية: لازم يشوف نفس الإشارة الأولى"""
    import joblib
    clf = joblib.load("ishara_rf.joblib")
    clf.n_jobs = 1
    classes = list(clf.classes_)

    def check(window, label):
        p = clf.predict_proba(features(np.asarray(window)[None]))[0]
        j = int(np.argmax(p))
        return classes[j] == label and p[j] >= min_prob
    return check


# ===================== الصوت =====================
class Speaker:
    """بيتكلم في thread لوحده عشان قراءة الجلوف متقفش"""

    def __init__(self, enabled):
        self.q = queue.Queue()
        self.linux_cmd = None
        if enabled and platform.system() != "Windows":
            import shutil
            self.linux_cmd = next((c for c in ("espeak-ng", "espeak", "spd-say") if shutil.which(c)), None)
            if self.linux_cmd is None:
                print("تحذير: مفيش برنامج صوت. على Ubuntu: sudo apt install espeak-ng")
                enabled = False
        self.enabled = enabled
        if enabled:
            threading.Thread(target=self._run, daemon=True).start()

    def say(self, text):
        if self.enabled:
            self.q.put(text)

    def _run(self):
        while True:
            text = self.q.get()
            try:
                if platform.system() == "Windows":   # صوت Windows المدمج، مش محتاج تنزيل
                    cmd = ("Add-Type -AssemblyName System.Speech; "
                           f"(New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{text}')")
                    subprocess.run(["powershell", "-NoProfile", "-Command", cmd],
                                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                else:
                    subprocess.run([self.linux_cmd, text], stderr=subprocess.DEVNULL)
            except Exception:
                pass


# ===================== مصدر القراءات =====================
DEMO_SENTENCES = [["me", "hungry"], ["me", "water"], ["water", "please"], ["you", "come"],
                  ["call", "me"], ["hello", "thanks"], ["sorry", "bye"], ["iloveyou"]]


def sim_source(fast):
    """بيعمل شخص جديد الموديل مشافوش، ويعمل الجمل التجريبية من ملف الـ Vocabulary"""
    import simulate_data as sim
    sim.rng = np.random.default_rng(int(time.time()))   # شخص مختلف كل مرة
    person = sim.make_person()
    open_vals = person["straight"]
    fist_vals = person["straight"] + np.array([0.6, 1, 1, 1, 1]) * (person["bent"] - person["straight"])
    gyro_bias = sim.estimated_bias(person)            # زي اللي الجلوف بيقيسه في خطوة "افتح إيدك"

    def stream():
        for sentence in DEMO_SENTENCES:
            print(f"\n── الجملة: {' + '.join(sentence)}")
            for sign in ["rest"] + sentence + ["rest"]:
                if sign != "rest":
                    print(f"   (الإيد بتعمل: {sign})")
                for row in sim.make_take(sign, person):
                    yield row
                    if not fast:
                        time.sleep(1 / SAMPLE_RATE)
    return stream(), open_vals, fist_vals, gyro_bias


def glove_source(port, person=None):
    import glove
    from common import load_calib
    ser = glove.open_glove(port)
    if not glove.ensure_stream(ser):
        raise SystemExit("الجلوف متوصل بس مش باعت داتا. افصل الكابل ووصّله تاني.")

    def read_rows():
        while True:
            row = glove.is_row(glove.read_line(ser))
            if row:
                yield np.array(row[1:], dtype=float)  # من غير seq

    # 1) المعايرة اللي جوه الجلوف (نفس اللي اتعملت من التطبيق أو بحرف c)
    cal = glove.request_cal(ser)
    if cal:
        print("المعايرة جاية من الجلوف.")
    # 2) لو مش متعاير: المعايرة المحفوظة للشخص ده
    elif person and load_calib(person):
        cal = load_calib(person)
        print(f"الجلوف مش متعاير، هستخدم معايرة '{person}' المحفوظة.")
    if cal:
        ser.reset_input_buffer()
        return read_rows(), np.asarray(cal["open"], float), np.asarray(cal["fist"], float), \
            np.asarray(cal.get("gyro_bias", [0, 0, 0]), float)

    # 3) آخر حل: معايرة سريعة هنا (الإيد ثابتة وهي مفتوحة، فبنقيس الـ gyro bias وقتها)
    print("الجلوف مش متعاير. هنعمل معايرة سريعة:")

    def capture(seconds):
        ser.reset_input_buffer()
        end, got = time.time() + seconds, []
        while time.time() < end:
            row = glove.is_row(glove.read_line(ser))
            if row:
                got.append(row[1:])
        return np.asarray(got, float)

    input("\nافرد إيدك وصوابعك على الآخر، وخلّيها ثابتة، ودوس Enter...")
    o = capture(2)
    input("اقفل إيدك (قبضة) ودوس Enter...")
    fz = capture(2)
    print("المعايرة خلصت. ابدأ اعمل إشارات!\n")
    ser.reset_input_buffer()
    return read_rows(), np.median(o[:, :5], axis=0), np.median(fz[:, :5], axis=0), np.median(o[:, 8:11], axis=0)


# ===================== البرنامج =====================
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", action="store_true", help="تجربة من غير جلوف")
    ap.add_argument("--fast", action="store_true", help="مع --sim: من غير انتظار")
    ap.add_argument("--port")
    ap.add_argument("--model", choices=["cnn", "rf"], default="cnn")
    ap.add_argument("--mute", action="store_true")
    ap.add_argument("--person", help="اسم الشخص، لو عايز تستخدم معايرته المحفوظة")
    args = ap.parse_args()

    predictor = Predictor(args.model)
    speaker = Speaker(not args.mute)
    cfg = decider_config(args.model)
    decider = Decider(predictor.classes, cfg, rf_confirm() if cfg.get("confirm_rf") and args.model == "cnn" else None)
    rows, open_vals, fist_vals, gyro_bias = sim_source(args.fast) if args.sim else glove_source(args.port, args.person)
    print(f"الموديل: {args.model.upper()} | Ctrl+C للخروج")

    buf = collections.deque(maxlen=WINDOW)
    said = []
    try:
        for n, raw in enumerate(rows, 1):
            buf.append(normalize(np.asarray(raw, float)[None], open_vals, fist_vals, gyro_bias)[0])
            if len(buf) < WINDOW or n % STEP:
                continue
            window = np.array(buf)
            for kind, word in decider.step(predictor(window), window):
                if kind == "tentative":
                    print(f"   …  {WORDS[word]}؟   (مبدئية)")
                elif kind == "cancel":
                    print(f"   ✗  {WORDS[word]}   (اتشالت: مكانتش إشارة)")
                else:                                  # word أو confirm: كلمة متأكدة، تتقال بصوت
                    said.append(word)
                    print(f"   🗣  {WORDS[word]}" + ("   (اتأكدت)" if kind == "confirm" else ""))
                    speaker.say(WORDS[word])
    except KeyboardInterrupt:
        pass

    if args.sim:
        expected = [w for s in DEMO_SENTENCES for w in s]
        print(f"\nالمطلوب: {' '.join(expected)}")
        print(f"اتقال:   {' '.join(said)}")
        time.sleep(1.5)                      # نسيب آخر كلمة تتقال


if __name__ == "__main__":
    main()
