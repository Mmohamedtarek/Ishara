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
    # step 9: untrue in the app (draft replacements in STEP9_DRAFTS)
    "histLead": "step 9: starring doesn't make a quick phrase (H1)",
    "searchPh": "step 9: there is no place to search (H2)",
    "toastStar": "step 9: not a quick phrase (H9)",
    "signedInAs": "step 9: nothing syncs before step 10 (S3)",
    "sPairS": "step 9: one glove at a time (S5)",
    "secAvatar": "step 9: no voice row (Q-D1) (S6)",
    "sVib": "step 9: S9-1 (S8)", "sVibS": "step 9: S9-1 (S9)",
    "sTheme": "step 9: a 3-way choice, Q-D3 (S10)", "sThemeS": "step 9: a 3-way choice (S10)",
    # Q-A2
    "avLook": "Q-A2", "avSkin": "Q-A2", "avHair": "Q-A2", "avOutfit": "Q-A2", "avGlasses": "Q-A2",
    # placeholders
    "toastSoon": "placeholder toast", "sAboutS": "fixed version (draft)",
    # step 7 answer 7: TTS reads "SOS · I need help" as "S O S"; sosSay (D23) is spoken instead
    "qSaySos": "step 7 answer 7 (replaced by sosSay)",
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

# Step 7 (Talk) texts D1-D23 (app/tools/out/step7/drafts.html), approved by
# the user as written on 2026-10-12 (DECISIONS S7-14).
STEP7_DRAFTS = {
    "talkToday": ("Today", "النهارده", "D1: feed day marker (step 7 answer 13: no place)", None),
    "toastSosSpoken": ("SOS spoken out loud.", "اتنطقت رسالة SOS بصوت عالي.", "D2: replaces toastSOS (Q-T4: no SMS); Arabic «SOS» (user's wording, step 9 review, 2026-10-15)", None),
    "sosSay": ("I need help, please.", "محتاج مساعدة من فضلك.", "D23: what the SOS quick phrase speaks (user, step 7 answer 7)", None),
    "micPermBody": ("Allow Ishara to use the microphone so it can hear the person you're talking to.", "اسمح للتطبيق يستخدم الميكروفون عشان يسمع الشخص اللي بتكلمه.", "D4: mic permission not given", None),
    "micPermBodySettings": ("Turn on the microphone permission for Ishara in your phone's settings.", "شغّل إذن الميكروفون لتطبيق إشارة من إعدادات الموبايل.", "D5: mic permission refused for good", None),
    "sttUnavailable": ("Speech recognition isn't available on this phone.", "التعرّف على الكلام مش متاح على الموبايل ده.", "D6: no recognizer", None),
    "sttNoEnglish": ("This phone can't recognize English speech yet.", "الموبايل ده لسه مش بيتعرّف على الكلام بالإنجليزي.", "D7: no English recognition", None),
    "sttNoArabic": ("This phone can't recognize Arabic speech yet.", "الموبايل ده لسه مش بيتعرّف على الكلام بالعربي.", "D8: no Arabic recognition", None),
    "sttNothingHeard": ("Didn't catch that. Tap the mic and try again.", "مسمعتش كويس. دوس على الميكروفون وجرّب تاني.", "D9: nothing heard", None),
    "gloveOff": ("Glove not connected", "الجوانتي مش متصل", "D10: glove chip, no glove", None),
    "gloveReconnecting": ("Reconnecting…", "بيتوصّل تاني…", "D11: glove chip, reconnecting", None),
    "gloveBattLow": ("Glove battery low", "بطارية الجوانتي قربت تخلص", "D12: glove chip, #BAT LOW", None),
    "liveNoGlove": ("Connect your glove to sign.", "وصّل الجوانتي عشان تعمل الإشارة.", "D13: live box, no glove", None),
    "liveNoCal": ("Calibrate your glove to start signing.", "عاير الجوانتي عشان تبدأ تعمل الإشارة.", "D14: live box, #CAL NONE", None),
    "liveStopped": ("Sign recognition stopped. Reconnect the glove and try again.", "التعرّف على الإشارات وقف. وصّل الجوانتي تاني وجرّب.", "D15: recognizer failed", None),
    "ttsNoVoice": ("This phone has no {language} voice, so words are shown but not spoken.", "الموبايل ده مفيهوش صوت {language}، فالكلمات هتظهر بس مش هتتنطق.", "D16: no TTS voice", {"language": "String"}),
    "tentativeLabel": ("{word}, not sure yet. Double-tap to confirm.", "{word}، لسه مش متأكد. دوس مرتين عشان تأكدها.", "D17: screen reader, tentative word", {"word": "String"}),
    "micLabel": ("Tap and speak", "دوس واتكلم", "D18: screen reader, mic button (prototype aria-label)", None),
    "privacySpeech": ("Speech to text uses your phone's speech recognizer. On some phones it sends the other person's voice to Google or Apple to turn it into text. Your signs and sentences stay on your phone.", "تحويل الكلام لنص بيستخدم خاصية التعرّف على الكلام في موبايلك. في بعض الموبايلات بيبعت صوت الشخص التاني لجوجل أو أبل عشان يحوّله لنص. إشاراتك وجملك بيفضلوا على موبايلك.", "D19: Q-T3 privacy line", None),
    "clearLabel": ("Clear and move to the conversation", "امسح وانقل للمحادثة", "D22: screen reader, Clear (Q-T2)", None),
    # D16's {language}, as listed with D16 on the approved drafts page
    "langNameEn": ("English", "إنجليزي", "D16 value: the English voice", None),
    "langNameAr": ("Arabic", "عربي", "D16 value: the Arabic voice", None),
}

