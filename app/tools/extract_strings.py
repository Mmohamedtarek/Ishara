#!/usr/bin/env python3
"""Turn the prototype's UI strings into the app's ARB files (en = template, ar).

Source: app/tools/out/prototype/prototype.stripped.html (run strip_prototype.py first):
  * I18N.en / I18N.ar           -> one ARB key per string
  * I18N_FEM                    -> Arabic feminine forms, used when the selected avatar is female:
                                   {gender, select, female{...} other{...}}
  * DEMO.<lang>.q               -> the spoken text of the Talk quick phrases (qSay*)
Transforms (same behaviour as the prototype's t()):
  * "Nour" / "نور"              -> {name}  (the selected avatar's name)
  * {n} {p}                     -> int placeholders; {w} -> String placeholder
  * micHint "<b>X</b> Y"        -> micHintStrong = X, micHintRest = Y
Strings that are demo-only, or that user decisions (app/DECISIONS.md) remove or make untrue, are
left out; EXCLUDED lists each one with its reason. Changed or new texts are NOT invented here:
they are drafted with their screens and approved by the user (Q-D2).

Usage: python3 app/tools/extract_strings.py   (rewrites app/ishara_app/lib/l10n/app_{en,ar}.arb)
"""
import json
import pathlib
import re
import sys

from proto_common import REPO, prototype_src
OUT = REPO / "app" / "ishara_app" / "lib" / "l10n"

EXCLUDED = {
    # demo frame / screen jump list (prompt: leave out demo-only parts)
    "exitFull": "desktop frame", "full": "desktop frame", "jWelcome": "jump list", "jLogin": "jump list",
    "jMission": "jump list",
    # Q-B2 email only
    "lblId": "Q-B2 (phone or email field)", "phId": "Q-B2", "errId": "Q-B2", "errIdFormat": "Q-B2 (Egyptian phone)",
    "remember": "Q-B2", "google": "Q-B2", "phoneLogin": "Q-B2", "toastGoogle": "Q-B2", "toastPhone": "Q-B2",
    "loginLead": "untrue: the glove isn't synced (draft)",
    "terms": "untrue: there is no conversation backup (Q-B4, draft)",
    # Q-K2..K5 glove copy
    "pairLead": "Q-K2 (wrist button)", "tip1": "Q-K2 (light colour)", "tip2": "Q-K2 (wrist button)",
    "c2": "Q-K3 (renamed, draft)", "pose3s": "Q-K4 (4 s -> 3 s, draft)", "accuracy": "Q-K5",
    # fake device values
    "sumGlove": "fake battery", "sGlove": "fake device name", "sGloveS": "fake battery / version",
    "sAvatarS": "fixed values, needs real ones (draft)", "sVoiceS": "Q-D1 (male/female voice)",
    # Q-T1 unsure words
    "sUnsure": "Q-T1", "sUnsureS": "Q-T1", "unsure": "Q-T1", "keep": "Q-T1", "fixed": "Q-T1",
    # Q-T4 SOS
    "sSos": "Q-T4", "sSosS": "Q-T4", "toastSOS": "Q-T4 (mentions SMS)",
    # fake history / conversation
    "today": "fake place", "toastOpen": "placeholder toast",
    "h1": "fake history", "h1s": "fake history", "h2": "fake history", "h2s": "fake history", "h3": "fake history",
    "h3s": "fake history", "h4": "fake history", "h4s": "fake history", "st1": "fake phrase", "st1s": "fake phrase",
    "st2": "fake phrase", "st2s": "fake phrase", "st3": "fake phrase", "st3s": "fake phrase",
    # Learn
    "tipIndex": "Q-L3", "tipThumb": "Q-L3", "tipPinky": "Q-L3", "okMatch": "Q-L3 (has a tip)",
    "yourTurnSub": "Q-L3 (claims per-finger checking, draft)",
    "shareMedal": "Q-L6", "toastShare": "Q-L6",
    "mGreet": "Q-L1", "mGreetS": "Q-L1", "mDoctor": "Q-L1", "mDoctorS": "Q-L1", "mFamily": "Q-L1",
    "mFamilyS": "Q-L1", "mShop": "Q-L1", "mShopS": "Q-L1", "mSos": "Q-L1", "mSosS": "Q-L1", "mWork": "Q-L1",
    "mWorkS": "Q-L1", "mDailyS": "Q-L2 ('3 minutes' isn't a rule, draft)",
    # Q-A2
    "avLook": "Q-A2", "avSkin": "Q-A2", "avHair": "Q-A2", "avOutfit": "Q-A2", "avGlasses": "Q-A2",
    # placeholders
    "toastSoon": "placeholder toast", "sAboutS": "fixed version (draft)",
}

