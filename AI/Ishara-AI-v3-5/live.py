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

from common import NON_WORDS, SAMPLE_RATE, WINDOW, calib_arrays, features, normalize, setup_console

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
        with open(path, encoding="utf-8") as f:
            cfg.update(json.load(f).get(kind, {}))
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
        with open("labels.txt", encoding="utf-8") as f:
            self.classes = f.read().split()
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
                               • جت بعدها كلمة تانية (بتعدّي مستوى pair_level) ← ده كلام حقيقي: الاتنين يتأكدوا
                               • نفس الإشارة فضلت لحد ما عدّت شروط strict ← تتأكد
                               • كانت واضحة (rest_conf) لفترة (rest_run)، واحتمال "مش كلام" وصل لأقل من rest_null،
                                 والإيد رجعت ترتاح confirm_on_rest توقعات ورا بعض ← كلمة اتقالت لوحدها: تتأكد
                                 (rest_per_class: نفس الشروط دي لكل كلمة لوحدها، conf / run / null)
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
        # الكلمة اللي بتتقال لوحدها (إيد مرتاحة ← إشارة ← إيد مرتاحة) مفيش بعدها كلمة تأكدها، ونادرًا ما بتعدّي strict،
        # فكانت بتظهر مبدئية وتتشال (one 53%، drink 19% بس كانوا بيتقالوا لوحدهم). confirm_on_rest بيأكدها لما الإيد
        # ترجع ترتاح، بشرط تكون كانت واضحة جدًا (rest_conf) لفترة (rest_run توقعات ورا بعض بتعدّي مستوى tentative).
        # الحركة العادية اللي بتطلع مبدئية ثقتها أوطى وأقصر، والإيد غالبًا بتكمل حركة مش بترتاح.
        # rest_null: وكمان لازم في لحظة كان احتمال "مش كلام" فيها قليل جدًا. ده أحسن فرق بين الإشارة الحقيقية لوحدها
        # (أقل احتمال "مش كلام" حوالي 0.02) والحركة العادية اللي بتطلع مبدئية (حوالي 0.16)
        self.rest_conf = float(cfg.get("rest_conf", 0.0))
        self.rest_run = int(cfg.get("rest_run", 0))
        self.rest_null = float(cfg.get("rest_null", 1.0))
        # rest_per_class (v3.5): نفس الشروط التلاتة لكل كلمة لوحدها {"drink": {"conf":..,"run":..,"null":..}}، واللي مش
        # مكتوب ياخد الرقم العام. drink و hungry أقل احتمال "مش كلام" فيهم 0.04-0.17 (حركتهم شبه حركات عادية)، فـ 0.03
        # العام كان بيضيّعهم لوحدهم، و one ثقتها أوطى لإنها بتتلخبط مع you و two وقت ما الإيد طالعة من الراحة
        self.rest_per_class = cfg.get("rest_per_class", {})
        self.pending_peak = self.pending_cur = self.pending_best = 0
        self.pending_null = 1.0
        # الكلمة اللي بتيجي بعد كلمة مبدئية وبتأكدها لازم تعدّي أنهي مستوى. "active" (الافتراضي) سهل،
        # فحركتين عاديتين ورا بعض شبه إشارتين كانوا بيأكدوا بعض ويطلّعوا كلمتين غلط. "tentative" أصعب شوية.
        self.pair_level = cfg.get("pair_level", "active")
        if self.pair_level not in self.levels:
            self.pair_level = "active"

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

    def _track_pending(self, label, conf, null):
        """أعلى ثقة للكلمة المبدئية، وأطول مدة فضلت فيها بتعدّي مستوى tentative، وكام توقع راحة ورا بعض بعدها"""
        lv = self.levels.get("tentative", self.levels["strict"])
        if label == self.pending:
            self.pending_peak = max(self.pending_peak, conf)
            self.pending_null = min(self.pending_null, null)
            ok = conf >= lv["per_class"].get(label, lv["confidence"]) and null <= lv["max_null"]
            self.pending_cur = self.pending_cur + 1 if ok else 0
            self.pending_best = max(self.pending_best, self.pending_cur)
        else:
            self.pending_cur = 0
        self.pending_rest = self.pending_rest + 1 if label == "rest" else 0

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
        null = float(avg[self.null_idx].sum()) if self.null_idx else 0.0
        if self.pending is not None:
            self._track_pending(label, conf, null)
        if label in NON_WORDS:
            rc = self.rest_per_class.get(self.pending, {})
            if (self.pending is not None and self.rest_after and self.pending_rest >= self.rest_after
                    and self.pending_peak >= rc.get("conf", self.rest_conf)
                    and self.pending_best >= rc.get("run", self.rest_run)
                    and self.pending_null <= rc.get("null", self.rest_null)):
                # إشارة لوحدها واضحة، وبعدها الإيد رجعت ترتاح (مش كملت حركة عادية) ← كلمة حقيقية
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
            elif passed[self.pair_level] and label != self.last_said:
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
                self.pending_peak, self.pending_cur, self.pending_best, self.pending_null = conf, 1, 1, null
        return events

    def update(self, probs, window=None):
        """للتوافق مع الكود القديم: (أول كلمة متأكدة في الخطوة دي أو None، الثقة)"""
        ev = self.step(probs, window)
        words = [w for kind, w in ev if kind in ("word", "confirm")]
        avg = np.mean(self.recent, axis=0)
        return (words[0] if words else None), float(avg.max())


