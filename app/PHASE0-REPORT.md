# Ishara app: Phase 0 report

Date: 2026-10-08. Everything below comes from reading the sources in full. Where I am not sure, I say so. Your decisions are needed on the questions in **section 7**. No app code has been written.

Files created in Phase 0:
- `CLAUDE.md` (rules for every session)
- `app/tools/strip_prototype.py`: writes `app/tools/out/prototype/prototype.stripped.html` (205 KB, 2,110 lines) and `glb/nour.glb` (4,197,048 B) and `glb/sara.glb` (4,952,968 B). `app/tools/out/` is git-ignored.
- this report, `app/PROGRESS.md`, `app/DECISIONS.md`

---

## 0.1 Toolchain

### What this machine has
| Item | Status |
|---|---|
| Ubuntu 24.04.4, x86_64, 15 GB RAM, KVM CPU support | ok |
| **Free disk on `/`** | **7.9 GB (92 % used). Not enough.** Flutter, the Android SDK and an emulator image, plus Gradle caches, need about 20–25 GB. **This blocks everything else.** |
| Flutter / Dart | missing (latest stable: **Flutter 3.47.6 / Dart 3.13.5**, 2026-10-01) |
| JDK | only `javac` 1.8 (JDK 8) plus a Java 21 **JRE**. Android builds and the Firebase emulators need a full JDK 21 (or 17). |
| Android SDK, cmdline-tools, adb, emulator | missing |
| `/dev/kvm` | present, but your user is not in the `kvm` group |
| Node.js | 18.19.1. `firebase-tools` 15.33.0 needs Node 20 or newer. |
| Firebase CLI, FlutterFire CLI | missing |
| git, curl, unzip, xz, zip, libglu1-mesa | ok |

### Commands to run (in order)
```bash
# 0) Free about 25 GB on / first (check with: df -h ~)

# 1) System packages (needs sudo)
sudo apt-get update
sudo apt-get install -y openjdk-21-jdk-headless
sudo usermod -aG kvm "$USER"        # then log out and back in

# 2) Flutter 3.47.6 (no sudo)
mkdir -p ~/development
curl -L https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.6-stable.tar.xz \
  | tar -xJ -C ~/development

# 3) Android command-line tools (no sudo)
mkdir -p ~/Android/Sdk/cmdline-tools
curl -L -o /tmp/clt.zip https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
unzip -q /tmp/clt.zip -d ~/Android/Sdk/cmdline-tools && mv ~/Android/Sdk/cmdline-tools/cmdline-tools ~/Android/Sdk/cmdline-tools/latest && rm /tmp/clt.zip

# 4) Environment (add to ~/.zshrc, then: source ~/.zshrc)
cat >> ~/.zshrc <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=$HOME/Android/Sdk
export PATH="$HOME/development/flutter/bin:$HOME/.pub-cache/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
EOF
source ~/.zshrc

# 5) Android SDK packages, licences and a mid-range emulator
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator" "system-images;android-36;google_apis;x86_64"
avdmanager create avd -n ishara_api36 -k "system-images;android-36;google_apis;x86_64" -d pixel_5
flutter config --android-sdk "$ANDROID_HOME" --jdk-dir "$JAVA_HOME" --no-enable-linux-desktop --no-enable-web
flutter doctor --android-licenses

# 6) Node 22 LTS through nvm (no sudo), then the Firebase CLI
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
source ~/.zshrc && nvm install 22 && nvm alias default 22
npm install -g firebase-tools@15.33.0

# 7) FlutterFire CLI
dart pub global activate flutterfire_cli 1.4.1

# 8) Check
flutter doctor -v
```
If `flutter doctor` asks for a different JDK, use `sudo apt-get install -y openjdk-17-jdk-headless` and point `JAVA_HOME` and `flutter config --jdk-dir` at it. Gradle downloads any other `platforms;android-NN` it needs by itself once the licences are accepted. A USB phone also works instead of the emulator (enable USB debugging; `adb devices`). It is also the only way to test real BLE.

When you're done, paste the output of `flutter doctor -v` and I'll check it.

