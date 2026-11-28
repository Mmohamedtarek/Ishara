"""
run_pipeline.py — الخطوات كلها ورا بعض على الداتا الوهمية (Windows و Linux)
---------------------------------------------------------------------------
v3 pipeline: data -> train -> mine (2 rounds) -> train ensemble -> tune Decider -> evaluate -> kit
أول تدريب قبل الـ mining، فالجولة الأولى بتدوّر بموديل جديد متدرّب على نفس الداتا
(مش بموديلات قديمة فاضلة على الديسك من كلمات تانية).
بعد التدريب بيظبط decider.json للـ CNN وللـ Random Forest على الموديلات الجديدة (eval_live.py --tune)،
عشان الداتا والموديلات وإعدادات القرار يفضلوا دايمًا من نفس التشغيلة.

ده المرجع الوحيد للخطوات: run_pipeline.sh (Linux) و run_pipeline.ps1 (Windows) بيشغّلوه بس.
بيقف عند أول خطوة تفشل، وبيطبع آخر الـ output بتاعها كامل (من غير فلترة) عشان الغلطة متستخباش.

التشغيل:
  python run_pipeline.py
  python run_pipeline.py --kit D:\\Ishara-Mobile-Kit     مكان تاني للـ Kit (الافتراضي: app/Ishara-Mobile-Kit لو المشروع
                                                         جوه الريبو، وإلا ../Ishara-Mobile-Kit جنبه؛ أو KIT=...)
"""
import argparse
import collections
import glob
import os
import re
import subprocess
import sys

from common import setup_console

PY = sys.executable          # نفس الـ Python اللي شغّال دلوقتي (الـ venv)
ACC_LINES = "الدقة|KB|labels"


def step(args, keep=None, tail=None, merge_stderr=False):
    """
    بيشغّل سكريبت. من غير keep/tail الـ output بيظهر زي ما هو.
    keep: regex، بيظهر بس السطور اللي فيها (زي grep -E). tail: آخر كام سطر بس (زي tail -9).
    merge_stderr: الـ stderr يتفلتر مع الـ stdout (زي 2>&1)، وإلا بيظهر زي ما هو.
    لو السكريبت فشل: آخر 60 سطر كاملين، وبعدين الـ pipeline بيقف بنفس الـ exit code.
    """
    cmd = [PY, *args]
    print(f"\n$ python {' '.join(args)}", flush=True)
    if keep is None and tail is None:
        code = subprocess.call(cmd)
        last = []
    else:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT if merge_stderr else None)
        last = collections.deque(maxlen=max(60, tail or 0))
        for raw in p.stdout:
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")   # السكريبتات بتطبع UTF-8 (common.setup_console)
            last.append(line)
            if keep is not None and re.search(keep, line):
                print(line, flush=True)
        code = p.wait()
        if tail and code == 0:
            print("\n".join(list(last)[-tail:]), flush=True)
    if code != 0:
        if last:
            print("\n".join(last), file=sys.stderr)
        print(f"\nالخطوة فشلت (exit code {code}): python {' '.join(args)}\nالـ pipeline وقف هنا.", file=sys.stderr)
        raise SystemExit(code)


def main():
    ap = argparse.ArgumentParser(description="الخطوات كلها ورا بعض على الداتا الوهمية")
    ap.add_argument("--kit", help="فولدر Ishara-Mobile-Kit (الافتراضي: app/Ishara-Mobile-Kit لو جوه الريبو، وإلا ../Ishara-Mobile-Kit)")
    args = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    # الـ Kit: --kit، أو KIT=...، أو app/Ishara-Mobile-Kit لو المشروع جوه الريبو، أو ../Ishara-Mobile-Kit جنبه
    in_repo = os.path.join(here, "..", "..", "app", "Ishara-Mobile-Kit")
    kit = os.path.abspath(args.kit or os.environ.get("KIT")
                          or (in_repo if os.path.isdir(in_repo) else os.path.join(here, "..", "Ishara-Mobile-Kit")))
    os.chdir(here)                                   # الخطوات والموديلات اللي بتتمسح دايمًا في فولدر المشروع، من أي مكان تشغّله

    step(["simulate_data.py"])
    # موديلات قديمة (ممكن تكون بكلمات تانية) متتخلطش بالجديدة
    for f in glob.glob("ishara_cnn*.tflite") + glob.glob("ishara_cnn*.keras") + glob.glob("ishara_rf.joblib"):
        os.remove(f)
    step(["train_rf.py"], tail=9)
    step(["train_cnn.py"], keep=ACC_LINES, merge_stderr=True)
    step(["mine_negatives.py", "--round", "1"])
    step(["train_rf.py"], tail=9)
    step(["train_cnn.py"], keep=ACC_LINES, merge_stderr=True)
    step(["mine_negatives.py", "--round", "2"])
    step(["train_rf.py"], tail=9)
    step(["train_cnn.py"], keep=ACC_LINES, merge_stderr=True)
    step(["train_cnn.py", "--member", "2"], keep="KB", merge_stderr=True)
    step(["train_cnn.py", "--member", "3"], keep="KB", merge_stderr=True)
    # إعدادات الـ Decider لازم تتظبط على الموديلات الجديدة: الأرقام القديمة كانت متظبطة على موديلات تانية
    step(["eval_live.py", "--tune", "--hours", "15", "--no-stress"], keep="أحسن|WER|لوحدها|التأخير|مبدئية", merge_stderr=True)
    step(["eval_live.py", "--tune", "--model", "rf", "--hours", "15", "--no-stress"], keep="أحسن|WER|لوحدها|التأخير|مبدئية",
         merge_stderr=True)
    step(["eval_live.py", "--hours", "30"])
    step(["eval_live.py", "--sessions", "20", "--no-stress", "--hours", "1"])
    step(["build_kit.py", kit])
    print("\nالـ pipeline خلص.")


if __name__ == "__main__":
    setup_console()
    main()
