#!/usr/bin/env python3
"""Step 8 review: the prototype's Learn and Mission states next to the app's.

1. Prototype shots (Playwright + system Chrome, venv as proto_shot.py):
     app/tools/.venv/bin/python app/tools/step8_compare.py shoot
   drives #s-learn and #s-mission (module "greet": hello, thanks, please,
   sorry) through: learn, quiz, quiz_wrong, practice_idle, practice_counting,
   practice_passed, result -> app/tools/out/step8/proto/.
2. Sheets (system python3 with Pillow):
     python3 app/tools/step8_compare.py sheets
   prototype | app for each state, EN / AR x light / dark, from the app's
   real-text goldens (test/goldens/goldens/linux/learn_*.png) ->
   app/tools/out/step8/compare/.
"""
import pathlib
import sys

from proto_common import REPO, prototype_src

OUT = REPO / "app" / "tools" / "out" / "step8"
GOLDENS = REPO / "app" / "ishara_app" / "test" / "goldens" / "goldens" / "linux"
LANGS = ["en", "ar"]
THEMES = ["light", "dark"]
# prototype state -> the app goldens shown next to it
PAIRS = {
    "learn": ["new_guest", "progress", "daily_done"],
    "quiz": ["quiz_idle", "quiz_picked", "quiz_right"],
    "quiz_wrong": ["quiz_wrong"],
    "practice_idle": ["practice_idle", "practice_no_glove"],
    "practice_counting": ["practice_counting"],
    "practice_passed": ["practice_passed"],
    "practice_failed": ["practice_retry", "practice_failed"],
    "result": ["result_medal", "result_no_medal"],
}
WORDS = ["hello", "thanks", "please", "sorry"]


def shoot() -> int:
    from playwright.sync_api import sync_playwright

    out = OUT / "proto"
    out.mkdir(parents=True, exist_ok=True)
    src = prototype_src()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        for theme in THEMES:
            for lang in LANGS:
                ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1)
                ctx.add_init_script(f"localStorage.setItem('ishara-theme','{theme}');"
                                    f"localStorage.setItem('ishara-lang','{lang}');")
                page = ctx.new_page()
                page.goto(src.as_uri())
                page.wait_for_timeout(500)

                def shot(name: str) -> None:
                    page.wait_for_timeout(450)
                    path = out / f"{name}_{lang}_{theme}.png"
                    page.locator("#stage").screenshot(path=str(path))
                    print(path.relative_to(REPO))

                def click(sel: str) -> None:
                    page.evaluate(f"document.querySelector({sel!r}).click()")

                page.evaluate("document.querySelector('[data-jump=\"learn\"]').click()")
                # the jump handler hides the splash; then it can go
                page.evaluate("document.getElementById('splash').style.display = 'none'")
                shot("learn")
                page.evaluate("document.querySelector('[data-jump=\"mission\"]').click()")
                shot("quiz")
                # a wrong pick: the second word's tile, on the first quiz
                wrong = WORDS[1]
                page.evaluate(f"(document.querySelector('#missionBody .tile[data-w=\"{wrong}\"]') || "
                              f"[...document.querySelectorAll('#missionBody .tile')].find(t => t.dataset.w !== 'hello')).click()")
                click("#missionCta .btn")
                shot("quiz_wrong")
                click("#missionCta .btn")  # Next
                shot("practice_idle")
                click("#missionCta .btn")  # Sign now
                page.wait_for_timeout(700)
                path = out / f"practice_counting_{lang}_{theme}.png"
                page.locator("#stage").screenshot(path=str(path))
                print(path.relative_to(REPO))
                page.wait_for_timeout(2200)
                shot("practice_passed")
                click("#missionCta .btn")  # Next
                for w in WORDS[1:]:
                    click(f"#missionBody .tile[data-w=\"{w}\"]")
                    click("#missionCta .btn")
                    click("#missionCta .btn")
                    click("#missionCta .btn")
                    page.wait_for_timeout(2700)
                    click("#missionCta .btn")
                shot("result")
                ctx.close()
        browser.close()
    return 0


def sheets() -> int:
    from PIL import Image, ImageDraw

    out = OUT / "compare"
    out.mkdir(parents=True, exist_ok=True)
    w, h, top = 390, 844, 31
    for proto, apps in PAIRS.items():
        cols = 1 + len(apps)
        sheet = Image.new("RGB", (cols * (w + 12) + 12, 4 * (h + 40) + 12), "#888888")
        d = ImageDraw.Draw(sheet)
        for row, (lang, theme) in enumerate((l, t) for t in THEMES for l in LANGS):
            y = 12 + row * (h + 40)
            p = OUT / "proto" / f"{proto}_{lang}_{theme}.png"
            x = 12
            d.text((x, y), f"prototype {proto} {lang} {theme}", fill="white")
            if p.exists():
                sheet.paste(Image.open(p).convert("RGB").resize((w, h)), (x, y + 18))
            else:
                d.text((x + 20, y + 200), "(no prototype state)", fill="white")
            for i, name in enumerate(apps):
                x = 12 + (i + 1) * (w + 12)
                g = Image.open(GOLDENS / f"learn_{name}.png").convert("RGB")
                col = ["en light", "en dark", "ar light", "ar dark"].index(f"{lang} {theme}")
                sheet.paste(g.crop((col * w, top, (col + 1) * w, top + h)), (x, y + 18))
                d.text((x, y), f"app {name} {lang} {theme}", fill="white")
        path = out / f"{proto}.png"
        sheet.save(path)
        print(path.relative_to(REPO))
    return 0


if __name__ == "__main__":
    sys.exit({"shoot": shoot, "sheets": sheets}[sys.argv[1]]())