# Texts that are not in the prototype, approved by the user word for word
# (key: (en, ar, where the approval is)). Drafts never go here.
APPROVED_NEW = {
    "comingSoon": ("Coming soon", "قريبًا", "user prompt, Sign language section"),
    "arslComingSoon": (
        "Egyptian Arabic Sign Language is coming in a future update. For now, Ishara uses American Sign Language (ASL).",
        "لغة الإشارة المصرية هتكون متاحة في تحديث قريب. حاليًا إشارة بيستخدم لغة الإشارة الأمريكية (ASL).",
        "user prompt, Sign language section; AR name fixed to إشارة in step 4 approvals",
    ),
    "ok": ("OK", "تمام", "user prompt, Sign language section"),
}

# New or changed texts written for step 6's screens (EN + Egyptian
# colloquial Arabic), key: (en, ar, why, placeholders). Approved by the user
# in the step 6 review (2026-10-10), with their Arabic corrections. New
# drafts for later steps go in a separate dict until approved.
DRAFTS = {
    # --- shared
    "back": ("Back", "رجوع", "step 6: the back button's label (prototype aria-label, not in I18N)", None),
    "stepOfLabel": ("Step {n} of 3: {name}", "خطوة {n} من 3: {name}", "step 6: the 3-step header for screen readers", {"n": "int", "name": "String"}),
    "tryAgain": ("Try again", "جرّب تاني", "step 6: retry after a failure", None),
    # --- login (Q-B2, S6-1)
    "loginLeadEmail": ("Sign in to keep your saved phrases, settings and Learn progress on any phone.", "سجّل دخولك عشان جملك المحفوظة وإعداداتك وتقدّمك في التعلّم يفضلوا معاك على أي موبايل.", "replaces loginLead (the glove isn't synced; Q-B4: saved phrases and settings sync)", None),
    "termsLocal": ("By continuing you agree to the Terms of Use and Privacy Policy. Your conversations stay on this phone.", "بالمتابعة إنت موافق على شروط الاستخدام وسياسة الخصوصية. محادثاتك بتفضل على الموبايل ده.", "replaces terms (there is no conversation backup, Q-B4)", None),
    "lblEmail": ("Email", "الإيميل", "Q-B2: replaces 'Phone number or email'", None),
    "phEmail": ("you@example.com", "you@example.com", "Q-B2: replaces '010… or you@example.com'", None),
    "errEmail": ("Enter your email", "اكتب الإيميل بتاعك", "Q-B2: replaces errId", None),
    "errEmailFormat": ("Enter a valid email address", "اكتب إيميل صحيح", "Q-B2: replaces errIdFormat (no phone numbers)", None),
    "authErrInvalid": ("Wrong email or password.", "الإيميل أو كلمة السر غلط.", "step 6: sign-in failed (one message for both, no account leak)", None),
    "authErrEmailInUse": ("This email already has an account. Sign in instead.", "الإيميل ده عليه حساب بالفعل. سجّل دخول بدل كده.", "step 6: create account, email taken", None),
    "authErrNetwork": ("No internet connection. Check it and try again.", "مفيش إنترنت. اتأكد من الاتصال وجرّب تاني.", "step 6: offline", None),
    "authErrTooMany": ("Too many tries. Wait a few minutes and try again.", "محاولات كتير. استنى كام دقيقة وجرّب تاني.", "step 6: rate limited", None),
    "authErrUnknown": ("Something went wrong. Try again.", "حصلت مشكلة. جرّب تاني.", "step 6: any other auth error", None),
    "forgotNeedsEmail": ("Enter your email above first, then tap Forgot password.", "اكتب الإيميل فوق الأول، وبعدين دوس «نسيت كلمة السر؟».", "step 6: Forgot password with no email", None),
    # --- pair (Q-K2, Q-K3, S6-3)
    "pairLeadTrue": ("Switch your glove on, keep it close to your phone and keep Bluetooth on. It shows up as “Ishara-” and 4 letters or numbers.", "شغّل الجوانتي وقرّبه من الموبايل وخلّي البلوتوث شغال. هيظهر باسم «\u2066Ishara-\u2069» وبعده 4 حروف أو أرقام.", "Q-K2: replaces pairLead (no button, no light colours; name from BLE-CONTRACT §1)", None),
    "c2Sensors": ("Checking the sensors", "فحص الحساسات", "Q-K3: replaces c2", None),
    "tipOn": ("Make sure the glove is switched on and charged.", "اتأكد إن الجوانتي شغال ومشحون.", "S6-3: replaces tip1 (no light colour)", None),
    "tipNear": ("Keep it close to your phone.", "قرّبه من الموبايل.", "S6-3: replaces tip2 (no wrist button)", None),
    "tipOtherPhone": ("If it's connected to another phone, disconnect it there first. A connected glove doesn't show up.", "لو متوصّل بموبايل تاني، افصله من هناك الأول. الجوانتي المتوصّل مش بيظهر.", "S6-3: BLE-CONTRACT §1 (it advertises only when not connected)", None),
    "sigGood": ("Good signal", "إشارة كويسة", "step 6: signal from RSSI (thresholds are a draft too: ≥ −60 strong, ≥ −70 good, ≥ −80 fair, else weak)", None),
    "sigFair": ("Fair signal", "إشارة متوسطة", "step 6: signal from RSSI (draft thresholds)", None),
    "sigWeak": ("Weak signal", "إشارة ضعيفة", "step 6: signal from RSSI (draft thresholds)", None),
    "rssiDbm": ("{v} dBm", "\u2066{v} dBm\u2069", "Q-K2: the real RSSI (kept left-to-right in Arabic)", {"v": "int"}),
    "battPercent": ("Battery {p}%", "البطارية {p}%", "Q-K2: real battery after connecting (#BAT OK)", {"p": "int"}),
    "battLow": ("Battery low", "البطارية ضعيفة", "Q-K2: #BAT LOW", None),
    "battUsb": ("On USB power", "شغال على USB", "Q-K2: #BAT NO_BATTERY (USB)", None),
    "firmware": ("Firmware {v}", "السوفتوير {v}", "Q-K2: fw from INFO", {"v": "String"}),
    "notFound": ("No glove found", "ملقيناش الجوانتي", "step 6: the scan ended without a glove", None),
    "notFoundSub": ("Check the tips below, then scan again.", "شوف النصايح اللي تحت، وبعدين ابحث تاني.", "step 6: not found", None),
    "permTitle": ("Bluetooth permission needed", "محتاجين إذن البلوتوث", "step 6: permission refused", None),
    "permBody": ("Allow Ishara to use Bluetooth to find and connect to your glove.", "اسمح للتطبيق يستخدم البلوتوث عشان يلاقي الجوانتي ويتوصّل بيه.", "step 6: permission refused once", None),
    "permBodySettings": ("Turn on the Bluetooth permission for Ishara in your phone's settings.", "شغّل إذن البلوتوث لتطبيق إشارة من إعدادات الموبايل.", "step 6: permission refused for good", None),
    "permLocationBody": ("On this Android version, finding Bluetooth devices needs the location permission. Ishara doesn't use your location.", "في إصدار الأندرويد ده، البحث عن أجهزة البلوتوث محتاج إذن الموقع. التطبيق مش بيستخدم موقعك.", "step 6: Android 11 and older", None),
    "allow": ("Allow", "اسمح", "step 6: ask for the permission again", None),
    "openSettings": ("Open settings", "افتح الإعدادات", "step 6: permission refused for good", None),
    "btOffTitle": ("Bluetooth is off", "البلوتوث مقفول", "step 6", None),
    "btOffBody": ("Turn on Bluetooth, then tap Scan again.", "شغّل البلوتوث، وبعدين دوس «ابحث تاني».", "step 6", None),
    "locOffTitle": ("Location is off", "الموقع مقفول", "step 6: Android 11 and older", None),
    "locOffBody": ("On this Android version, Bluetooth scanning needs Location turned on. Ishara doesn't use your location.", "في إصدار الأندرويد ده، البحث بالبلوتوث محتاج الموقع يبقى شغال. التطبيق مش بيستخدم موقعك.", "step 6: Android 11 and older", None),
    "btUnsupported": ("This phone doesn't support Bluetooth Low Energy, so it can't connect to the glove.", "الموبايل ده مش بيدعم بلوتوث Low Energy، فمش هيقدر يتوصّل بالجوانتي.", "step 6", None),
    "btNotReady": ("Bluetooth isn't ready yet. Try again in a moment.", "البلوتوث لسه مش جاهز. جرّب تاني بعد شوية.", "step 6", None),
    "connFailTitle": ("Couldn't connect to the glove", "مقدرناش نتوصّل بالجوانتي", "step 6: check 1 failed", None),
    "connFailBody": ("Keep it close to your phone and try again.", "قرّبه من الموبايل وجرّب تاني.", "step 6", None),
    "protoTitle": ("This glove needs a different version of the app", "الجوانتي ده محتاج إصدار تاني من التطبيق", "BLE-CONTRACT §2: proto ≠ 1", None),
    "protoBody": ("Update the Ishara app and the glove's firmware, then try again.", "حدّث تطبيق إشارة وسوفتوير الجوانتي، وبعدين جرّب تاني.", "BLE-CONTRACT §2", None),
    "mpuTitle": ("The glove's motion sensor isn't responding", "حساس الحركة في الجوانتي مش بيرد", "BLE-CONTRACT §6: #MPU FAIL (Q-K3 check 2)", None),
    "mpuBody": ("Switch the glove off and on, then try again. If it keeps happening, the glove needs a check.", "اقفل الجوانتي وافتحه، وبعدين جرّب تاني. لو المشكلة فضلت، الجوانتي محتاج فحص.", "step 6", None),
    "linkLostTitle": ("The connection stopped", "الاتصال وقف", "step 6: timeout, rejected command or lost link", None),
    "linkLostBody": ("Keep the glove close to your phone and try again.", "قرّب الجوانتي من الموبايل وجرّب تاني.", "step 6", None),
    # --- calibrate (Q-K4, Q-K6, Q-K7, BLE-CONTRACT §7)
    "pose3s3": ("Turn your palm to the left, then to the right, slowly, for 3 seconds. This calibrates the motion sensor.", "لفّ كف إيدك ناحية الشمال وبعدين اليمين بالراحة، لمدة 3 ثواني. دي معايرة حساس الحركة.", "Q-K4: replaces pose3s (3 s)", None),
    "handStill": ("Hand still", "الإيد ثابتة", "Q-K7: hold-still indicator", None),
    "handMoving": ("Hand moving", "الإيد بتتحرك", "Q-K7: hold-still indicator", None),
    "fingersLater": ("Finger bars appear after Open and Fist.", "شرايط الصوابع بتظهر بعد «مفتوحة» و«قبضة».", "Q-K7: bars hidden until OPEN and FIST", None),
    "failMovedTitle": ("Your hand moved", "إيدك اتحركت", "BLE-CONTRACT §7: MOVED", None),
    "failMovedBody": ("Keep your hand still for the whole 2 seconds, then try again.", "خلّي إيدك ثابتة طول الثانيتين، وبعدين جرّب تاني.", "MOVED", None),
    "failRangeTitle": ("Turn your wrist further", "لفّ رسغك أكتر", "BLE-CONTRACT §7: RANGE", None),
    "failRangeBody": ("Turn your palm further to the left and to the right (at least 30° in all), then try again.", "لفّ كف إيدك أكتر ناحية الشمال واليمين (30 درجة على الأقل في المجموع)، وبعدين جرّب تاني.", "RANGE (firmware CAL_MIN_ROLL_RANGE_DEG 30)", None),
    "failCancelledTitle": ("The capture stopped", "التسجيل وقف", "BLE-CONTRACT §7: CANCELLED", None),
    "failCancelledBody": ("Tap Start capture to try again.", "دوس «ابدأ التسجيل» عشان تجرّب تاني.", "CANCELLED", None),
    "weakTitle": ("Weak finger sensor", "حساس صباع ضعيف", "BLE-CONTRACT §6: #FLEX WEAK", None),
    "weakBody": ("{fingers}: the reading barely changed between Open and Fist. Make sure the glove fits snugly and calibrate again. If it keeps happening, the glove needs a check.", "{fingers}: القراءة تقريبًا متغيرتش بين «مفتوحة» و«قبضة». اتأكد إنك لابس الجوانتي مظبوط وعاير تاني. لو المشكلة فضلت، الجوانتي محتاج فحص.", "#FLEX WEAK", {"fingers": "String"}),
    "busyTitle": ("The glove is busy", "الجوانتي مشغول", "#ERR CAL BUSY", None),
    "busyBody": ("Wait a moment and try again.", "استنى شوية وجرّب تاني.", "#ERR CAL BUSY", None),
    "saveFailTitle": ("The glove couldn't save the calibration", "الجوانتي مقدرش يحفظ المعايرة", "#ERR CAL NVS / other #ERR CAL", None),
    "saveFailBody": ("Try again. If it keeps happening, the glove needs a check.", "جرّب تاني. لو المشكلة فضلت، الجوانتي محتاج فحص.", "#ERR CAL", None),
    "disconnectedTitle": ("The glove disconnected", "الجوانتي اتفصل", "step 6: link lost during calibration", None),
    "disconnectedBody": ("Pair it again to continue.", "وصّله تاني عشان تكمّل.", "step 6", None),
    "pairAgain": ("Pair again", "وصّل تاني", "step 6", None),
    "saving": ("Saving…", "بنحفظ…", "step 6: CAL SAVE running", None),
    "skipNeedsCal": ("This glove hasn't been calibrated yet, so calibration can't be skipped.", "الجوانتي ده لسه ما اتعايرش، فمينفعش تتخطّى المعايرة.", "Q-K6: Skip hidden with #CAL NONE", None),
    # --- ready (Q-K5)
    "sumGloveBatt": ("Connected · Battery {p}%", "متصل · بطارية {p}%", "replaces sumGlove (real battery)", {"p": "int"}),
    "sumGloveLow": ("Connected · Battery low", "متصل · البطارية ضعيفة", "replaces sumGlove (#BAT LOW)", None),
    "sumGloveUsb": ("Connected · On USB power", "متصل · شغال على USB", "replaces sumGlove (#BAT NO_BATTERY)", None),
}

