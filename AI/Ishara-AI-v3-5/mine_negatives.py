"""
mine_negatives.py — بيلاقي الحركات العادية اللي الموديل فاكرها إشارة، ويضيفها للتدريب كـ "other"
-------------------------------------------------------------------------------------------------
ده أقوى سلاح ضد الكلمات اللي بتطلع لوحدها (Hard Negative Mining، نفس اللي بيتعمل في
"Hey Siri" و"OK Google"): نشغّل الموديل على ساعات من الحركة العادية، وكل لحظة قال فيها
كلمة غلط نحفظها، وندرّب تاني وهو شايفها كـ other. ونكرر.

دلوقتي: الحركة العادية جاية من simulate_data (أشخاص مختلفين عن التدريب والاختبار).
مع الجلوف الحقيقي: البس الجلوف وانت بتعمل يومك العادي ساعة أو اتنين وسجّل بـ
  python record.py wear ahmed        (تسجيل طويل من غير إشارات)
وبعدين:  python mine_negatives.py --from-recording ahmed

التشغيل (داتا وهمية):
  python mine_negatives.py                 20 شخص × 30 دقيقة
  python train_rf.py && python train_cnn.py
"""
import argparse
import glob
import os

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
import numpy as np
import pandas as pd

import live
import simulate_data as sim
from common import CHANNELS, NON_WORDS, WINDOW, calib_arrays, load_calib, normalize, save_calib, setup_console

MINE_SEED = 9000          # أشخاص مختلفين عن التدريب (rng 7) والضبط (5000) والاختبار (1000)
MIN_CONF = 0.4            # أي نافذة الموديل شايفها إشارة بثقة أعلى من كده = غلطة نتعلم منها
MAX_PER_PERSON = 250


def hard_windows(predictor, raw, o, f, b):
    """النوافذ (بالقراءات الخام) اللي الموديل قال عليها إشارة وهي مش إشارة"""
    x = normalize(raw, o, f, b)
    ends = np.arange(WINDOW, len(x) + 1, live.STEP)
    W = np.stack([x[e - WINDOW:e] for e in ends])
    P = predictor.batch(W)
    non = [i for i, c in enumerate(predictor.classes) if c in NON_WORDS]
    sign_p = P.copy()
    sign_p[:, non] = 0
    hit = sign_p.max(1) >= MIN_CONF
    picked, last = [], -WINDOW
    for i in np.where(hit)[0]:                    # نوافذ مش متداخلة قوي (كل نص ثانية على الأقل)
        if ends[i] - last >= 25:
            picked.append(raw[ends[i] - WINDOW:ends[i]])
            last = ends[i]
    return picked


def write_other(folder, person_name, takes, take0):
    rows = []
    for k, tk in enumerate(takes):
        for seq, r in enumerate(np.asarray(tk).round().astype(int)):
            rows.append(["other", person_name, take0 + k, seq % 256, *r])
    path = os.path.join(folder, "other.csv")
    pd.DataFrame(rows).to_csv(path, mode="a", header=False, index=False, encoding="utf-8", lineterminator="\n")   # LF زي Linux


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--people", type=int, default=20)
    ap.add_argument("--minutes", type=float, default=30)
    ap.add_argument("--round", type=int, default=1, help="رقم الجولة (عشان أسامي الأشخاص متتكررش)")
    ap.add_argument("--from-recording", help="اسم شخص سجّل حركة عادية بـ record.py wear")
    ap.add_argument("--data", default="data")
    args = ap.parse_args()

    predictor = live.Predictor("cnn", members=["ishara_cnn"])   # الموديل الأساسي اللي لسه متدرّب على نفس الداتا
    take0 = 1_900_000_000_000 + args.round * 10_000_000
    total = 0
    if args.from_recording:
        cal = load_calib(args.from_recording)
        files = glob.glob(os.path.join(args.data, "wear.csv"))
        if not cal or not files:
            raise SystemExit("محتاج معايرة الشخص (record.py calib) وملف data/wear.csv")
        df = pd.read_csv(files[0], header=None)
        df = df[df[1] == args.from_recording]
        raw = df.iloc[:, 4:4 + len(CHANNELS)].to_numpy(float)
        takes = hard_windows(predictor, raw, *calib_arrays(cal))[:MAX_PER_PERSON * 4]
        write_other(args.data, args.from_recording, takes, take0)
        print(f"اتضاف {len(takes)} take لـ other من تسجيل {args.from_recording}")
        return

    n_takes = int(args.minutes * 60 * sim.SAMPLE_RATE / (WINDOW - 10)) + 1
    for p in range(args.people):
        sim.rng = np.random.default_rng(MINE_SEED + args.round * 100 + p)
        person = sim.make_person()
        name = f"m{args.round}_{p}"
        save_calib(name, sim.glove_cal(person), os.path.join(args.data, "calib"))
        cal = load_calib(name, os.path.join(args.data, "calib"))
        labels = np.where(sim.rng.random(n_takes) < 0.45, "rest", "other")
        raw = sim.stitch([sim.make_sample(l, person) for l in labels])
        takes = hard_windows(predictor, raw, *calib_arrays(cal))
        if len(takes) > MAX_PER_PERSON:
            takes = [takes[i] for i in sim.rng.choice(len(takes), MAX_PER_PERSON, replace=False)]
        write_other(args.data, name, takes, take0 + p * 100_000)
        total += len(takes)
        print(f"  {name}: {len(takes)} لحظة الموديل غلط فيها")
    print(f"اتضاف {total} take صعب لفئة other. درّب تاني: python train_rf.py && python train_cnn.py")


if __name__ == "__main__":
    setup_console()
    main()
