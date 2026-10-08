"""
record.py — تسجيل الداتا الحقيقية من الجلوف
--------------------------------------------
- بيسجّل اسم الشخص، عشان نقدر نختبر على شخص الموديل مشافوش
- بياخد المعايرة من الجلوف نفسه (نفس خطوات التطبيق: افتح، اقفل، لفّ الرسغ)
- عدّ تنازلي 3-2-1 قبل كل take، عشان أول جزء ميبقاش "إيد لسه بتتحرك لمكانها"
- بيرفض أي اسم إشارة مش في القايمة، عشان غلطة كتابة متبوظش الداتا

الاستخدام:
  python record.py calib ahmed          مرة واحدة لكل شخص: عاير الجلوف الأول (حرف c من التطبيق أو الـ Serial Monitor)
                                        وبعدين ده بيحفظ المعايرة في data/calib/ahmed.json
  python record.py water ahmed           كل إشارة 20 مرة
  python record.py water ahmed COM5      لو عايز تحدد البورت بنفسك (على Ubuntu: /dev/ttyACM0)
  python record.py other ahmed          حركات عادية مش إشارات (كتابة، موبايل، كوباية...): 2 ثانية كل Enter
  python record.py wear ahmed 60        تسجيل طويل (60 دقيقة) وانت لابس الجلوف في يومك العادي من غير إشارات.
                                        بيتحفظ في data/wear.csv، وبعدين: python mine_negatives.py --from-recording ahmed

كل Enter = عدّ تنازلي وبعده take مدته ثانيتين. اكتب q وEnter عشان تخرج.
(لسه ينفع تسجّل calib_open و calib_fist بالطريقة القديمة لو الجلوف مش بيبعت #CAL.)
"""
import csv
import os
import sys
import time

import glove
from common import CALIB_DIR, CALIB_FIST, CALIB_OPEN, LABELS, load_calib, save_calib

SECONDS = 2.0
COUNTDOWN = 3          # 3، 2، 1، ابدأ
TICK = 0.6             # ثواني بين كل رقم


def record_calib(ser, person):
    cal = glove.request_cal(ser)
    if cal is None:
        raise SystemExit("الجلوف مش متعاير لسه.\n"
                         "عايره الأول: افتح الـ Serial Monitor (أو التطبيق) واكتب c، وامشي في الخطوات التلاتة،\n"
                         f"وبعدين شغّل تاني: python record.py calib {person}")
    span = [f - o for o, f in zip(cal["open"], cal["fist"])]
    weak = [n for n, d in zip(["الإبهام", "السبابة", "الوسطى", "البنصر", "الخنصر"], span) if abs(d) < 300]
    cal = save_calib(person, cal)
    print(f"اتحفظت المعايرة في {os.path.join(CALIB_DIR, person + '.json')} (format v{cal['v']})")
    print("  open :", [round(v) for v in cal["open"]])
    print("  fist :", [round(v) for v in cal["fist"]])
    print("  gyro bias:", [round(v, 1) for v in cal["gyro_bias"]])
    if weak:
        print(f"  تحذير: {', '.join(weak)} بيتحرك أقل من 300، اتأكد من الحساس وعيد المعايرة")


def countdown():
    for n in range(COUNTDOWN, 0, -1):
        print(f"  {n}...", end=" ", flush=True)
        time.sleep(TICK)
    print("ابدأ!")


def record_wear(ser, person, minutes):
    """تسجيل متصل طويل: الجلوف عليك وانت بتعمل حاجتك العادية، من غير ولا إشارة"""
    print(f"هسجّل {minutes:.0f} دقيقة. اعمل يومك العادي من غير إشارات. Ctrl+C يوقف بدري والتسجيل بيتحفظ.")
    take = int(time.time() * 1000)
    rows, end, last = 0, time.time() + minutes * 60, time.time()
    with open(os.path.join("data", "wear.csv"), "a", newline="") as f:
        out = csv.writer(f)
        try:
            ser.reset_input_buffer()
            ser.readline()
            while time.time() < end:
                row = glove.is_row(glove.read_line(ser))
                if row:
                    out.writerow(["wear", person, take] + row)
                    rows += 1
                if time.time() - last > 60:
                    f.flush()
                    last = time.time()
                    print(f"  {rows / 50 / 60:.1f} دقيقة اتسجلت")
        except KeyboardInterrupt:
            pass
    print(f"خلص: {rows / 50 / 60:.1f} دقيقة في data/wear.csv. دلوقتي: python mine_negatives.py --from-recording {person}")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    label, person = sys.argv[1], sys.argv[2].lower()
    allowed = LABELS + [CALIB_OPEN, CALIB_FIST, "calib", "wear"]
    if label not in allowed:
        raise SystemExit(f"'{label}' مش في القايمة. الأسماء المسموحة:\n{', '.join(allowed)}")
    minutes = None
    if label == "wear":
        minutes = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].replace(".", "").isdigit() else 60.0
        port = sys.argv[4] if len(sys.argv) > 4 else None
    else:
        port = sys.argv[3] if len(sys.argv) > 3 else None
    ser = glove.open_glove(port)
    if not glove.ensure_stream(ser):
        raise SystemExit("الجلوف متوصل بس مش باعت داتا. اتأكد إن الفيرموير شغال، وجرّب تفصل الكابل وتوصّله تاني.")

    if label == "calib":
        record_calib(ser, person)
        return
    if label not in (CALIB_OPEN, CALIB_FIST) and load_calib(person) is None:
        print(f"تنبيه: '{person}' ملوش معايرة لسه. سجّلها الأول: python record.py calib {person}\n")

    os.makedirs("data", exist_ok=True)
    if label == "wear":
        record_wear(ser, person, minutes)
        return
    count = 0
    with open(os.path.join("data", f"{label}.csv"), "a", newline="") as f:
        out = csv.writer(f)
        while input(f"[{label} | {person} | {count} take] Enter = سجّل، q = خروج: ").strip() != "q":
            countdown()
            ser.reset_input_buffer()
            ser.readline()                            # أول سطر بعد المسح ممكن يكون نصه مقطوع
            take = int(time.time() * 1000)
            rows = 0
            end = time.time() + SECONDS
            while time.time() < end:
                row = glove.is_row(glove.read_line(ser))
                if row:
                    out.writerow([label, person, take] + row)
                    rows += 1
            f.flush()
            count += 1
            warn = "" if rows >= 90 else "  ← قراءات قليلة! اتأكد إن الجلوف متوصل"
            print(f"  اتسجل ({rows} قراءة){warn}")


if __name__ == "__main__":
    main()