### iOS (can't be built on Linux)
The code will stay iOS-ready. Things to finish on a Mac:
- `pod install`, an Xcode build, signing, and a TestFlight upload;
- `Info.plist` keys (I will add them): `NSBluetoothAlwaysUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, and `NSAppTransportSecurity → NSAllowsLocalNetworking` (the avatar is served from loopback);
- testing on a device:
  - CoreBluetooth with the glove (iOS picks its own MTU, usually 185);
  - WKWebView loading ES modules from loopback;
  - the avatar frame rate;
  - Arabic and English speech to text, and on-device recognition;
  - Arabic TTS voices;
  - VoiceOver;
  - App Check with App Attest;
  - Crashlytics dSYM upload.

---

## 0.3 Report

### 1. Screen map

Navigation in the prototype: a stack (`go` / `back`) plus 4 tabs (Talk, Learn, History, Settings); the tab bar shows only on the 4 tab screens. Screen change: slide-in from the side (from the left in RTL) in 0.38 s; Ready and Mission use a "pop" animation. Theme: **light is the default** (stored in `ishara-theme`). App language: `en` by default; Arabic sets `dir=rtl`, uses the Cairo font and mirrors the arrows. The prototype has no loading, error or offline states anywhere.

| # | Screen | How you get there | States in the prototype | Missing (I must design them from existing components) |
|---|---|---|---|---|
| 0 | Splash | app start; ends after 2.1 s or a tap | logo, tagline, progress bar | — |
| 1 | Welcome | after the splash; Sign out | avatar hero with a "Hi, I'm Nour!" bubble, plays `hello` | — |
| 2 | Login / Create account | Welcome "Get started" (sign up) or "I already have an account" (sign in) | segmented toggle; field errors with `role=alert`; show/hide password; "Forgot password" (toast only); **Google** and **phone number** buttons; guest card | loading, auth errors, offline, email verification, reset flow |
| 3 | Setup (step 1/3) | after auth or guest | who (I sign / I speak), sign language (**ArSL selected by default**), voice (Arabic by default), avatar picker (Nour / Sara) | ArSL dialog and "Coming soon" badge |
| 4 | Pair (2/3) | Setup → Continue; Settings → "Pair a new glove" | scanning (radar) → found (device card) → connecting (3 animated checks) → connected; tips panel; "Scan again" | BT off, permission denied, location off (Android ≤ 11), not found / timeout, `proto ≠ 1`, connection lost |
| 5 | Calibrate (3/3) | Pair → Continue; Settings → Calibrate; Ready → "Calibrate again" | step 1 Open / 2 Fist / 3 Turn; idle → counting (fake hand animation) → captured; skip | step FAIL (MOVED / RANGE / MPU / CANCELLED), `#FLEX WEAK`, `#ERR CAL …`, disconnect |
| 6 | Ready | end of Calibrate, or Skip | calibrated ("96 % accuracy") / skipped variant | — |
| 7 | **Talk** (tab) | Ready → "Start talking"; tab | mic card idle / listening; face-to-face mode (card rotated 180°, signs text for the other person); avatar card with word-by-word caption; feed (them / me bubbles, "Today · Clinic" day marker); live box (placeholder, words, **unsure word** + "Did you mean" fix row); type box; Speak / Type / Clear; quick phrases incl. **SOS**; glove chip ("Glove connected 84 %") → Settings | glove disconnected, low battery, mic permission denied, STT unavailable, no calibration |
| 8 | **Learn** (tab) | tab | guest banner; stats (XP, signs learned, medals, streak chip); 7 modules (done / hero / locked) + daily challenge | empty (new user) |
| 9 | Mission | Learn → a module | quiz step (avatar loops a sign, 4 tiles, Check, right/wrong + replay at 0.6×); practice step (live hand + finger bars, "Sign now", fake countdown and random %); result (medal, XP, accuracy, time, "Share medal") | glove not connected, practice FAIL / timeout |
| 10 | History (tab) | tab | search; All / Starred; **4 fake conversations and 3 fake starred phrases** | empty, real data |
| 11 | Settings (tab) | tab; glove chip | profile (guest / signed in); Glove (→ Calibrate, → Pair); Avatar & voice (→ Avatar studio; Voice → "coming" toast; unsure-words switch; subtitles switch); Accessibility (vibrate, large text, high contrast); App (dark mode, language, emergency contact → "coming", Privacy → "coming", About → "coming", Sign out) | sign-language row (required by your prompt, not in the prototype), delete account, analytics opt-in, hidden developer switch |
| 12 | Avatar studio | Settings → Avatar | avatar picker, signing speed (1× → 0.5× → 1.5×), credits line, Save | — |

Feminine Arabic: when Sara is selected and the app is in Arabic, 7 strings use feminine forms (`I18N_FEM`). Every "Nour" / "نور" in a string becomes the selected avatar's name.

### 2. Avatar engine (prototype lines 1393–2105)

- **Loading:**
  - `import('three')`, `GLTFLoader.js` and `meshopt_decoder.module.js` come from **jsdelivr, three@0.186.0**, through an import map;
  - the fonts (Figtree, Cairo, Bricolage Grotesque) come from **Google Fonts**;
  - the GLBs are base64 strings in `window.__ISHARA_GLB`, decoded with `atob`.
  
  All of this must become local assets.
- **Characters (`CAST`):**
  - `nour` (male; outfit top recoloured `#2F3A56` to hide a vendor logo);
  - `sara` (female, `fem: true`).
  
  Both are `kind: 'glb'`, with per-character landmark adjustments (`lmAdj`). The credits line says: *"Avatars: Avaturn and Avatar SDK (MetaPerson) sample models, for non-commercial use."* There is also a dead code path (`buildRig`, `loadScript`) for a custom compressed format that no character uses.
- **Rig setup (`prepare`):**
  - scales to 1.72 m and centres the model;
  - finds bones through aliases (Mixamo-style names or `Bip01_*`);
  - measures the arm lengths, the hinge axes and the forearm twist shares;
  - measures a depth grid of the body front (`measure`), so contacts land on the skin;
  - places face landmarks (chin, mouth, cheek, forehead, chest) from the eye bones;
  - **bakes every sign once** into per-frame bone quaternions (`POSEQ`).
- **Keyframed signs:**
  - a sign is `{ frames: [{ t, R, L, head }] }`;
  - a hand key is `{ P, at, H, N, c }`:
    - `P`: a point in the signer's frame (x = signer's right, y = up, z = toward the viewer), or `[landmark, dx, dy, dz]` with dz measured from the skin;
    - `at`: `wrist`, `tip` or `palm`;
    - `H`: hand direction;
    - `N`: palm normal;
    - `c`: hand shape.
  - Missing R / L / head values carry over from the previous frame. The library starts from `READY_R` / `READY_L` (the relaxed "ready" pose).