MAX_DROPPED = 10        # أكتر من كده seq قديم ورا بعض = الجلوف اتعمله restart والعداد رجع من الأول


class StreamRecognizer:
    """
    المرجع اللي التطبيق بيقارن بيه، وهو نفسه اللي live.py بيستخدمه مع الجلوف:
    قراءة قراءة ومعاها seq زي ما بتيجي من USB أو BLE (AI-SPEC قسم 4):
      - فجوة 1-5 قراءات: نكرر آخر قراءة سليمة مكان الناقص، والمكرر بيتعد قراءة عادية
      - فجوة أكتر من 5: نفضّي النافذة، والعداد يرجع 0، والـ Decider يبدأ من الأول
        (ولو فيه كلمة مبدئية مستنية بنطلّع cancel ليها الأول)
      - seq مكرر أو راجع لورا: القراءة بتتشال ومش بتتعد
      - أكتر من MAX_DROPPED قراءة ورا بعض اتشالوا كده: الجلوف اتعمله restart، فبنبدأ من الأول زي الفجوة الكبيرة
    الـ seq بيلف من 255 لـ 0 (الفيرموير والـ CSV: 8 bit) أو من 65535 لـ 0 (BLE: 16 bit).
    بنبدأ على 8 bit، وأول ما يجي seq أكبر من 255 بنعرف إنه 16 bit.
    قبل كده كان 16 bit بس، فمع الجلوف (8 bit) كل القراءات بعد أول 256 (حوالي 5 ثواني) كانت بتتشال ومفيش كلمة بتطلع.
    feed() بترجع الأحداث [(event, word)] اللي طلعت بسبب القراءة دي
    """

    def __init__(self, predictor, cfg, cal, predict=None, confirm=None):
        self.predictor, self.cfg, self.confirm = predictor, cfg, confirm
        # predict(window) ← الاحتمالات. الافتراضي الـ keras (batch)، و live.py بيدّيله ملفات tflite زي الموبايل
        self.predict = predict or (lambda w: predictor.batch(w[None])[0])
        self.o, self.f, self.b = calib_arrays(cal)
        self.last_seq, self.last, self.mod, self.dropped = None, None, 256, 0
        self._reset()

    def _reset(self):
        self.window, self.count = collections.deque(maxlen=WINDOW), 0
        self.decider = Decider(self.predictor.classes, self.cfg, self.confirm)

    def _push(self, raw, events):
        self.window.append(normalize(np.asarray(raw, float)[None], self.o, self.f, self.b)[0])
        self.count += 1
        if len(self.window) == WINDOW and self.count % STEP == 0:
            w = np.asarray(self.window)
            events += self.decider.step(self.predict(w), w)

    def feed(self, seq, raw):
        seq, events = int(seq), []
        if seq > 255:
            self.mod = 65536
        if self.last_seq is not None:
            gap = (seq - self.last_seq - 1) % self.mod        # كام قراءة ضاعت بين آخر قراءة ودي
            if gap >= self.mod // 2:                          # مكرر (= آخر seq) أو راجع لورا
                self.dropped += 1
                if self.dropped <= MAX_DROPPED:
                    return events
                gap = MAX_DROPPED + 1                         # restart: نبدأ من الأول
            self.dropped = 0
            if 1 <= gap <= 5:
                for _ in range(gap):
                    self._push(self.last, events)
            elif gap > 5:
                if self.decider.pending is not None:
                    events.append(("cancel", self.decider.pending))
                self._reset()
        self._push(raw, events)
        self.last, self.last_seq = raw, seq
        return events


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
# صوت Windows المدمج (System.Speech، مش محتاج تنزيل): PowerShell واحد شغال طول الوقت وبيقول كل سطر بيوصله على stdin.
# كده مفيش PowerShell جديد بيقوم مع كل كلمة، والكلام مش بيدخل جوه الأمر نفسه، فأي ' أو " في الكلام مش بتبوّظه.
WIN_TTS = ("Add-Type -AssemblyName System.Speech; "
           "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
           "$in = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), (New-Object System.Text.UTF8Encoding $false)); "
           "while ($null -ne ($line = $in.ReadLine())) { if ($line.Trim()) { $s.Speak($line) } }")


