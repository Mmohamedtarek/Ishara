"""
train_cnn.py — الموديل التاني: 1D-CNN (ده الموديل النهائي المقترح)
--------------------------------------------------------------------
على عكس Random Forest، الـ CNN بياخد الـ take كامل (100 قراءة × 11 قناة)
ويتعلم لوحده شكل الحركة مع الوقت: هزة، دايرة، ميل، ...

ليه هو النهائي:
  - بيتحوّل لـ TensorFlow Lite  → يشتغل في تطبيق Flutter على الموبايل
  - وبـ int8 يبقى حجمه صغير     → يشتغل على ESP32-S3 نفسه (TFLite Micro)

محتاج TensorFlow، وده مش بيشتغل على Python 3.14. شوف README.md.

التشغيل:
  python train_cnn.py          اختبار سريع على شخص واحد + الموديل النهائي
  python train_cnn.py --full   Leave-One-Person-Out كامل (أبطأ، ده الرقم للمناقشة)
"""
import os
import sys

import numpy as np

from common import (CHANNELS, LABELS, WINDOW, context_windows, load_takes, setup_console, show_help, sign_people,
                    transition_windows)

EPOCHS = 40
BATCH = 32
AUG_COPIES = 3            # كام نسخة متعدلة من كل take نضيفها للتدريب
# Ensemble: 3 موديلات بتتدرّب بشكل مختلف شوية (seed و kernel)، والتطبيق بياخد متوسطهم.
# كل موديل بيغلط في حتت مختلفة، فالمتوسط بيقلل الكلمات الغلط من غير ما يضيّع كلمات صح.
#   python train_cnn.py               → الموديل 1: ishara_cnn.*
#   python train_cnn.py --member 2    → ishara_cnn_2.*  (و --member 3)
MEMBER = int(sys.argv[sys.argv.index("--member") + 1]) if "--member" in sys.argv else 1
KERNEL = {1: 5, 2: 7, 3: 3}[MEMBER]
NAME = "ishara_cnn" if MEMBER == 1 else f"ishara_cnn_{MEMBER}"
rng = np.random.default_rng(MEMBER - 1)


# ===== Data Augmentation =====
# الداتا قليلة، فبنعمل نسخ متعدلة من كل take. كل تعديل بيقلّد مشكلة هتحصل في الحقيقة:
ROT_DEG = 25              # الجلوف متلبس بزاوية مختلفة: نلف الـ MPU لحد 25°
WARP = (0.65, 1.5)        # حد بيعمل الإشارة أسرع أو أبطأ
DROP_P = 0.15             # حساس صباع اتكسر أو السلك فصل: القراءة بتقف على رقم واحد


def random_rotation(deg):
    axis = rng.normal(0, 1, 3)
    axis /= np.linalg.norm(axis)
    a = np.radians(rng.normal(0, deg / 2))
    k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
    return np.eye(3) + np.sin(a) * k + (1 - np.cos(a)) * (k @ k)      # Rodrigues


def time_warp(x, f):
    """f > 1: الإشارة اتعملت أسرع. بناخد عينات من الـ take حوالين نصه بسرعة مختلفة"""
    pos = np.clip(WINDOW / 2 + (np.arange(WINDOW) - WINDOW / 2) * f, 0, WINDOW - 1)
    out = np.stack([np.interp(pos, np.arange(WINDOW), x[:, c]) for c in range(x.shape[1])], 1)
    out[:, 8:11] *= f                                 # أسرع = بيلف أسرع
    return out


def augment(x):
    x = x.copy()
    if rng.random() < 0.7:
        x = time_warp(x, rng.uniform(*WARP))
    r = random_rotation(ROT_DEG)
    x[:, 5:8] = x[:, 5:8] @ r.T                       # التسارع والدوران بيتلفوا مع بعض
    x[:, 8:11] = x[:, 8:11] @ r.T
    x[:, :5] += rng.normal(0, 0.05, 5)                # الصوابع مثنية أكتر أو أقل شوية
    x[:, :5] = x[:, :5] * rng.uniform(0.9, 1.1, 5)    # الحساس اتغيّر شوية من وقت المعايرة
    x[:, 5:] *= rng.uniform(0.8, 1.2)                 # الحركة أقوى أو أضعف
    if rng.random() < DROP_P:
        f = rng.integers(5)
        x[:, f] = rng.uniform(-0.1, 1.1)
    x += rng.normal(0, 0.02, x.shape)                 # noise
    return x.astype(np.float32)


def with_augmentation(X, y, persons):
    # نسخ مزاحة جوه rest قبلها وبعدها، زي النافذة اللي بتتحرك في live.py
    Xc, yc = context_windows(X, y, persons, copies=AUG_COPIES)
    # ونوافذ الانتقال من إشارة لإشارة، زي اللي بتحصل في نص الجملة
    Xt, yt = transition_windows(X, y, persons)
    # ونسخة متعدلة من كل take أصلي كمان
    Xc, yc = np.concatenate([Xc, Xt, X]), np.concatenate([yc, yt, y])
    Xc = np.stack([augment(x) for x in Xc]) if len(Xc) else Xc
    Xa, ya = np.concatenate([X, Xc]), np.concatenate([y, yc])
    return Xa, np.array([LABELS.index(label) for label in ya])