# Step 7 texts written after the D1-D23 approval. D24 approved by the user
# on 2026-10-13 (DECISIONS S7-16). New drafts get "DRAFT" until approved.
STEP7_NEW_DRAFTS = {
    "sttTryShortSentence": ("Try saying it in a short sentence.", "جرّب تقولها في جملة قصيرة.", "D24: under D9 when nothing was heard (the phone's recognizer drops very short words said alone)", None),
}

# Step 7b texts: D25 approved by the user on 2026-10-13 (DECISIONS S7-26).
STEP7B_DRAFTS = {
    "typeAddLabel": ("Add", "ضيف", "D25: screen reader, the Type box's send button (prototype aria-label)", None),
}

# Step 8 (Learn) texts L1-L20, approved by the user on 2026-10-15 (DECISIONS
# S8-5); L17's Arabic is the user's wording.
STEP8_TEXTS = {
    "mNumbers": ("Numbers", "الأرقام", "L1: module title (Q-L1)", None),
    "mPeople": ("People", "الناس", "L2: module title (Q-L1)", None),
    "mNeeds": ("Needs", "الاحتياجات", "L3: module title (Q-L1)", None),
    "mWatchOnly": ("Watch only", "مشاهدة بس", "L4: module title (Q-L1: pick-the-meaning steps only)", None),
    "mDailySigns": ("{n} signs · keep your streak", "{n} إشارات · حافظ على سلسلتك", "L5: replaces mDailyS (Q-L2: no '3 minutes')", {"n": "int"}),
    "dailyDoneToday": ("Done for today · come back tomorrow", "خلصته النهارده · ارجع بكرة", "L6: daily challenge already played today (S8-4)", None),
    "yourTurnSign": ("Sign {w} with your glove.", "اعمل إشارة {w} بالجوانتي.", "L7: replaces yourTurnSub (no per-finger checking, Q-L3)", {"w": "String"}),
    "goodMatch": ("Good, {p}% match", "كويس، تطابق {p}%", "L8: practice passed under 92 % (okMatch without its tip, Q-L3)", {"p": "int"}),
    "practiceOther": ("Not quite. Watch {name} again and try once more.", "مش بالظبط. اتفرج على {name} تاني وجرّب مرة كمان.", "L9: another sign was recognized (never named)", {"name": "String"}),
    "practiceNothing": ("The glove didn't catch the sign. Try again.", "الجوانتي ملقطش الإشارة. جرّب تاني.", "L10: 8 s passed with no sign", None),
    "practiceOut": ("Out of tries for {w}. Let's move on.", "خلصت محاولاتك في {w}. يلا نكمّل.", "L11: 3 attempts failed (Q-L2)", {"w": "String"}),
    "practiceTry": ("Try {n} of {total}", "محاولة {n} من {total}", "L12: attempt counter", {"n": "int", "total": "int"}),
    "skipPractice": ("Continue without practice", "كمّل من غير تدريب", "L13: glove can't be used (S8-1)", None),
    "missionKeepGoing": ("Pass every sign to unlock the next module.", "عدّي كل الإشارات عشان تفتح الوحدة اللي بعدها.", "L14: result, the module isn't finished (S8-3); missionDoneS only when a module was unlocked", None),
    "missionNice": ("Nice work. Keep it up!", "شغل حلو. كمّل كده!", "L15: result, nothing new to unlock (finished before, last module, daily)", None),
    "medalEarned": ("Medal earned", "كسبت ميدالية", "L16: screen reader, the medal on the result", None),
    "noMedal": ("Reach {p}% accuracy to earn a medal.", "اوصل لدقة {p}% عشان تكسب ميدالية.", "L17: result without a medal (Q-L2: 80 %)", {"p": "int"}),
    "closeLabel": ("Close", "اقفل", "L18: screen reader, the mission's close button (prototype aria-label)", None),
    "missionStepOf": ("Step {n} of {total}", "خطوة {n} من {total}", "L19: screen reader, the mission's progress", {"n": "int", "total": "int"}),
    "passedOf": ("{done} of {total} passed", "عدّيت {done} من {total}", "L20: screen reader, a module's progress", {"done": "int", "total": "int"}),
}

