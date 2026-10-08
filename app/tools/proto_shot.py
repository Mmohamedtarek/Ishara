#!/usr/bin/env python3
"""Screenshot prototype screens (390 x 844) in EN / AR x light / dark, for the UI comparison.

Uses the system Google Chrome through Playwright (no browser download):
  python3 -m venv app/tools/.venv && app/tools/.venv/bin/pip install 'playwright==1.*'
  app/tools/.venv/bin/python app/tools/proto_shot.py learn talk --out app/tools/out/shots
Screens are the prototype's jump names: welcome login setup pair cal talk learn mission history settings
(and 'avatar', reached through Settings). The splash is removed and the 3D avatar is left out
(its GLBs are stripped). Run strip_prototype.py first.
"""
import argparse
import pathlib
import sys

from playwright.sync_api import sync_playwright

from proto_common import REPO, prototype_src


def jump(page, screen: str) -> None:
    # The jump buttons are hidden at phone width, so click them from JS.
    page.evaluate(f"document.querySelector('[data-jump=\"{screen}\"]').click()")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("screens", nargs="+")
    ap.add_argument("--out", default=REPO / "app" / "tools" / "out" / "shots", type=pathlib.Path)
    ap.add_argument("--langs", default="en,ar")
    ap.add_argument("--themes", default="light,dark")
    args = ap.parse_args()
    src = prototype_src()
    args.out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        for theme in args.themes.split(","):
            for lang in args.langs.split(","):
                ctx = browser.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=1,
                                          reduced_motion="reduce")
                ctx.add_init_script(f"localStorage.setItem('ishara-theme','{theme}');"
                                    f"localStorage.setItem('ishara-lang','{lang}');")
                page = ctx.new_page()
                page.goto(src.as_uri())
                page.wait_for_timeout(500)
                for screen in args.screens:
                    if screen == "avatar":
                        jump(page, "settings")
                        page.evaluate("[...document.querySelectorAll('#settingsBody .row')]"
                                      ".find(r => /^(Avatar|الأفاتار)/.test(r.querySelector('b').textContent)).click()")
                    else:
                        jump(page, screen)
                    page.evaluate("document.getElementById('splash')?.remove()")
                    page.wait_for_timeout(400)
                    path = args.out / f"proto_{screen}_{lang}_{theme}.png"
                    page.locator("#stage").screenshot(path=str(path))
                    print(path.relative_to(REPO) if path.is_relative_to(REPO) else path)
                ctx.close()
        browser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
