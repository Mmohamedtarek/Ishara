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
        "لغة الإشارة المصرية هتكون متاحة في تحديث قريب. حاليًا Ishara بيستخدم لغة الإشارة الأمريكية (ASL).",
        "user prompt, Sign language section",
    ),
    "ok": ("OK", "تمام", "user prompt, Sign language section"),
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

    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in (("app_en.arb", out_en), ("app_ar.arb", out_ar)):
        (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    kept = sum(1 for k in out_en if not k.startswith("@"))
    print(f"{kept} strings written, {len(EXCLUDED)} excluded:")
    for k, why in sorted(EXCLUDED.items()):
        print(f"  {k:14} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
