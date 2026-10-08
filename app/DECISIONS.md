# Decisions

User decisions use the IDs from `PHASE0-REPORT.md` §7 (answered 2026-10-08, after kit v3.2.1, commit `1bbd09d`). "Draft" means: show the text or screenshots to the user before it ships.

## Release blockers
| ID | Blocker |
|---|---|
| **RB-1** (Q-A1) | The Nour / Sara avatar models are "sample models, for non-commercial use". Fine for development and the graduation demo. **They must be replaced before any store release.** Avatar files stay swappable: the character list is data, and nothing in the code depends on the model files. |

## Machine and workflow
| ID | Decision |
|---|---|
| Q-M1 | Toolchain installed (Flutter 3.47.6 / Dart 3.13.5, Android SDK 36, build-tools 36.0.0, JDK 21, Node 22.23.3, firebase-tools 15.33.0, flutterfire_cli 1.4.1). Emulator `ishara_api36` is for development and for integration tests on the mock. The user's Android phone over USB is for anything BLE. CI runs everything that needs no device. Keep build outputs and caches lean (disk is tight). |

## Design
| ID | Decision |
|---|---|
| Q-D1 | The prototype wins on everything. Static screens are an older design: use them only as a pixel reference where they show the same screen with the same structure. Out of v1: hair / hijab / colour options, the SOS location sender, "Speak after a pause", "Simulate glove sign", "Work offline", male / female voice choice, Reconnect / Update. |
| Q-D2 | New screens and states are built from the prototype's own components. Screenshots and the full list of new EN + AR texts (Egyptian colloquial Arabic) go to the user for approval (draft). |
| Q-D3 | Theme follows the system; light is the fallback. |
| Q-D4 | Setup "I speak" opens Talk in face-to-face mode with the mic card first. "I sign" opens Talk with the glove text first. |

## Talk
| ID | Decision |
|---|---|
| Q-T1 | Remove the unsure-word chip, the "Did you mean" alternatives and the 75 % switch; use AI-SPEC tentative / confirm / cancel. **Tapping a tentative word confirms it and speaks it**, and it is logged as a user confirmation (not a Decider event). |
| Q-T2 | Each `word` / `confirm` is spoken when it arrives. When the conversation ends (`active_s` with no new confirmed word) or the user taps Clear, the live sentence moves to the feed as a "me" message. "Speak" repeats the current sentence aloud. "Type" adds typed words, spoken when sent. |
| Q-T3 | Speech to text uses the platform recognizer, preferring on-device when the phone supports it. Privacy states clearly that speech to text may use Google / Apple servers for the other person's voice. |
| Q-T4 | v1 SOS only speaks the SOS phrase aloud. "Emergency contact" is hidden. No SMS, no location. |
| Q-T5 | Arabic spoken text for all 20 labels: drafted in `signs.json` for approval. Aliases: keep `hi`, `hey` → hello; `i` → me; `thank` → thanks; `doctors` → doctor. Add the full phrases `السلام عليكم` → hello and `من فضلك` → please. Remove every other alias listed in report item 8. |

## Learn
| ID | Decision |
|---|---|
| Q-L1 | 5 modules: Start here (hello, thanks, please, yes, no); Numbers (one–five); People (me, you, iloveyou, come, call); Needs (water, drink, hungry, sorry, bye); Watch only (coffee, doctor, home, family, help: pick-the-meaning steps only). Modules with unapproved animations stay locked. |
| Q-L2 | XP: quiz +10, practice +15. Medal when a mission ends at ≥ 80 % accuracy. Streak = consecutive local days with at least one finished mission. "Signs learned" = passed at least once in practice (or in a quiz for watch-only signs). Unlock = finish the module above. Daily challenge = 5 random signs from unlocked modules, +30 XP, once a day. Practice: 8 s after "Sign now", 3 attempts. |
| Q-L3 | Drop the random per-finger tips. |
| Q-L4 | Match % = the smoothed average probability of the target label at the step where its `word` / `confirm` fired. |
| Q-L5 | Never fake anything. On the mock source, the practice check plays `mock/A/practice/<label>.csv` (or `B`) through the real pipeline; each confirms its sign exactly once. The old isolated files stay as they are. |
| Q-L6 | No "Share medal" in v1. |

