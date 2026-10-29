"""Experiment: train one CNN member with overrides, save as <prefix>_<member>.keras (no LOPO, no tflite).
usage: python _work/exp_train.py PREFIX MEMBER [key=value ...]
keys: drop_p, epochs, cw (class-weight power 0..1), arch (base|gmp), lr_sched (0|1), aug_copies, ls (label smoothing)
"""
import os
import sys
import time

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
sys.path.insert(0, os.getcwd())
prefix, member = sys.argv[1], int(sys.argv[2])
opts = dict(a.split("=", 1) for a in sys.argv[3:])
sys.argv = ["train_cnn.py", "--member", str(member)]
import numpy as np
import train_cnn as tc
from common import LABELS, load_takes

tc.DROP_P = float(opts.get("drop_p", tc.DROP_P))
tc.EPOCHS = int(opts.get("epochs", tc.EPOCHS))
tc.AUG_COPIES = int(opts.get("aug_copies", tc.AUG_COPIES))
CW = float(opts.get("cw", 0))
ARCH = opts.get("arch", "base")
SCHED = int(opts.get("lr_sched", 0))
LS = float(opts.get("ls", 0))
if "shift" in opts:
    import functools
    tc.context_windows = functools.partial(tc.context_windows, max_shift=int(opts["shift"]))


def build(n_classes):
    from tensorflow import keras
    from tensorflow.keras import layers
    inp = keras.Input(shape=(tc.WINDOW, len(tc.CHANNELS)))
    x = inp
    for filters in (32, 64, 64):
        x = layers.Conv1D(filters, tc.KERNEL, padding="same")(x)
        x = layers.BatchNormalization()(x)
        x = layers.ReLU()(x)
        x = layers.MaxPooling1D(2)(x)
    if ARCH == "gmp":
        x = layers.Concatenate()([layers.GlobalAveragePooling1D()(x), layers.GlobalMaxPooling1D()(x)])
    else:
        x = layers.GlobalAveragePooling1D()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(64, activation="relu")(x)
    out = layers.Dense(n_classes, activation="softmax")(x)
    return keras.Model(inp, out)


def main():
    import tensorflow as tf
    from tensorflow import keras
    tf.random.set_seed(member - 1)
    t0 = time.time()
    X, y, persons = load_takes(opts.get("data", "data"))
    Xa, ya = tc.with_augmentation(X, y, persons)
    model = build(len(LABELS))
    steps = int(np.ceil(len(Xa) / tc.BATCH)) * tc.EPOCHS
    lr = keras.optimizers.schedules.CosineDecay(1e-3, steps, alpha=0.05) if SCHED else 1e-3
    if LS:
        loss = keras.losses.CategoricalCrossentropy(label_smoothing=LS)
        yt = keras.utils.to_categorical(ya, len(LABELS))
    else:
        loss, yt = "sparse_categorical_crossentropy", ya
    model.compile(optimizer=keras.optimizers.Adam(lr), loss=loss, metrics=["accuracy"])
    cw = None
    if CW:
        counts = np.bincount(ya, minlength=len(LABELS)).astype(float)
        w = (counts.mean() / counts) ** CW
        cw = {i: float(v) for i, v in enumerate(w)}
    model.fit(Xa, yt, epochs=tc.EPOCHS, batch_size=tc.BATCH, shuffle=True, verbose=0, class_weight=cw)
    model.save(f"_work/{prefix}_{member}.keras")
    print(f"saved _work/{prefix}_{member}.keras  ({len(Xa)} windows, {time.time() - t0:.0f}s)")


main()