STR = r'"((?:[^"\\]|\\.)*)"'
# Dart reserved words can't be getter names: such keys get a "Label" suffix.
DART_RESERVED = {"assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else",
                 "enum", "extends", "false", "final", "finally", "for", "if", "in", "is", "new", "null",
                 "rethrow", "return", "super", "switch", "this", "throw", "true", "try", "var", "void",
                 "while", "with"}


def js_str(s: str) -> str:
    return json.loads('"' + s + '"')


def parse_obj(block: str) -> dict:
    return {k: js_str(v) for k, v in re.findall(r"(\w+):" + STR, block)}


def section(s: str, start: str, end: str) -> str:
    a = s.index(start)
    return s[a:s.index(end, a)]


def main() -> int:
    src = prototype_src()
    s = src.read_text(encoding="utf-8")
    i18n = section(s, "var I18N = {", "// ---------- the cast")
    en = parse_obj(section(i18n, "en: {", "ar: {"))
    ar = parse_obj(i18n[i18n.index("ar: {"):])
    fem = parse_obj(section(s, "var I18N_FEM = {", "};"))
    if set(en) != set(ar) or not set(fem) <= set(ar):
        print("error: en/ar/fem keys differ", file=sys.stderr)
        return 1

    demo = section(s, "var DEMO = {", "};")
    for lang, d in (("en", en), ("ar", ar)):
        q = section(demo, f"{lang}: {{", "} }")
        q = q[q.index("q:{"):]
        for k, v in re.findall(r"(\w+):'((?:[^'\\]|\\.)*)'", q):
            d["qSay" + k[0].upper() + k[1:]] = v

    for d in (en, ar, fem):
        if "micHint" in d:
            m = re.fullmatch(r"<b>(.*?)</b>\s*(.*)", d.pop("micHint"))
            if m is None:
                print("error: micHint is no longer '<b>X</b> Y'", file=sys.stderr)
                return 1
            d["micHintStrong"], d["micHintRest"] = m.group(1), m.group(2)
    if set(en) != set(ar):
        print(f"error: en/ar differ after merging quick phrases: {sorted(set(en) ^ set(ar))}", file=sys.stderr)
        return 1

    unknown = set(EXCLUDED) - set(en) - {"micHint"}
    if unknown:
        print(f"error: EXCLUDED names unknown keys {sorted(unknown)}", file=sys.stderr)
        return 1

    out_en, out_ar = {"@@locale": "en"}, {"@@locale": "ar"}
    for key in sorted(en, key=str.lower):
        if key in EXCLUDED:
            continue
        e, a, f = en[key], ar[key], fem.get(key)
        ph = {}

        def conv(t: str) -> str:
            t = t.replace("Nour", "{name}").replace("نور", "{name}")
            return t

        e, a = conv(e), conv(a)
        f = conv(f) if f else None
        if f == a:
            f = None
        for p in re.findall(r"\{(\w+)\}", e + a + (f or "")):
            ph[p] = {"type": "int"} if p in ("n", "p") else {"type": "String"}
        if f:
            ph["gender"] = {"type": "String"}
            e = "{gender, select, female{" + e + "} other{" + e + "}}"
            a = "{gender, select, female{" + f + "} other{" + a + "}}"
        name = key + "Label" if key in DART_RESERVED else key
        out_en[name], out_ar[name] = e, a
        meta = {"description": f"prototype I18N.{key}"}
        if ph:
            meta["placeholders"] = ph
        out_en["@" + name] = meta

    for key, (e, a, src) in APPROVED_NEW.items():
        if key in out_en:
            print(f"error: approved key {key} clashes with a prototype key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        out_en["@" + key] = {"description": f"approved new text ({src})"}

    for key, (e, a, why, ph) in DRAFTS.items():
        if key in out_en:
            print(f"error: draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 6 review, 2026-10-10): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in (("app_en.arb", out_en), ("app_ar.arb", out_ar)):
        (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    kept = sum(1 for k in out_en if not k.startswith("@"))
    print(f"{kept} strings written ({len(DRAFTS)} step 6 texts), {len(EXCLUDED)} excluded:")
    for k, why in sorted(EXCLUDED.items()):
        print(f"  {k:14} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