- **Two-bone IK (`solveArm`):**
  - shoulder → target distance, clamped to the reachable range;
  - the elbow is placed by the law of cosines with a fixed pole vector `(.42, -1, -.28)`;
  - then `poseArm`:
    - aims the upper arm;
    - rolls it so the elbow hinge matches;
    - aims the forearm;
    - aims the hand (`H`);
    - rolls the hand to match the palm normal `N`, spreading the roll over the forearm twist bones.
- **Hand shapes (`CURL`):** one curl value per finger, 0–100, for thumb, index, middle, ring and pinky.
  - Each value is turned into degrees (`FMAX` = 80/250/255/255/250° in total) and split over the 3 joints (`FSPLIT`).
  - Existing shapes: `relax b open s a point w ily f flato bent no1 no2`.
  - **Limits:**
    - there is **no finger spread (abduction)**;
    - there is no per-joint control (for example "bent at the knuckles only");
    - thumb opposition is fixed.
  
  This matters for FIVE (spread) vs FOUR, for TWO (V, spread) vs NO (together), and for the bent-knuckle flap in BYE (section 3).
- **Library (`SIGNS`):** `rest` plus 15 signs: `hello thanks please sorry yes no help water coffee doctor home family love you me`.
- **Playback:**
  - the render loop samples the baked frames at `poseT·speed − LEAD` (LEAD = 0.32 s to travel into the first frame), with smoothstep between keys;
  - then it eases the bones toward the target (exponential, faster after the lead-in);
  - plus idle breathing and a neck sway (off with reduced motion);
  - blinking, a jaw "talking" movement while signing, and a slight smile, through morph targets.
  
  Camera: 24° FOV, framed from the top of the head to the waist, leaving room for the caption.
- **Word → sign (`poseNameFor`):**
  - normalize: lower case, strip Arabic diacritics and tatweel, drop everything that isn't `a-z` or Arabic;
  - then match, in order:
    1. a `SIGNS` key;
    2. the `ALIASES` table;
    3. `ISHARA_WORDS` en/ar names.
  - Before that, the page-level `avSign` groups multi-word phrases (`PHRASES`: "thank you", "i love you", "من فضلك", "لو سمحت", "السلام عليكم", "بحبك"…).
  - Unknown word: stays in `rest`, the mouth moves for 0.42 s, and the caption carries the word.
  - Timing: each sign lasts `(0.32 + last frame t + 0.25) / speed` s; an unknown word lasts `max(360, 520/speed)` ms.
- **`window.__avatarEngine`:**
  - `play(word, speed, loop)` returns `{known, ms}`; with `loop`, the sign replays after 0.8 s;
  - `stop()`;
  - `reframe()`;
  - `setAvatar(id)` loads the character, then plays `hello` at 0.8×;
  - `current()`;
  - `signFor(word)`;
  - `customize({skin, outfit})` tints the materials (the prototype UI never shows the swatches, because no character has `custom`);
  - `whenReady(fn)`;
  - `_dbg` (`pose(name, t)` freezes on a frame, which is useful for the front/side preview screen).
  
  There are **no events**: `signStarted` / `signEnded` / `error` have to be added.
- It also renders a 128 px face thumbnail per character with a **second WebGL context** (a cost on low-end phones).

### 3. Sign mismatches

**Confirmed (all 7 you listed):**
1. Glove signs: 20 (`labels.txt` minus `rest` / `other`). Avatar `SIGNS`: 15.
2. Glove signs with no animation: `one two three four five bye come drink call hungry` (10).
3. Avatar signs the glove can't recognize: `coffee doctor home family help` (5).
4. `love` (prototype) = `iloveyou` (model).
5. `MISSION_WORDS` asks for glove practice of `coffee`, `doctor`, `home`, `family`, `help`, which can never be checked. The modules affected are doctor, family, shop and sos; `start` and `greet` are fine.
6. The practice check is fake: a 2.4 s timer, a match % of `88 + random(0..8)`, a random tip ("straighten your index finger…"), and the step always passes.
7. Setup selects ArSL by default (`state.sign = 'arsl'`).

**New findings:**

8. **Wrong-sign word aliases** in `ALIASES`. These break your "never play the wrong sign" rule:
   - `my → me` (ASL MY is a flat palm on the chest, not a point);
   - `your → you` (ASL YOUR is a flat palm forward);
   - `house → home` (ASL HOUSE is a different sign);
   - `sure / ok / okay / yeah → yes` and `nope → no` (word substitution, not the same word);
   - `أكيد / اكيد → yes`;
   - `السلام` on its own → hello, and `فضلك` on its own → please (only the full phrases should match);
   - `من → ''` (harmless but odd).
   
   Probably fine: `hi / hey → hello` (ASL HI = HELLO), `i → me` (ASL I = ME), `thank → thanks`, `doctors → doctor`.