class Speaker:
    """بيتكلم في thread لوحده عشان قراءة الجلوف متقفش"""

    def __init__(self, enabled):
        self.q = queue.Queue()
        self.linux_cmd = None
        self.win = None
        if enabled and platform.system() != "Windows":
            import shutil
            self.linux_cmd = next((c for c in ("espeak-ng", "espeak", "spd-say") if shutil.which(c)), None)
            if self.linux_cmd is None:
                print("تحذير: مفيش برنامج صوت. على Ubuntu: sudo apt install espeak-ng")
                enabled = False
        elif enabled:
            try:
                self._windows_tts()                   # نشغّله من دلوقتي عشان أول كلمة متتأخرش
            except OSError:
                print("تحذير: مش لاقي PowerShell للصوت، هكمّل من غير صوت")
                enabled = False
        self.enabled = enabled
        if enabled:
            threading.Thread(target=self._run, daemon=True).start()

    def say(self, text):
        if self.enabled:
            self.q.put(text)

    def _windows_tts(self):
        """الـ PowerShell اللي بيتكلم: بيتعمل مرة واحدة، ولو قفل لأي سبب بيتعمل تاني"""
        if self.win is None or self.win.poll() is not None:
            self.win = subprocess.Popen(["powershell", "-NoProfile", "-NonInteractive", "-Command", WIN_TTS],
                                        stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return self.win

    def _run(self):
        while True:
            text = self.q.get()
            try:
                if platform.system() == "Windows":
                    line = (" ".join(str(text).split()) + "\n").encode("utf-8")   # سطر واحد = كلمة واحدة
                    for _ in range(2):                # لو الـ PowerShell كان قفل: نشغّله تاني ونبعت تاني مرة واحدة
                        try:
                            tts = self._windows_tts()
                            tts.stdin.write(line)
                            tts.stdin.flush()
                            break
                        except OSError:
                            self.win = None
                else:
                    subprocess.run([self.linux_cmd, text], stderr=subprocess.DEVNULL)
            except Exception:
                pass


# ===================== مصدر القراءات =====================
DEMO_SENTENCES = [["me", "hungry"], ["me", "water"], ["water", "please"], ["you", "come"],
                  ["call", "me"], ["hello", "thanks"], ["sorry", "bye"], ["iloveyou"]]


def sim_source(fast):
    """
    بيعمل شخص جديد الموديل مشافوش، ويعمل الجمل التجريبية من ملف الـ Vocabulary.
    بيرجّع (قراءات (seq، الـ 11 رقم)، المعايرة)
    """
    import simulate_data as sim
    sim.rng = np.random.default_rng(int(time.time()))   # شخص مختلف كل مرة
    person = sim.make_person()
    cal = {"open": person["straight"],
           "fist": person["straight"] + np.array([0.6, 1, 1, 1, 1]) * (person["bent"] - person["straight"]),
           "gyro_bias": sim.estimated_bias(person)}   # زي اللي الجلوف بيقيسه في خطوة "افتح إيدك"

    def stream():
        n = 0
        for sentence in DEMO_SENTENCES:
            print(f"\n── الجملة: {' + '.join(sentence)}")
            for sign in ["rest"] + sentence + ["rest"]:
                if sign != "rest":
                    print(f"   (الإيد بتعمل: {sign})")
                for row in sim.make_take(sign, person):
                    yield n % 256, row
                    n += 1
                    if not fast:
                        time.sleep(1 / SAMPLE_RATE)
    return stream(), cal


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
                yield row[0], np.array(row[1:], dtype=float)  # (seq، الـ 11 رقم): الـ seq عشان القراءات الناقصة

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
        return read_rows(), cal

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
    return read_rows(), {"open": np.median(o[:, :5], axis=0), "fist": np.median(fz[:, :5], axis=0),
                         "gyro_bias": np.median(o[:, 8:11], axis=0)}


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
    confirm = rf_confirm() if cfg.get("confirm_rf") and args.model == "cnn" else None
    rows, cal = sim_source(args.fast) if args.sim else glove_source(args.port, args.person)
    # نفس اللي التطبيق بيعمله: نافذة ثانيتين كل 10 قراءات، والقراءات الناقصة أو المكررة بتتعالج بالـ seq
    rec = StreamRecognizer(predictor, cfg, cal, predict=predictor, confirm=confirm)
    print(f"الموديل: {args.model.upper()} | Ctrl+C للخروج")

    said = []
    try:
        for seq, raw in rows:
            for kind, word in rec.feed(seq, raw):
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
    setup_console()
    try:
        main()
    except (KeyboardInterrupt, EOFError):   # Ctrl+C وهو لسه بيحمّل الموديل أو في المعايرة السريعة
        raise SystemExit("\nاتوقف.")