# Step 8 review texts: L21, the forms the user gave on 2026-10-15 (S8-7),
# approved with its Arabic 0 form on 2026-10-15 (S8-10).
STEP8_DRAFTS = {
    "streakDays": (
        "{n, plural, =1{1 day} other{{n} days}}",
        "{n, plural, =0{{n} يوم} =1{يوم واحد} =2{يومين} few{{n} أيام} other{{n} يوم}}",
        "L21: streak chip (replaces 'N days'); AR 0 = «0 يوم» (user, same as 11+)",
        {"n": "int"},
    ),
}

# Step 9 texts (app/tools/out/step9/drafts.html): DRAFTS until approved.
# H = History, S = Settings, P = Privacy / About, A = Avatar studio,
# E = emergency contacts, O = the SOS sheet.
# Step 9 review (2026-10-15): new texts the user asked for, approved
# 2026-10-17 (step 10 brief). key: (en, ar, why, placeholders).
STEP9B_DRAFTS = {
    "sosLocOldHours": ("Last known location, about {n, plural, =1{1 hour} other{{n} hours}} ago (±{m} m)", "آخر مكان معروف، من حوالي {n, plural, =1{ساعة} =2{ساعتين} few{{n} ساعات} other{{n} ساعة}} (±{m} م)", "O17: last known, 1 h to 48 h old", {"n": "int", "m": "int"}),
    "sosLocOldDays": ("Last known location, about {n, plural, =1{1 day} other{{n} days}} ago (±{m} m)", "آخر مكان معروف، من حوالي {n, plural, =1{يوم} =2{يومين} few{{n} أيام} other{{n} يوم}} (±{m} م)", "O18: last known, 48 h or older", {"n": "int", "m": "int"}),
    "sosLocStale": ("This location may be out of date.", "المكان ده ممكن يكون قديم.", "O19: under a last known position older than 1 hour", None),
    "sosSmsFailed": ("Couldn't open the SMS app.", "مقدرناش نفتح تطبيق الرسايل.", "O20: no app opened for SMS", None),
    "sosCallFailed": ("Couldn't open the phone app.", "مقدرناش نفتح تطبيق الاتصال.", "O21: no app opened for a call", None),
    "sosCopy": ("Copy message", "انسخ الرسالة", "O22: copies the SOS message to paste anywhere", None),
    "toastCopied": ("Message copied", "الرسالة اتنسخت", "O23: toast after Copy message", None),
}