9. The prototype's normalization does **not** fold hamza / alef forms, ة/ه or ى/ي. That's why it needs duplicate keys (`اهلا` / `أهلا`, `اسف` / `آسف`, `ايوه` / `أيوه`).
10. Learn content far exceeds what exists: the modules promise signs that no part of the system has (*pain, medicine, appointment, pharmacy, allergy, mother, father, brother, sister, house, food, how much, cheap, expensive, receipt, card, police, hospital, fire, lost, teacher, exam, meeting, deadline, computer, nice to meet you, name, more*). The counts (12, 18, 15, 14, 10, 16 signs, "21 signs learned", 260 XP, 4-day streak, 2 medals) are fake.
11. The Talk "unsure word" UI (amber chip with "?", "Not sure about this word. Did you mean: book / look / cook", and the Settings switch "Ask me about unsure words · below 75 % confidence") **contradicts AI-SPEC §7** (tentative = faded + "…", no alternatives, the Decider owns the thresholds). The alternatives are fake.
12. The Talk "Speak" button speaks the whole live sentence and moves it to the feed. AI-SPEC says each `word` / `confirm` is spoken **when it arrives**. Nothing defines when a live sentence becomes a "me" message in the feed.
13. **Mock files that never produce a confirmed word** (from `expected.json`):
    - `A/one`, `A/me`, `A/drink`, `A/hungry`, `B/one`, `B/me`.
    
    In addition, `B/one.csv`'s only events are a tentative **`you`** (later cancelled), and `B/me.csv` ends on a tentative `one`. So on the mock, a real practice check for **`one` and `me` can never pass** with either person, and `drink` / `hungry` pass only with person B. The kit README says this is intentional (a single isolated sign needs a hold).
14. The mock files contain only a `#CAL` line: no `#BAT`, no connection events. `MockGloveSource` will produce those from a small mock script I write. That script is test data I own, not kit data.
15. Pair screen copy describes hardware that doesn't exist:
    - "Hold the button on the wrist strap for 3 seconds until the light blinks blue" and "The light turns white when it's ready". The firmware has **no button**, advertises all the time, and the XIAO LED is a plain **orange** LED.
    - "Ishara Glove G-01", "Right hand", "84 %", "Strong signal" and "v1.2.0" are fixed strings. Real values: `Ishara-XXXX`, RSSI, `#BAT`, and INFO `fw`.
    - The battery is only known **after** connecting (`#BAT` arrives when EVENT is subscribed), so the "found" card can't show it.
16. Calibration TURN: the prototype says "**4 seconds**" (EN and AR) and counts 4 s. BLE contract §7 says TURN takes **3 s**.
17. The Ready screen's "**96 % accuracy**" is invented: calibration produces no accuracy number.
18. "Skip calibration" in the prototype. The Recognizer **can't run without a calibration**: normalize needs `open`, `fist` and `gyro_bias_raw`. If the glove answers `#CAL NONE`, skipping leaves Talk and Learn with no recognition.
19. The finger % bars during the OPEN step need a calibration that doesn't exist yet. The values are undefined before calibration.
20. The prototype Settings has **no sign-language row**, but your prompt says Settings shows both options.
21. Setup "Who uses this phone? I sign / I speak" says it "decides what comes first on the Talk screen", but the prototype Talk ignores it.

### 4. Avatar vs. vocabulary v2

This table is read from the keyframe data, not yet watched frame by frame. In Step 5 I'll render each sign from the front and the side and recheck. Palm directions are in the signer's frame.