## Glove and calibration
| ID | Decision |
|---|---|
| Q-K1 | BLE gap rule = AI-SPEC v3.2.1 §4 exactly (test: `test_vectors.json` → `gaps`). 1–5 missing: repeat the last accepted sample, the repeats count. More than 5 (and < 32768): emit `cancel` for a pending tentative word, then reset the window, the counter and the Decider, then push the sample. Duplicate or older (`gap ≥ 32768`): drop. `seq` is mod 65536. |
| Q-K2 | Pair copy (draft), only true facts: switch the glove on and keep it near the phone; it shows as `Ishara-XXXX`; show real RSSI, battery after connecting, `fw` from INFO. No button, no light colours. |
| Q-K3 | Pairing checks: (1) connect + MTU 247 + services; (2) INFO `proto == 1` + subscribe to EVENT (+ `#BAT`, no `#MPU FAIL`); (3) `GETCAL`. Check 2 is renamed "Checking the sensors". |
| Q-K4 | TURN lasts 3 s; the text says 3 seconds. |
| Q-K5 | Remove "96 % accuracy". |
| Q-K6 | Skip calibration is allowed only when the glove has a stored `#CAL {…}`. With `#CAL NONE`, Skip is hidden and the screen explains why. |
| Q-K7 | Finger bars are hidden until both OPEN and FIST are done. During OPEN / FIST a "hold still" indicator driven by the gyro is shown. |

## Avatar
| ID | Decision |
|---|---|
| Q-A1 | See RB-1. |
| Q-A2 | Avatar studio v1 = avatar picker + speed. `AvatarController.customize()` still exists. |
| Q-A3 | PLEASE keeps the B hand. SORRY keeps the A hand. I LOVE YOU is held still (remove the forward push). Vocabulary v2.1 (same PDF) now says the same. |
| Q-A4 | Rename the engine sign `love` → `iloveyou`. |
| Q-A5 | Remove the wrong-sign aliases (`my`, `your`, `house`, `sure`, `ok`, `okay`, `yeah`, `nope`, `أكيد`, `اكيد`, `السلام` alone, `فضلك` alone, `من`). The aliases kept in Q-T5 stay. |
| Q-A6 | Add finger spread to the engine as data plus a few lines in `curlHand`. Show FIVE vs FOUR and TWO vs NO in the preview screen. |
| Q-A7 | The user sends references for the 10 new signs before step 5. Steps 2–4 don't wait for them. |

## Backend
| ID | Decision |
|---|---|
| Q-B1 | Free Spark plan, **no Cloud Functions**. Account deletion: re-authenticate if Firebase requires it, the client deletes its own data, then the Auth user. Interruption-safe: a local "deletion pending" flag, retried on next launch. Code stays ready to move to a callable function. |
| Q-B2 | Email + password only. No Google, no phone number, no "Remember me". |
| Q-B3 | Unverified accounts can use the app; sync starts after the email is verified. |
| Q-B4 | History (signed and heard sentences) stays on the phone only. Starring makes it a saved phrase, which syncs. Titles come from date and time. |
| Q-B5 | Settings has a sign-language row using the same two pills as Setup, with the "Coming soon" badge on ArSL. |

## Source issues (report §6)
| ID | Resolution |
|---|---|
| C6 | Expect an exact match on every mock file in `expected.json` (now 88). If one differs, stop and ask. |
| C7 | AI-SPEC "rounded" = Python round-half-to-even, with a test. |
| C8 | Ignore `confirm_on_rest` and the top-level level defaults in `live.py`; not part of the spec. |
| C10, C11 | Fixed in kit v3.2.1. |
| C12 | Fixed in vocabulary v2.1 (Please = flat B, Sorry = A fist, I love you held still). |
| C14 | See Q-T3. |

## Technical decisions (mine)
| Date | Decision | Reason |
|---|---|---|
| 2026-10-08 | Read the prototype through `app/tools/strip_prototype.py` (outputs git-ignored in `app/tools/out/`) | The 12 MB file is mostly base64 GLBs; the script can be re-run and never touches `design/`. |
| 2026-10-08 | `docs/BLE-CONTRACT.md` is the BLE source; the kit copy is identical | The user's prompt names `docs/`. |
| 2026-10-08 | Avatar: `webview_flutter` + loopback HTTP server (planned for step 5) | First-party and maintained; ES modules don't load from `file://`. |