def build_model(n_classes):
    from tensorflow import keras
    from tensorflow.keras import layers

    inp = keras.Input(shape=(WINDOW, len(CHANNELS)))
    x = inp
    # 3 طبقات Conv1D: كل واحدة بتدوّر على patterns قصيرة في الوقت
    # (زي "الدوران زاد وبعدين قل") وكل ما نطلع لفوق بتشوف فترة أطول
    for filters in (32, 64, 64):
        x = layers.Conv1D(filters, KERNEL, padding="same")(x)
        x = layers.BatchNormalization()(x)
        x = layers.ReLU()(x)
        x = layers.MaxPooling1D(2)(x)
    x = layers.GlobalAveragePooling1D()(x)
    x = layers.Dropout(0.3)(x)
    x = layers.Dense(64, activation="relu")(x)
    out = layers.Dense(n_classes, activation="softmax")(x)

    model = keras.Model(inp, out)
    model.compile(optimizer=keras.optimizers.Adam(1e-3),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    return model


def train(X, y, persons):
    Xa, ya = with_augmentation(X, y, persons)
    model = build_model(len(LABELS))
    model.fit(Xa, ya, epochs=EPOCHS, batch_size=BATCH, shuffle=True, verbose=0)
    return model


def export_tflite(model, X):
    import tensorflow as tf

    def converter():
        # بعض إصدارات TensorFlow بتفشل مع from_keras_model، فنجرب طريق تاني
        try:
            c = tf.lite.TFLiteConverter.from_keras_model(model)
            c.convert()
            return tf.lite.TFLiteConverter.from_keras_model(model)
        except Exception:
            model.export(f"{NAME}_savedmodel")
            return tf.lite.TFLiteConverter.from_saved_model(f"{NAME}_savedmodel")

    # 1) float32 للموبايل (Flutter: tflite_flutter)
    data = converter().convert()
    with open(f"{NAME}.tflite", "wb") as f:
        f.write(data)
    print(f"{NAME + '.tflite':22s} {len(data) / 1024:6.1f} KB  ← للموبايل")

    # 2) int8 للـ ESP32-S3 (TFLite Micro): أصغر 4 مرات تقريباً
    # نوافذ المعايرة من كل الفئات: X مترتبة بالفئة، فأول 300 كانوا bye و call بس
    # والـ int8 كان بيتظبط على مدى أرقام إشارتين بس
    calib_idx = np.random.default_rng(0).choice(len(X), min(500, len(X)), replace=False)
    try:
        conv = converter()
        conv.optimizations = [tf.lite.Optimize.DEFAULT]
        conv.representative_dataset = lambda: ([X[i:i + 1]] for i in calib_idx)
        conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        conv.inference_input_type = tf.int8
        conv.inference_output_type = tf.int8
        data = conv.convert()
        with open(f"{NAME}_int8.tflite", "wb") as f:
            f.write(data)
        print(f"{NAME + '_int8.tflite':22s} {len(data) / 1024:6.1f} KB  ← للـ ESP32-S3")
    except Exception as e:                            # مش هيوقف الباقي لو فشل
        print("تحويل int8 مانجحش:", e)

    with open("labels.txt", "w", encoding="utf-8", newline="\n") as f:     # LF: نفس الملف بالظبط على Windows و Linux
        f.write("\n".join(LABELS))
    print("labels.txt           ترتيب الفئات اللي الموديل بيطلعها")


def main():
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    import tensorflow as tf
    from sklearn.metrics import accuracy_score

    tf.random.set_seed(MEMBER - 1)
    X, y, persons = load_takes("data")
    y_idx = np.array([LABELS.index(label) for label in y])
    people = sign_people(y, persons)                  # أشخاص الـ mining (other بس) مش بيتحسبوا في الدقة
    print(f"{len(y)} take | {len(people)} أشخاص بيعملوا إشارات | شكل كل take {X.shape[1:]}\n")

    test_people = people if "--full" in sys.argv else ([] if MEMBER > 1 else people[-1:])
    correct = total = 0
    print("الاختبار على شخص الموديل مشافوش (بياخد وقت، استنى):")
    for p in test_people:
        test = persons == p
        model = train(X[~test], y[~test], persons[~test])
        pred = model.predict(X[test], verbose=0).argmax(1)
        acc = accuracy_score(y_idx[test], pred)
        correct += int(acc * test.sum())
        total += int(test.sum())
        print(f"  {p}: {acc * 100:5.1f}%")
    if total:
        print(f"\nالدقة على أشخاص جداد (1D-CNN): {correct / total * 100:.1f}%\n")

    print("تدريب الموديل النهائي على كل الناس...")
    model = train(X, y, persons)
    model.save(f"{NAME}.keras")
    print(f"{NAME + '.keras':22s} الموديل الأصلي")
    export_tflite(model, X)


if __name__ == "__main__":
    setup_console()
    show_help(__doc__)
    main()
