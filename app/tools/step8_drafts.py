#!/usr/bin/env python3
"""Step 8 drafts page for the user's approval: app/tools/out/step8/drafts.html.

Lists the new Learn texts (EN + Egyptian Arabic, from extract_strings.py
STEP8_DRAFTS), the module looks (icon + colour, ModuleLook) and the quiz tile
icons (signs.json "icon"), drawn with the prototype's own SVG icons.
Usage: python3 app/tools/step8_drafts.py
"""
import html
import json
import re

from extract_strings import STEP8_DRAFTS, STEP8_TEXTS
from proto_common import REPO

APP = REPO / "app" / "ishara_app"
OUT = REPO / "app" / "tools" / "out" / "step8" / "drafts.html"

icons_src = (APP / "lib" / "core" / "ui" / "ishara_icon_data.dart").read_text(encoding="utf-8")
ICONS = dict(re.findall(r"'([a-z0-9-]+)': r'''(<svg.*?</svg>)'''", icons_src, flags=re.S))

look_src = (APP / "lib" / "features" / "learn" / "presentation" / "learn_modules_ui.dart").read_text(encoding="utf-8")
COLORS = {name: (a, b) for name, a, b in re.findall(
    r"static const (\w+) = \[Color\(0xFF(\w{6})\), Color\(0xFF(\w{6})\)\];", look_src)}
LOOKS = re.findall(r"'(\w+)': ModuleLook\('([\w-]+)', (\w+), \(l\) => l\.(\w+)\)", look_src)
PROTO_LOOKS = {"start"}  # the prototype's own (mStart: c-teal, star)

signs = json.loads((APP / "assets" / "packs" / "asl" / "signs.json").read_text(encoding="utf-8"))
PROTO_ICONS = {"hello", "thanks", "please", "yes", "no", "help", "sorry", "water", "coffee",
               "doctor", "home", "family", "iloveyou"}


def icon(name: str, color: str = "#3446C9", size: int = 26) -> str:
    svg = ICONS.get(name, "?")
    return (f'<span style="display:inline-block;width:{size}px;height:{size}px;color:{color}">'
            + svg.replace("<svg ", f'<svg width="{size}" height="{size}" ') + "</span>")


def esc(s: str) -> str:
    return html.escape(s)


def text_rows(items: dict) -> str:
    return "\n".join(
        f"<tr><td><b>{why.split(':')[0]}</b><br><code>{esc(k)}</code></td><td>{esc(e)}</td>"
        f'<td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>'
        for k, (e, a, why, _ph) in items.items()
    )


drafts = text_rows(STEP8_DRAFTS)
rows = text_rows(STEP8_TEXTS)
looks = "\n".join(
    f"<tr><td><code>{mid}</code></td>"
    f'<td><span style="display:inline-grid;place-items:center;width:50px;height:50px;border-radius:16px;'
    f'background:linear-gradient(135deg,#{COLORS[col][0]},#{COLORS[col][1]})">{icon(ic, "#fff", 24)}</span></td>'
    f"<td><code>{ic}</code>, {col}</td><td>{'prototype (mStart)' if mid in PROTO_LOOKS else 'approved'}</td></tr>"
    for mid, ic, col, _title in LOOKS
)
tiles = "\n".join(
    f"<tr><td><code>{s['label']}</code></td><td>{esc(s['en']['word'])}</td>"
    f"<td dir='rtl'>{esc(s['ar']['word'])}</td><td>{icon(s['icon'])}</td><td><code>{s['icon']}</code></td>"
    f"<td>{'prototype WORDS' if s['label'] in PROTO_ICONS else 'approved: no prototype icon, neutral hand'}</td></tr>"
    for s in signs["signs"]
)

page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Step 8 drafts</title>
<style>body{{font:14px system-ui,sans-serif;margin:24px;max-width:1100px}}table{{border-collapse:collapse;width:100%;margin-bottom:28px}}
td,th{{border:1px solid #ccc;padding:6px 8px;vertical-align:middle;text-align:start}}th{{background:#eee}}
td[dir=rtl]{{font-size:15px}}</style></head><body>
<h1>Step 8 (Learn): texts</h1>
<h2>Draft for your approval</h2>
<p>ICU plural: Arabic 0 is not in your list; it uses the 11+ form («0 يوم»). Examples: EN 1 day, 2 days;
AR يوم واحد، يومين، 3 أيام … 10 أيام، 11 يوم، 100 يوم.</p>
<table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th><th>Where / why</th></tr>
{drafts}</table>
<h2>1. Approved 2026-10-15 (L1-L20; L17 Arabic is your wording)</h2>
<table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th><th>Where / why</th></tr>
{rows}</table>
<p>Not new: module subtitles other than Start here are the signs' words from <code>signs.json</code> joined with
", " / "، " (e.g. "One, Two, Three, Four, Five"). The practice feedback above 92 % keeps the prototype's
"Great! {{p}}% match". "being reviewed" (sign rule 5) is a debug-only English marker.</p>
<h2>2. Module looks (approved 2026-10-15)</h2>
<table><tr><th>Module</th><th>Look</th><th>Icon, colour</th><th>Source</th></tr>
{looks}<tr><td><code>daily</code></td><td><span style="display:inline-grid;place-items:center;width:50px;height:50px;border-radius:16px;background:linear-gradient(135deg,#FCD34D,#D97706)">{icon('bolt','#fff',24)}</span></td><td><code>bolt</code>, amber</td><td>prototype (mDaily)</td></tr></table>
<h2>3. Quiz tile icons (approved 2026-10-15)</h2>
<table><tr><th>Label</th><th>EN</th><th>AR</th><th>Icon</th><th>Name</th><th>Source</th></tr>
{tiles}</table>
</body></html>"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page, encoding="utf-8")
print(OUT.relative_to(REPO))
