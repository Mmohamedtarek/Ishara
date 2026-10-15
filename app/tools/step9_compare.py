#!/usr/bin/env python3
"""Step 9 review: the prototype's History, Settings and Avatar screens next to the app's.

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

OUT = REPO / "app" / "tools" / "out" / "step9"
GOLDENS = REPO / "app" / "ishara_app" / "test" / "goldens" / "goldens" / "linux"
LANGS = ["en", "ar"]
THEMES = ["light", "dark"]
# prototype state -> the app goldens shown next to it
PAIRS = {
    "history": ["history_list", "history_empty", "history_search", "history_starred"],
    "settings": ["settings_guest", "settings_signed_in"],
    "avatar": ["avatar_studio"],
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

                for screen in ["history", "settings"]:
                    page.evaluate("s => document.querySelector(`[data-jump=\"${s}\"]`).click()", screen)
                    page.evaluate("document.getElementById('splash').style.display = 'none'")
                    shot(screen)
                # the third row: Avatar (glove, pair, avatar)
                page.evaluate("document.querySelectorAll('#settingsBody .row')[2].click()")
                shot("avatar")
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
                g = Image.open(GOLDENS / f"step9_{name}.png").convert("RGB")
                col = ["en light", "en dark", "ar light", "ar dark"].index(f"{lang} {theme}")
                sheet.paste(g.crop((col * w, top, (col + 1) * w, top + h)), (x, y + 18))
                d.text((x, y), f"app {name} {lang} {theme}", fill="white")
        path = out / f"{proto}.png"
        sheet.save(path)
        print(path.relative_to(REPO))
    return 0


if __name__ == "__main__":
    sys.exit({"shoot": shoot, "sheets": sheets}[sys.argv[1]]())