| Sign | Vocabulary v2 | Prototype animation | Match |
|---|---|---|---|
| **me** | index straight; points to own chest and touches it | `point` (index straight, others and thumb curled), fingertip moves 4 cm into the chest, palm faces the signer's left | **Yes** |
| **you** | index straight; points forward at the other person | `point`, hand pointing forward, small push forward, palm down | **Yes** |
| **hello** | B hand, thumb folded; fingertips at the side of the forehead, moves out and away (salute) | `b` (thumb curl 34/100), tip at the forehead, right side; moves up and out to the side; palm forward; small head tilt | **Yes** (I need to check visually that a 34 % thumb curl reads as "folded") |
| **thanks** | B hand; fingertips at the chin, forward and down, ends palm up | `b`, tip at the chin, palm toward the face; moves forward and down; ends palm up | **Yes** |
| **please** | flat **open** hand; palm on the chest, circles | `b` (thumb folded), palm on the chest, one circle of 4.5 cm radius over 1.3 s | **Partly**: shape is B (thumb folded), v2 says "flat open hand". Standard ASL PLEASE uses a flat B / open-B hand, so this may not matter. **Your call.** |
| **yes** | S fist; wrist nods up and down | `s` fist in front of the shoulder, wrist nods twice, plus head nods | **Yes** |
| **no** | index + middle straight together, snap shut onto the thumb, in front of the shoulder, twice | `no1` → `no2` twice in front of the shoulder, plus a head shake | **Yes** (fingers can't be shown "together" vs spread; see the engine limits) |
| **sorry** | fist (**A or S**); on the chest, circles. Note under the table: "Yes and Sorry use a fist with the thumb **resting on the fingers**" (= S) | `a` (thumb straight up along the side), palm on the chest, one circle | **Unclear**: the v2 table allows A; the v2 note says S. Standard ASL SORRY is usually the A hand. **Your call.** |
| **water** | W (index + middle + ring), thumb holds the pinky; the **index** fingertip taps the chin twice | `w` (thumb and pinky curled, 3 fingers straight); palm faces left; fingertips tap the chin twice | **Yes** (the contact point is computed from the middle-finger length; check visually) |
| **iloveyou** (`love`) | ILY (thumb + index + pinky); palm out, **held still** in front | `ily`, palm forward, pushed 6 cm forward over 0.6 s | **Almost**: v2 says held still; the prototype adds a small push. **Your call.** |
| home *(avatar only; v2 lists it as a **backup** glove sign)* | v2 backup: fingertips together, mouth then cheek | `flato`: mouth corner → cheek | **Yes** |
| help *(avatar only, not in v2)* | — (standard ASL: A hand, thumb up, on the flat other palm, both lift) | A hand on the flat left palm, both lift | Matches standard ASL as I know it (**not verified**). It is **two-handed**: v2 rules say no glove sign may need a second hand, so it can never become a glove sign. |
| coffee *(avatar only)* | — (standard ASL: S on S, the top hand grinds in a circle) | two S fists stacked, the top one circles | Matches as I know it (**not verified**); two-handed |
| doctor *(avatar only)* | — (standard ASL: D or M hand, or bent-B fingertips, tapping the inside of the other wrist) | bent fingertips tap the left wrist twice | Matches one common variant (**not verified**); two-handed |
| family *(avatar only)* | — (standard ASL: two F hands, palms out, circle out until the palms face in) | two F hands, palms out, circle out and meet with the palms in | Matches as I know it (**not verified**); two-handed |

For the 10 new animations, the engine needs new shapes:
- `one`: index up, thumb over the fingers (close to `point`, but the palm faces you);
- `two`: V;
- `three`: thumb + index + middle;
- `four`;
- `five`: open, spread;
- C (for `drink` / `hungry`);
- Y (for `call`);
- a bent-knuckle flap (for `bye`);
- an index curl in and out (for `come`).

**Spread (FIVE vs FOUR, TWO vs NO) can't be shown** by the current engine. Adding finger spread means adding new data (a spread value per shape) plus a few lines in `curlHand`, which goes beyond "port, not rewrite". I need your OK for that (Q-A6).

### 5. Architecture plan

```
app/
  ishara_app/                     Flutter app
    assets/
      kit/                        model/, mock/, test/: copied ONLY by tools/sync_kit.sh (checksum manifest)
      packs/asl/signs.json        catalogue (+ avatar sign library + model reference)
      packs/arsl/                 (later)
      avatar/                     index.html, engine.js (ported), three/ r186 module + GLTFLoader + meshopt, glb/
      fonts/                      Figtree, Cairo, Bricolage Grotesque (OFL), bundled
    lib/
      core/
        glove/                    GloveSource (interface), MockGloveSource, BleGloveSource, FrameDecoder,
                                  SerialCsvParser, EventLineParser, SampleSequencer (seq gaps), glove_providers
        recognition/              Normalizer, SampleWindow, Ensemble (tflite), Decider, Recognizer,
                                  RecognizerIsolate (long-lived; owns the interpreters)
        packs/                    SignLanguage enum, SignLanguagePack, PackRegistry (available flag), activePack provider
        catalogue/                Sign model, WordNormalizer (EN / AR), SpeechToSignMatcher (exact)
        avatar/                   AvatarController (typed), AvatarHost (one WebView for the whole app), LoopbackAssetServer
        speech/                   SpeechToText and TextToSpeech interfaces + platform implementations + fakes
        storage/                  drift database (local source of truth), outbox
        sync/                     SyncEngine (outbox ↔ Firestore), conflict rules
        auth/                     AuthRepository (Firebase / fake)
        errors/                   sealed Failure hierarchy (BleFailure, PermissionFailure, …)
        logging/                  structured logger (package:logging + JSON-ish records; Crashlytics sink)
        theme/                    tokens taken from the prototype CSS, light / dark / high contrast
        l10n/                     ARB en / ar (+ feminine variants)
        router/                   go_router (shell route for the 4 tabs)
      features/<feature>/{data,domain,presentation}
        onboarding (splash, welcome, auth, setup) · pair · calibration · talk · learn · history · settings · avatar_studio · dev (scenario player, sign preview)
    test/ integration_test/
  firebase/                       firebase.json, firestore.rules, firestore.indexes.json, functions/ (TS), rules tests
  tools/                          strip_prototype.py, sync_kit.sh, …
```

Main flows:
- **Glove:**
  - `GloveSource` exposes:
    - `connection` (a state stream);
    - `samples` (`Stream<SampleBatch>` with `seq`);
    - `events` (parsed `#…` lines);
    - `info`;
    - commands `scan / connect / disconnect / getCal / calStep / calSave / calCancel / battery / ping`.
  - One `SampleSequencer` (shared by both sources) applies the BLE gap rules.
  - `MockGloveSource` plays a scenario at real 50 Hz (5 samples per 100 ms tick, drift-corrected with a `Stopwatch`). In "BLE frame" mode it sends `ble_frames.txt`-style binary through the **same** `FrameDecoder`.
- **Recognizer:**
  - It runs in **one long-lived isolate**. The main isolate sends sample batches; the isolate runs normalize → window → 3 interpreters → average → Decider.
  - It returns `RecognitionEvent`s plus a `RecognitionStep` (step index, sample count, the averaged and smoothed probabilities).
  - The practice "match %" = **the smoothed average probability of the target label at the step where its `word` / `confirm` fired**. Please confirm (Q-L4).
  - Reset on reconnect and on a new `#CAL`, as the spec requires.
- **Avatar:**
  - one `WebView` kept alive at the app root, moved between screens with an `Overlay` + `CompositedTransformFollower` (like the prototype's single `#avatar` element);
  - three.js r186 (pinned 0.186.0, as in the prototype), the addons and the GLBs, served from a **loopback HTTP server** (`dart:io` `HttpServer` on 127.0.0.1, random port, random path token) that reads from the asset bundle;
  - JS ↔ Dart through one JavaScript channel with typed messages.
- **Data:** drift (SQLite) is the local source of truth for everything (guest and signed-in). A `SyncEngine` pushes an outbox to Firestore when signed in and pulls changes. Firebase is optional at runtime: with no `firebase_options`, the app uses the fakes.

### Packages (latest on pub.dev today; I'll pin exact versions in `pubspec.lock`)

| Package | Version | Why |
|---|---|---|
| flutter_riverpod / riverpod_annotation / riverpod_generator | 3.4.3 / 4.0.7 / 4.0.9 | state management with code generation (your stack) |
| go_router | 18.0.2 | navigation, deep links, shell route for the tabs |
| freezed / freezed_annotation | 4.0.2 / 3.1.0 | immutable models, sealed unions (events, failures) |
| json_serializable / json_annotation | 6.14.1 / 4.12.0 | `signs.json`, `decider.json`, `#CAL` JSON, INFO |
| flutter_localizations (SDK) + intl | 0.20.3 | ARB, EN / AR, RTL, plural / gender |
| **tflite_flutter** (tensorflow.org) *or* **flutter_litert** | 0.12.1 / 3.9.3 | runs the 3 `.tflite` models. tflite_flutter is official but last released 2025-10. flutter_litert is maintained (2026-09) and ships native libraries for desktop, which lets the model tests run in `flutter test` on Linux and in CI. **I'll test both in step 3 and record the choice** (both must also pass Google Play's 16 KB page-size check). |
| flutter_blue_plus | 2.3.14 | BLE central, MTU request, notify, write |
| webview_flutter | 4.14.1 | the avatar WebView (first-party; I'm not using flutter_inappwebview, which hasn't been released since 2024-10) |
| speech_to_text | 7.5.0 | Arabic / English speech to text (platform recognizer) |
| flutter_tts | 4.2.5 | Arabic (ar-EG if present) / English TTS |
| permission_handler | 13.0.2 | Bluetooth, location (Android ≤ 11), microphone, speech |
| drift / drift_dev + sqlite3 | 2.35.2 / 2.35.1 | local database, offline first, guest data, outbox (`sqlite3_flutter_libs` is end-of-life; drift now uses `sqlite3` 3.x) |
| firebase_core / firebase_auth / cloud_firestore | 4.15.0 / 6.7.0 / 6.10.0 | backend |
| firebase_crashlytics / firebase_analytics / firebase_app_check / cloud_functions | 5.4.0 / 12.6.0 / 0.4.8 / 6.5.0 | crash reports, opt-in analytics, App Check, account deletion call |
| connectivity_plus | 7.3.2 | online / offline banner, sync trigger |
| logging | 1.3.0 | structured logging |
| package_info_plus | 10.2.2 | About screen version |
| wakelock_plus | 1.8.1 | keeps the screen on in Talk while signing (to be confirmed) |
| *dev:* build_runner 2.16.2, very_good_analysis 11.0.0, mocktail 1.0.5, alchemist 0.14.1 (goldens), crypto 3.0.7 (checksum test), patrol 4.10.0 (integration tests that tap system permission dialogs) | | |
| *firebase/ (npm):* firebase-tools 15.33.0, firebase-functions 7.4.0, firebase-admin 14.5.0, @firebase/rules-unit-testing 6.0.0, TypeScript, vitest | | rules and functions tests in the emulator |
| *avatar (bundled, not CDN):* three 0.186.0 (`three.module.js`, `GLTFLoader.js`, `meshopt_decoder.module.js`) | MIT | same version as the prototype (0.186.1 exists, but I'll keep it identical) |

### Firestore data model (only for signed-in users; guests stay on the phone)
```
users/{uid}                         profile: displayName, createdAt, updatedAt, schemaVersion
users/{uid}/settings/app            uiLang, theme, signLanguage ('asl' only accepted in v1), spokenLanguage, who,
                                    avatarId, signSpeed, subtitles, bigText, highContrast, vibrate, analyticsOptIn, updatedAt
users/{uid}/activity/{eventId}      IMMUTABLE learn events: type (quiz|practice|missionDone), label, moduleId,
                                    passed, prob, xp, day (yyyy-mm-dd, local), at, deviceId
users/{uid}/phrases/{phraseId}      text, lang, createdAt, updatedAt, deleted (tombstone)
```
- **Conflicts:**
  - `settings` and `phrases`: last writer wins per document, by `updatedAt`, with the document id as tie-break; deletes are tombstones, so a delete made offline isn't brought back.
  - Learn progress is **never overwritten**: it's an append-only event log, so two offline phones merge with no loss. XP is a sum; medals, per-sign stats and the streak are **computed** from the log. I'll test this with two simulated devices.
- **Rules:**
  - `request.auth.uid == uid` on every path; everything else is denied;
  - field types, sizes and allowed values are checked (for example `signLanguage == 'asl'`);
  - `activity` documents are create-only;
  - `phrases.text` ≤ 500 characters;
  - writes require `email_verified` (Q-B3).
- **Account deletion:** a callable function `deleteMyAccount` (TypeScript) recursively deletes `users/{uid}`, then the Auth user, and the app wipes the local database. Cloud Functions need the **Blaze** plan (Q-B1).
- **Guest → account:** on sign-up, the local guest data is uploaded once through the same outbox.

---

## 6. Wrong or contradictory sources

| # | Where | Problem |
|---|---|---|
| C1 | `design/Figma-Import-Screens/` vs `design/prototype.html` | **They are different designs.** The static screens have: a 2D avatar; Learn as a searchable category list with an 11-sign list (Good morning, Police, Pain, Medicine, Eat…); an Avatar studio with hair / hijab / colour options; Settings with "Speak after a pause of 1.5 s", "Unsure-word threshold 75 %", "Work offline", voice Female / Male, Reconnect / Update; a status bar on Talk; a "Simulate glove sign" button; an SOS screen that **sends your location**; and "Try the demo without an account". Your prompt says the prototype decides the screens and the static screens are the pixel reference, so the two can't both be followed. **Q-D1** |
| C2 | prototype Login vs your prompt | The prototype has **phone-number login, Google sign-in, an "Egyptian mobile number or email" field and "Remember me"**. Your prompt: email + password + guest. **Q-B2** |
| C3 | prototype Talk vs AI-SPEC §7 | unsure-word chip + alternatives + the 75 % switch; sentence-level "Speak" button (items 11, 12) |
| C4 | prototype Calibrate vs BLE-CONTRACT §7 | TURN 4 s vs 3 s |
| C5 | prototype Pair vs firmware | a wrist button and a blue / white light that don't exist; fixed device name, battery and signal |
| C6 | AI-SPEC §8 vs your prompt | AI-SPEC says the words in `expected.json` come from the **Keras** model and "can very rarely move a word by one step" with .tflite. Your prompt requires the exact same events. The kit README says an independent implementation matched 48/48, so I expect an exact match. If one file differs by a step, I'll stop and ask. |
| C7 | AI-SPEC §5 "seconds × 5 (rounded)" vs `live.py` | `live.py` uses Python `round()` (round half to even). Dart's `round()` rounds halves away from zero. For today's numbers they agree (`3.5 × 5 = 17.5 → 18`, `4 × 5 = 20`), but `2.5 s` would give 12 in Python and 13 in Dart. I'll copy Python's behaviour (so a new `decider.json` behaves like `live.py`) and add a test. |
| C8 | `live.py` vs AI-SPEC | `live.py` supports a `confirm_on_rest` option and level defaults from top-level keys. AI-SPEC doesn't mention either; today's `decider.json` uses neither. If the AI team ever adds them, the app won't follow. Worth telling the AI team. |
| C9 | BLE-CONTRACT §4 gap rule | Not specified: after a gap > 5 samples clears the window, does the "multiple of 10" sample counter restart at 0? Do repeated (filled-in) samples count? What about a duplicate or backwards `seq`? These change the steps at which words come out on the real glove. **Q-K1 (for the AI team)** |
| C10 | BLE-CONTRACT INFO example `"fw":"0.4.0"` vs BLE-TESTING / firmware `0.3.0` | Only the example is off; the app doesn't depend on `fw`. |
| C11 | BLE-TESTING "Reading a DATA frame by hand" | Its hex example (`8e 07` = 1934) comes from the old v3.1 `hello.csv`; the current `ble_frames.txt` starts with `05 08` = 2053. It's a doc example only. |
| C12 | Vocabulary v2, SORRY | The table says A or S; the note says the thumb rests on the fingers (S). |
| C13 | Avatar licence | The credits say the avatars are **sample models for non-commercial use**. A store release (and probably Google Play) needs models we're allowed to ship commercially. **This blocks release, not development.** **Q-A1** |
| C14 | Privacy | `speech_to_text` uses the phone's recognizer. On many Android phones (and for Arabic) that recognizer **sends audio to Google / Apple servers** unless on-device mode is forced, which many phones don't support for Arabic. Your privacy rule covers sensor data and sentences; spoken audio from the other person isn't covered. **Q-T3** |
| C15 | `docs/` vs `app/Ishara-Mobile-Kit/BLE-CONTRACT.md` | The two are byte-identical today. The kit copy belongs to the kit and the `docs/` copy is the one I treat as the source. If they ever differ, I'll ask. |

---

## 7. Questions (your decisions)

**Design**
- **Q-D1** Prototype vs static screens (C1): which one wins, screen by screen? *My recommendation:* the prototype wins on everything (it's newer in behaviour, it has the 3D avatar, and it has the AR texts); the static screens are used only where they show the same screen in the same structure. Static-only features (hair / hijab, the SOS location sender, "Speak after a pause", "Simulate glove sign"…) are left out of v1.
- **Q-D2** New screens and states the prototype doesn't have: errors, permissions, BT off, the ArSL dialog, Delete account, Privacy, About, Voice, the hidden developer menu, email verification, password reset. OK if I build them from the prototype's own components (banner, card, row, tips) and send you screenshots for approval? All new English and Arabic text will be listed for you to approve. My Arabic will be Egyptian colloquial like the prototype, but it needs a native check.
- **Q-D3** Default theme: light (prototype) or follow the system?
- **Q-D4** What does Setup "I speak" change in Talk? (for example: open Talk in face-to-face mode with the mic card first). Or should the question be removed?

**Talk**
- **Q-T1** Remove the "unsure word" chip, the "Did you mean" alternatives and the "Ask me about unsure words (75 %)" switch, and use AI-SPEC tentative / confirm / cancel instead? (I recommend yes.) May the user tap a tentative word to confirm it (the kit README's optional idea)? If so, is it spoken when tapped?
- **Q-T2** The live sentence → the feed: proposal: a `word` / `confirm` is spoken right away (AI-SPEC). When the conversation ends (`active_s` with no new confirmed word) or the user taps Clear, the sentence moves to the feed as a "me" message. "Speak" **repeats** the current sentence out loud. "Type" adds typed words that are spoken when sent. OK?
- **Q-T3** Speech to text: allow the platform recognizer even when it uses the cloud (with a line in Privacy), or on-device only (Arabic may not work on many phones)?
- **Q-T4** SOS: v1 = speak the SOS phrase out loud only, and hide "Emergency contact"? (No SMS, no location.)
- **Q-T5** Arabic spoken text for the 20 labels (AI-SPEC §6 is English only). I'll draft them (e.g. `one → واحد`, `thanks → شكراً`, `iloveyou → بحبك`) in `signs.json` for your approval. Also: which aliases from item 8 stay?

**Learn**
- **Q-L1** Curriculum for v1, built only from the 20 glove signs + 5 avatar-only signs. Proposal:
  1. *Start here*: hello, thanks, please, yes, no;
  2. *Numbers*: one–five;
  3. *People*: me, you, iloveyou, come, call;
  4. *Needs*: water, drink, hungry, sorry, bye;
  5. *Watch only*: coffee, doctor, home, family, help (pick-the-meaning steps only).
  
  The prototype's modules (doctor, shop, school…) and their texts go away. Modules with signs that have no animation yet stay locked until you approve those animations. OK?
- **Q-L2** Rules I need from you, or approve mine:
  - XP: quiz +10, practice +15 (prototype);
  - medal when a mission ends with ≥ 80 % accuracy (prototype);
  - streak = consecutive local days with at least one finished mission;
  - "signs learned" = signs passed at least once in practice (or in a quiz if watch-only);
  - unlocking = finish the module above;
  - daily challenge = 5 random signs from unlocked modules, +30 XP, once a day;
  - practice time limit = 8 s after "Sign now", 3 attempts.
- **Q-L3** The prototype's per-finger tips ("straighten your index finger") are random. Drop them? (The model gives no per-finger feedback.)
- **Q-L4** Match % = the smoothed probability of the target label at the step its `word` / `confirm` fired (section 5). OK?
- **Q-L5** On the mock, "Sign now" for `one` and `me` will honestly **fail** (item 13), and `drink` / `hungry` pass only with person B. Accept it (honest), or should the AI team add mock files where these signs are held long enough?
- **Q-L6** "Share medal" (saves an image to the gallery, which needs a permission): keep or drop for v1?

**Glove / calibration**
- **Q-K1** (C9) Gap-reset details: I'll write my reading of them as a question for the AI team. Until they answer, I'll restart the sample counter after a reset and count the filled-in samples.
- **Q-K2** Pair copy: replace the wrist-button / light text with true text (e.g. "Switch on the glove and keep it close to your phone"). Do you want to write it, or shall I draft it?
- **Q-K3** The 3 pairing checks map to: (1) connect + MTU 247 + services; (2) read INFO, `proto == 1`, subscribe to EVENT (+ `#BAT`, no `#MPU FAIL`); (3) `GETCAL`. Check 2's text "Checking the 5 finger sensors" isn't what happens. Rename it to "Checking the sensors"?
- **Q-K4** TURN step: use 3 s (contract) and change the text to "3 seconds"?
- **Q-K5** Ready screen: remove "96 % accuracy" (there's no real number)?
- **Q-K6** Skip calibration: allow it only when the glove already has a stored calibration (`#CAL {…}`); with `#CAL NONE`, hide Skip and explain why?
- **Q-K7** Finger bars before calibration: show raw values scaled 0–4095, or hide the bars until OPEN is done?

**Avatar**
- **Q-A1** (C13) Avatar licence: do you have commercial rights to the Nour / Sara models, or do we need new models before release?
- **Q-A2** Settings / Avatar studio: v1 = avatar picker + speed only (prototype), with no skin / outfit / hair customization (static screens)? `customize()` will still exist in `AvatarController`.
- **Q-A3** PLEASE (B vs open hand), SORRY (A vs S), ILOVEYOU (still vs small push): keep as they are, or change? (Section 4)
- **Q-A4** Rename the engine's `love` sign key to `iloveyou` (data-only change)?
- **Q-A5** Remove the wrong-sign aliases from item 8 (`my, your, house, sure, ok, okay, yeah, nope, أكيد`, and `السلام` / `فضلك` on their own)?
- **Q-A6** Add finger spread to the engine (new per-shape data plus a few lines in `curlHand`) so FIVE ≠ FOUR and TWO ≠ NO can be shown? It goes slightly beyond "port, not rewrite".
- **Q-A7** References for the 10 new signs: please send them (video links or descriptions), as your prompt says.

**Backend**
- **Q-B1** Cloud Functions need the **Blaze** (pay-as-you-go) plan. OK? Otherwise the client deletes its own data and then the Auth user (works on Spark, but isn't atomic).
- **Q-B2** Remove the Google and phone-number login buttons and use an email-only field (C2)? "Remember me": keep it as a visual-only toggle, or remove it (Firebase keeps the session anyway)?
- **Q-B3** May an account with an unverified email use the app? (Proposal: yes, but sync starts only after the email is verified.)
- **Q-B4** History: proposal: conversations (signed and heard sentences) are kept **only on the phone**; starring one makes it a saved phrase that syncs. Titles come from date and time (no place names, because there's no location). OK?
- **Q-B5** Sign-language row in Settings: OK if it uses the same two pills as Setup (with the "Coming soon" badge)?

**Machine**
- **Q-M1** Free about 25 GB of disk and run the commands in 0.1; then send me `flutter doctor -v`.
