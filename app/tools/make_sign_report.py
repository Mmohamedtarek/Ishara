#!/usr/bin/env python3
"""Builds the sign review page: per sign, its contact sheet (front + side at
every keyframe, from avatar_shots.py), its Lifeprint link from
docs/ASL-REFERENCES.md, and the review status with the reason.

Usage (from app/tools): .venv/bin/python make_sign_report.py [--sheets out/review2]
Writes <sheets>/index.html (open it in a browser).
"""
from __future__ import annotations

import argparse
import html
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
APP = HERE.parent / "ishara_app"

# Step 5 review (user's emulator recording + review sheets): what happened to
# each sign. fixed / unchanged (was right) / needs your call.
STATUS: dict[str, tuple[str, str]] = {
    "one": ("unchanged (was right)", "Side view: palm back (toward the signer), index up, thumb over the fingers."),
    "two": ("unchanged (was right)", "Side view: palm back; V spread (Q-A6). TWO vs NO: spread vs together, see NO."),
    "three": ("fixed", "Thumb now swings out to the side (thumb spread), with index + middle; palm back."),
    "four": ("fixed", "Thumb folded across the palm: from the side it lies on the palm, unlike FIVE."),
    "five": ("fixed", "Thumb out to the side in the palm plane (thumb spread); fingers spread; palm back."),
    "bye": ("unchanged (was right)", "Open hand, palm out at shoulder height, fingers bend down and up twice, arm still."),
    "come": ("fixed", "Start now visible at chest height: index forward, palm up; one quick arc up toward the signer; no finger curl (V-2)."),
    "drink": ("fixed", "C hand travels in a short arc up to the chin, palm sideways, thumb toward the chin, then tilts; the hand stays below the lips, so the front view doesn't cover the mouth."),
    "call": ("fixed — please check", "Round 2: the Y hand sits beside the head (thumb at the ear, pinky toward the jaw and mouth corner), nothing covers the eye; the wrist is at the jaw, so the elbow is down and slightly out, well below the shoulder. Placed from the head ('ear' point), so it fits Sara too (her hair is not simulated: the arm passes through it, known issue)."),
    "hungry": ("fixed", "Deeper C, fingertips angled into the chest so the C reads from the front; moves down the chest once."),
    "water": ("fixed", "With the depth fix the W hand's fingertips touch the mouth twice (V-3)."),
    "iloveyou": ("unchanged (was right)", "Held still at its place (identical at every keyframe, Q-A3). The motion in the recording at 55-56 s is the lead-in from the ready pose and the return to it."),
    "you": ("fixed", "Points level, straight at the other person, at chest height (was slightly down); shorter push."),
    "me": ("fixed", "Depth fix: the index fingertip touches the chest."),
    "hello": ("fixed", "Depth fix: the fingertips touch the side of the forehead, then the salute moves out."),
    "thanks": ("fixed", "Depth fix: the fingertips touch the chin, then forward and down, palm up."),
    "please": ("fixed", "Depth fix: the flat B palm is on the chest while it circles."),
    "sorry": ("fixed", "Depth fix: the A fist is on the chest while it circles."),
    "home": ("fixed — please check the flat-O", "Round 2: flat-O at the corner of the mouth, then the cheekbone (not the temple), the hand tilted up into each touch so the elbow stays low. The flat-O is closed more onto the thumb; from straight in front it still looks a little loose."),
    "yes": ("unchanged (was right)", "Pixel-identical to the prototype. S fist nods at the wrist in front of the shoulder."),
    "no": ("unchanged (was right)", "Pixel-identical to the prototype. Index + middle together snap onto the thumb, twice."),
    "help": ("unchanged (matches the reference)", "Checked against Lifeprint HELP: loose-thumb A hand resting on the flat palm, both lift together (front and side)."),
    "coffee": ("unchanged (matches the reference)", "Checked against Lifeprint COFFEE: two S fists stacked, the bottom still, the top circles like a grinder (front and side)."),
    "doctor": ("needs your call", "Checked against Lifeprint DOCTOR: the bent-B fingertips tap the middle of the other PALM, not the inside of the WRIST (the pulse) as the recommended version. Not changed (sign rule 1); fix = move the tap target about 5 cm toward the wrist."),
    "family": ("unchanged (matches the reference)", "Checked against Lifeprint FAMILY: two F hands start together palms out, circle apart and meet again palms in (front and side)."),
}