# Step 10 texts (app/tools/out/step10/drafts.html): DRAFTS until approved;
# N1 approved 2026-10-17.
# key: (en, ar, why, placeholders).
STEP10_DRAFTS = {
    "storageFull": ("Your phone is out of storage, so Ishara can't save new changes. Free up some space.", "مساحة الموبايل خلصت، فإشارة مش قادر يحفظ التغييرات الجديدة. فضّي شوية مساحة.", "N1: once per session, when a change can't be saved (your wording, step 10a review)", None),
}

# Talk voice (2026-10-26): hold to talk. TV1-TV15 approved 2026-10-26
# (app/tools/out/talk_voice/drafts.html).
TALKVOICE_DRAFTS = {
    "micHoldStrong": ("Hold the mic and speak.", "دوس مطوّل على الميكروفون واتكلم.", "TV1: mic hint, hold to talk (replaces micHintStrong «Tap the mic and speak.»)", None),
    "micTapStrong": ("Tap the mic, speak, then tap again.", "دوس على الميكروفون، اتكلم، وبعدين دوس تاني.", "TV2: mic hint in tap mode (screen reader, Switch Access, or the setting)", None),
    "micHoldLabel": ("Hold to talk", "دوس مطوّل واتكلم", "TV3: screen reader, mic button, hold to talk (replaces D18 «Tap and speak»)", None),
    "micStartLabel": ("Start recording", "ابدأ التسجيل", "TV4: screen reader, mic button in tap mode, not recording", None),
    "micStopLabel": ("Stop and send", "وقّف وابعت", "TV5: screen reader, mic button in tap mode, recording", None),
    "micCancelAction": ("Cancel recording", "الغي التسجيل", "TV6: screen reader action while recording (throws it away)", None),
    "micCancelled": ("Recording cancelled", "التسجيل اتلغى", "TV7: screen reader announcement after a cancel", None),
    "micSlideCancel": ("Slide to cancel", "اسحب للإلغاء", "TV8: while holding (your wording)", None),
    "micReleaseCancel": ("Release to cancel", "سيب عشان تلغي", "TV9: after sliding far enough", None),
    "micTooShort": ("Hold the mic while you speak.", "خليك دايس على الميكروفون وانت بتتكلم.", "TV10: released under 0.4 s, nothing sent", None),
    "micFinishing": ("One moment…", "لحظة…", "TV11: after release, waiting for the last words", None),
    "sttNothingHeardHold": ("Didn't catch that. Hold the mic and try again.", "مسمعتش كويس. دوس مطوّل على الميكروفون وجرّب تاني.", "TV12: D9 for hold to talk (tap mode keeps D9)", None),
    "micReplyHold": ("Hold the mic to reply", "دوس مطوّل على الميكروفون عشان ترد", "TV13: face to face, under your words (replaces micReply in hold mode)", None),
    "sMicTap": ("Tap to start and stop", "دوسة تبدأ ودوسة توقّف", "TV14: Settings › Accessibility", None),
    "sMicTapS": ("Record with a tap instead of holding the mic. On by itself with TalkBack.", "سجّل بدوسة بدل ما تفضل دايس على الميكروفون. بيشتغل لوحده مع TalkBack.", "TV15: under TV14", None),
}

# Talk voice: words with no sign (user decision 2026-10-26). NS1 approved, NS2 approved
# with the "few" form changed to «مالهمش» (user, 2026-10-27).
TALKVOICE_NS_DRAFTS = {
    "noSignYet": ("No sign yet", "لسه مالهاش إشارة", "NS1: screen reader, after a word the avatar has no sign for (caption and feed)", None),
    "noSignCount": ("{n, plural, =1{1 word has no sign yet} other{{n} words have no sign yet}}", "{n, plural, =1{كلمة واحدة لسه مالهاش إشارة} =2{كلمتين لسه مالهمش إشارة} few{{n} كلمات لسه مالهمش إشارة} other{{n} كلمة لسه مالهاش إشارة}}", "NS2: under a heard sentence in the feed when some words had no sign", {"n": "int"}),
}

