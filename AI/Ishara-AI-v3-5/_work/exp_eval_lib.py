import os
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import eval_live as ev
import live
from common import SIGN_LABELS


class KPred(live.Predictor):
    """Predictor from .keras files (no tflite needed)"""

    def __init__(self, paths):
        import tensorflow as tf
        self.kind = "cnn"
        with open("labels.txt", encoding="utf-8") as f:
            self.classes = f.read().split()
        self.members = paths
        self.models = [tf.keras.models.load_model(p) for p in paths]


def test_report(name, pred, cfg, hours=30, takes=True):
    import check_words as cw
    t0 = time.time()
    tb = ev.Bench(pred, ev.TEST_SEED, people=12, hours=hours)
    ev.show(tb.score(cfg), f"[{name}] TEST (12 new people, {hours} h everyday):")
    res = cw.new_people(pred, cfg, 20)
    tot = sum(len(v) for v in res.values())
    ok = sum(v.count("ok") for v in res.values())
    print(f"[{name}] check_words, 20 new people: {ok}/{tot} = {ok / tot * 100:.1f}%")
    print("  " + "  ".join(f"{w}:{res[w].count('ok')}" for w in SIGN_LABELS))
    if takes:
        ev.show_takes(ev.take_report(pred), pred.classes)
    print(f"({time.time() - t0:.0f}s)")