def references() -> dict[str, str]:
    refs = {}
    for line in (REPO / "docs" / "ASL-REFERENCES.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\|\s*`(\w+)`\s*\|[^|]*\|\s*\[[^\]]*\]\((https?://[^)]+)\)", line)
        if m:
            refs[m[1]] = m[2]
    return refs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheets", type=Path, default=HERE / "out" / "review2")
    a = ap.parse_args()
    cat = {s["label"]: s for s in json.loads((APP / "assets/packs/asl/signs.json").read_text(encoding="utf-8"))["signs"]}
    refs = references()
    order = [l for l in cat if (a.sheets / f"{l}_nour.png").exists()]
    rows = []
    for label in order:
        s = cat[label]
        status, why = STATUS.get(label, ("needs your call", "not reviewed"))
        ref = refs.get(label)
        link = f'<a href="{html.escape(ref)}">{html.escape(ref)}</a>' if ref else "<i>no reference in docs/ASL-REFERENCES.md</i>"
        badge = {"fixed": "#1F7A4D", "unchanged (was right)": "#3446C9"}.get(status, "#B26A00")
        rows.append(
            f'<section><h2>{html.escape(s["en"]["word"])} <code>{label}</code>'
            f' <span class="b" style="background:{badge}">{html.escape(status)}</span>'
            f' <span class="m">{"glove" if s["glove"] else "avatar only"} · avatar: {str(s["avatar"]).lower()}'
            f' · verified: {str(s["verified"]).lower()}</span></h2>'
            f'<p><b>Reference:</b> {link}<br><b>Vocabulary:</b> {html.escape(s["description"])}<br>'
            f'<b>Review:</b> {html.escape(why)}</p>'
            f'<img src="{label}_nour.png" alt="{label}: front (top) and side (bottom) at each keyframe">'
            + (
                f'<details><summary>Before this review (step 5 commit 1f673ab; for the prototype\'s signs this '
                f'renders like the prototype)</summary><img src="../ba_before/{label}_nour.png" '
                f'alt="{label} before: front and side"></details>'
                if (a.sheets.parent / "ba_before" / f"{label}_nour.png").exists() else ""
            )
            + "</section>"
        )
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Avatar sign review</title>
<style>body{{font:15px/1.5 system-ui,sans-serif;margin:0 auto;max-width:1400px;padding:16px;background:#F4F2EC;color:#15171C}}
h1{{font-size:24px}} h2{{font-size:19px;margin:28px 0 6px}} code{{font-size:14px}} img{{width:100%;height:auto;border-radius:8px}}
.b{{color:#fff;font-size:12px;padding:2px 8px;border-radius:999px;vertical-align:middle}} .m{{font-size:13px;color:#5B606B;font-weight:400}}
section{{border-top:1px solid #DCD7CC;padding-top:4px}} a{{color:#3446C9}}
@media (prefers-color-scheme: dark){{body{{background:#121318;color:#EDEEF2}} .m{{color:#A3A8B4}} a{{color:#B7C0FF}} section{{border-color:#2A2D36}}}}</style></head>
<body><h1>Avatar sign review · step 5</h1>
<p>Each sheet: top row front, bottom row side (from the signer's right), at every keyframe (t = seconds at speed 1).
Rendered with the app's own engine page (<code>tools/avatar_shots.py</code>), character Nour.
Signs with <code>avatar: false</code> are not used by the app until you approve them.</p>
{''.join(rows)}</body></html>"""
    out = a.sheets / "index.html"
    out.write_text(page, encoding="utf-8")
    print("wrote", out, len(rows), "signs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