# Prototype texts whose Arabic the user changed (key: (ar, why)).
AR_CHANGED = {
    "starred": ("المحفوظة", "Starred = «المحفوظة» everywhere (step 9 review, 2026-10-15)"),
    "sos": ("SOS · محتاج مساعدة", "«SOS» in every Arabic text, as the button (step 9 review, 2026-10-15)"),
}

STEP9_DRAFTS = {
    # History
    "histLeadPhone": ("Saved on this phone only. Star a sentence to keep it in Starred.", "متسجّل على الموبايل ده بس. علّم على جملة بنجمة عشان تفضل في المحفوظة.", "H1: replaces histLead", None),
    "searchWordPh": ("Search a word", "دوّر على كلمة", "H2: replaces searchPh", None),
    "messagesCount": ("{n, plural, =1{1 message} other{{n} messages}}", "{n, plural, =1{رسالة واحدة} =2{رسالتين} few{{n} رسائل} other{{n} رسالة}}", "H3: a conversation's size", {"n": "int"}),
    "histYesterday": ("Yesterday", "امبارح", "H4: title day marker", None),
    "histTitleAt": ("{day}, {time}", "{day}، {time}", "H5: conversation title (Q-B4: date and time)", {"day": "String", "time": "String"}),
    "histEmpty": ("No conversations yet. What you sign and hear in Talk shows up here.", "لسه مفيش محادثات. اللي بتعمله إشارة واللي بتسمعه في المحادثة هيظهر هنا.", "H6: empty History", None),
    "starredEmpty": ("Nothing starred yet. Open a conversation and tap the star next to a sentence.", "لسه مفيش حاجة محفوظة. افتح محادثة ودوس على النجمة جنب الجملة.", "H7: empty Starred", None),
    "searchEmpty": ("Nothing matches “{q}”.", "مفيش حاجة فيها «{q}».", "H8: no search results", {"q": "String"}),
    "toastStarred": ("Added to Starred", "اتحفظت", "H9: replaces toastStar", None),
    "toastUnstarred": ("Removed from Starred", "اتشالت من المحفوظة", "H10", None),
    "starLabel": ("Star", "احفظها", "H11: screen reader, star a sentence", None),
    "unstarLabel": ("Unstar", "شيلها من المحفوظة", "H12: screen reader, unstar", None),
    "deleteConversation": ("Delete conversation", "امسح المحادثة", "H13", None),
    "toastConvDeleted": ("Conversation deleted", "المحادثة اتمسحت", "H14: with Undo", None),
    "undo": ("Undo", "تراجع", "H15", None),
    "guestStarredNote": ("Guest mode: your starred phrases stay on this phone only.", "وضع الزائر: جملك المحفوظة هتفضل على الموبايل ده بس.", "H16: guest state", None),
    "speakPhraseLabel": ("Speak “{text}”", "انطق «{text}»", "H17: screen reader, a saved phrase", {"text": "String"}),
    # Settings
    "signedInAsEmail": ("Signed in as {email}", "داخل بـ {email}", "S3: replaces signedInAs", {"email": "String"}),
    "gloveNone": ("No glove paired", "مفيش جوانتي متوصّل", "S4: Settings › Glove, nothing paired", None),
    "pairReplaceS": ("Connect another glove instead of this one", "وصّل جوانتي تاني بدل ده", "S5: replaces sPairS", None),
    "gloveFirmware": ("Firmware {fw}", "السوفتوير {fw}", "S4b: the glove's firmware (INFO fw)", {"fw": "String"}),
    "secAvatarOnly": ("Avatar", "الأفاتار", "S6: replaces secAvatar (no voice row)", None),
    "avatarSpeedS": ("Sign speed {speed}x", "سرعة الإشارة {speed}x", "S7: replaces sAvatarS", {"speed": "String"}),
    "vibrateTitle": ("Vibrate", "الاهتزاز", "S8: replaces sVib (S9-1)", None),
    "vibrateS": ("Short pulse for words and replies, long for SOS", "نبضة قصيرة للكلام والردود، وطويلة لـ SOS", "S9: replaces sVibS (S9-1)", None),
    "appearance": ("Appearance", "المظهر", "S10: replaces sTheme (Q-D3)", None),
    "themeSystem": ("System", "زي الموبايل", "S11", None),
    "themeLight": ("Light", "فاتح", "S12", None),
    "themeDark": ("Dark", "غامق", "S13", None),
    "emergencyContacts": ("Emergency contacts", "أرقام الطوارئ", "S14: Settings row and screen title (Q-T4)", None),
    "emergencyNone": ("Not set · SOS can send them your location", "مش متحدّدة · من SOS تقدر تبعتلهم مكانك", "S15", None),
    "emergencyCount": ("{n, plural, =1{1 contact} other{{n} contacts}}", "{n, plural, =1{رقم واحد} =2{رقمين} few{{n} أرقام} other{{n} رقم}}", "S16", {"n": "int"}),
    "aboutVersion": ("Version {version}", "الإصدار {version}", "S17: replaces sAboutS", {"version": "String"}),
    "devModeOn": ("Developer mode on", "وضع المطوّرين اشتغل", "S18: 7 taps on the version", None),
    "devModeOff": ("Developer mode off", "وضع المطوّرين اتقفل", "S19", None),
    # Privacy, About
    "privacyIntro": ("Ishara works on your phone. Here is what it keeps and where.", "إشارة بيشتغل على موبايلك. ده اللي بيحتفظ بيه ومكانه فين.", "P1", None),
    "privacyGlove": ("Your signs are recognized on this phone. Glove data never leaves it.", "إشاراتك بتتعرف على الموبايل ده. بيانات الجوانتي مش بتخرج منه.", "P2", None),
    "privacyStored": ("Your conversations and your Learn progress stay on this phone.", "محادثاتك وتقدّمك في التعلّم بيفضلوا على الموبايل ده.", "P3", None),
    "privacyPhrases": ("Starred phrases stay on this phone too. A later version will keep them in your account when you're signed in.", "الجمل المحفوظة بتفضل على الموبايل ده كمان. إصدار جاي هيحفظها في حسابك لما تكون مسجّل دخول.", "P4: Q-B4, sync comes with step 10", None),
    "privacyLocation": ("Your location is read only when you press SOS, to put it in the message you choose to send. It is never tracked, stored or uploaded.", "مكانك بيتقري بس لما تدوس SOS، عشان يتحط في الرسالة اللي تختار تبعتها. مش بيتتبّع ولا بيتحفظ ولا بيترفع.", "P5: Q-T4 phase 1", None),
    "privacyContacts": ("Emergency contacts stay on this phone and are never sent anywhere.", "أرقام الطوارئ بتفضل على الموبايل ده ومش بتتبعت لأي مكان.", "P6", None),
    "exportData": ("Export my data", "صدّر بياناتي", "P7", None),
    "exportDataS": ("A file with your conversations, starred phrases and Learn progress", "ملف فيه محادثاتك وجملك المحفوظة وتقدّمك في التعلّم", "P8", None),
    "clearHistory": ("Clear history", "امسح السجل", "P9", None),
    "clearHistoryS": ("Deletes your conversations on this phone. Starred phrases stay.", "بيمسح محادثاتك من الموبايل ده. الجمل المحفوظة بتفضل.", "P10", None),
    "clearHistoryTitle": ("Clear all conversations?", "تمسح كل المحادثات؟", "P11: confirmation", None),
    "clearAction": ("Clear", "امسح", "P12", None),
    "cancelAction": ("Cancel", "إلغاء", "P13", None),
    "toastHistoryCleared": ("History cleared", "السجل اتمسح", "P14", None),
    "licences": ("Open-source licences", "تراخيص البرامج المفتوحة المصدر", "P15", None),
    # Avatar studio
    "discardTitle": ("Discard your changes?", "تلغي التغييرات؟", "A1: leaving without Save", None),
    "discardBody": ("Your avatar changes aren't saved.", "تغييرات الأفاتار متحفظتش.", "A2", None),
    "discardAction": ("Discard", "الغيها", "A3", None),
    "keepEditing": ("Keep editing", "كمّل تعديل", "A4", None),
    # Emergency contacts
    "emergencyLead": ("Up to 3 people. From SOS you can send them your location by SMS or WhatsApp, or call them.", "لحد 3 أشخاص. من SOS تقدر تبعتلهم مكانك برسالة أو واتساب، أو تكلّمهم.", "E1", None),
    "addContact": ("Add contact", "ضيف رقم", "E2", None),
    "pickFromContacts": ("Choose from your contacts", "اختار من الأسماء اللي عندك", "E3: system picker, no permission", None),
    "contactName": ("Name", "الاسم", "E4", None),
    "contactPhone": ("Phone number", "رقم التليفون", "E5", None),
    "contactPhoneHint": ("01x xxxx xxxx or +…", "01x xxxx xxxx أو +…", "E6", None),
    "contactPhoneInvalid": ("Enter an Egyptian number (01…) or an international one starting with +.", "اكتب رقم مصري (01…) أو رقم دولي بيبدأ بـ +.", "E7", None),
    "contactNameEmpty": ("Enter a name.", "اكتب الاسم.", "E8", None),
    "saveAction": ("Save", "احفظ", "E9", None),
    "removeContact": ("Remove", "امسح", "E10", None),
    "contactsFull": ("You can add up to 3 contacts.", "تقدر تضيف لحد 3 أرقام بس.", "E11", None),
    "locationAskTitle": ("Allow location for SOS?", "تسمح بالموقع لـ SOS؟", "E12: asked once, when the first contact is added", None),
    "locationAskBody": ("When you press SOS, Ishara reads your location once so you can send it to your contacts. It is never tracked or stored.", "لما تدوس SOS، إشارة بيقرا مكانك مرة واحدة عشان تقدر تبعته للأرقام دي. مش بيتتبّع ولا بيتحفظ.", "E13", None),
    "notNow": ("Not now", "مش دلوقتي", "E14", None),
    # SOS sheet
    "sosTitle": ("SOS", "SOS", "O1: sheet title", None),
    "sosLocating": ("Getting your location…", "بنجيب مكانك…", "O2", None),
    "sosLocFresh": ("Your location (±{m} m)", "مكانك (±{m} م)", "O3: a fresh fix", {"m": "int"}),
    "sosLocOld": ("Last known location, about {n, plural, =1{1 minute} other{{n} minutes}} ago (±{m} m)", "آخر مكان معروف، من حوالي {n, plural, =0{أقل من دقيقة} =1{دقيقة} =2{دقيقتين} few{{n} دقايق} other{{n} دقيقة}} (±{m} م)", "O4: last known, with its age", {"n": "int", "m": "int"}),
    "sosLocNone": ("Couldn't get your location. You can still send a message or call.", "مقدرناش نجيب مكانك. لسه تقدر تبعت رسالة أو تتصل.", "O5", None),
    "sosLocOff": ("Location is off for Ishara.", "إشارة مش مسموحله يستخدم الموقع.", "O6: permission denied", None),
    "sosSms": ("Send location by SMS", "ابعت المكان برسالة", "O7: opens the SMS app, filled in", None),
    "sosSmsNoLoc": ("Send SMS", "ابعت رسالة", "O7b: without a location", None),
    "sosWhatsApp": ("Send on WhatsApp", "ابعت على واتساب", "O8", None),
    "sosWhatsAppTo": ("Send on WhatsApp to {name}", "ابعت على واتساب لـ{name}", "O9: one contact", {"name": "String"}),
    "sosCall": ("Call {name}", "كلّم {name}", "O10: opens the dialer", {"name": "String"}),
    "sosAmbulance": ("Call ambulance {number}", "كلّم الإسعاف {number}", "O11: opens the dialer", {"number": "String"}),
    "sosAddContact": ("Add an emergency contact", "ضيف رقم طوارئ", "O12: no contacts yet", None),
    "sosSendTo": ("Send to", "ابعت لـ", "O13: pick one contact for WhatsApp", None),
    "sosMessage": ("I need help. My location: {link} (±{m} m, {time})", "محتاج مساعدة. مكاني: {link} (±{m} م، {time})", "O14: the message (app language)", {"link": "String", "m": "int", "time": "String"}),
    "sosMessageNone": ("I need help. I couldn't get my location.", "محتاج مساعدة. مقدرتش أجيب مكاني.", "O15: the message without a location", None),
    "sosNothingSent": ("Nothing is sent until you tap Send there.", "مفيش حاجة بتتبعت غير لما تدوس إرسال هناك.", "O16: under the actions", None),
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

    unknown = (set(EXCLUDED) | set(AR_CHANGED)) - set(en) - {"micHint"}
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

        changed = AR_CHANGED.get(key)
        if changed:
            a, f = changed[0], None
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
        if changed:
            meta["description"] += f"; Arabic changed: {changed[1]}"
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

    for key, (e, a, why, ph) in STEP7_DRAFTS.items():
        if key in out_en:
            print(f"error: step 7 key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 7, 2026-10-12): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in STEP7_NEW_DRAFTS.items():
        if key in out_en:
            print(f"error: step 7 draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        out_en["@" + key] = {"description": f"approved new text (step 7, 2026-10-13): {why}"}

    for key, (e, a, why, ph) in STEP7B_DRAFTS.items():
        if key in out_en:
            print(f"error: step 7b draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        out_en["@" + key] = {"description": f"approved new text (step 7b, 2026-10-13): {why}"}

    for key, (e, a, why, ph) in STEP8_TEXTS.items():
        if key in out_en:
            print(f"error: step 8 key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 8, 2026-10-15): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in STEP8_DRAFTS.items():
        if key in out_en:
            print(f"error: step 8 draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 8 review, 2026-10-15): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in STEP9_DRAFTS.items():
        if key in out_en:
            print(f"error: step 9 draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 9, 2026-10-15): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in STEP9B_DRAFTS.items():
        if key in out_en:
            print(f"error: step 9 review draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 9 review, 2026-10-17): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in STEP10_DRAFTS.items():
        if key in out_en:
            print(f"error: step 10 draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (step 10, 2026-10-17): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in TALKVOICE_DRAFTS.items():
        if key in out_en:
            print(f"error: talk voice draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (talk voice, 2026-10-26): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    for key, (e, a, why, ph) in TALKVOICE_NS_DRAFTS.items():
        if key in out_en:
            print(f"error: no-sign draft key {key} clashes with an existing key", file=sys.stderr)
            return 1
        out_en[key], out_ar[key] = e, a
        meta = {"description": f"approved new text (talk voice, 2026-10-27): {why}"}
        if ph:
            meta["placeholders"] = {k: {"type": v} for k, v in ph.items()}
        out_en["@" + key] = meta

    OUT.mkdir(parents=True, exist_ok=True)
    for name, data in (("app_en.arb", out_en), ("app_ar.arb", out_ar)):
        (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    kept = sum(1 for k in out_en if not k.startswith("@"))
    print(f"{kept} strings written ({len(DRAFTS)} step 6 texts, {len(STEP7_DRAFTS)} step 7 texts, {len(STEP7_NEW_DRAFTS)} new drafts), {len(EXCLUDED)} excluded:")
    for k, why in sorted(EXCLUDED.items()):
        print(f"  {k:14} {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
