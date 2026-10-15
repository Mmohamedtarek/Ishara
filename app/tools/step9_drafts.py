#!/usr/bin/env python3
"""Step 9 drafts page for the user's approval: app/tools/out/step9/drafts.html.

Lists every new text of step 9 (History, Settings, Privacy, About, Avatar
studio, SOS; EN + Egyptian Arabic, from extract_strings.py STEP9_DRAFTS),
grouped by its ID prefix, plus the two texts that live outside the ARB files
(the iOS location prompt in Info.plist and the SOS message's wording).
Usage: python3 app/tools/step9_drafts.py
"""
import html
import re

from extract_strings import STEP9_DRAFTS
from proto_common import REPO

APP = REPO / "app" / "ishara_app"
OUT = REPO / "app" / "tools" / "out" / "step9" / "drafts.html"

GROUPS = {
    "H": "History",
    "S": "Settings",
    "P": "Privacy",
    "A": "About and Avatar studio",
    "E": "Emergency contacts",
    "O": "SOS sheet and message",
}


def esc(s: str) -> str:
    return html.escape(s)


def group(prefix: str) -> str:
    rows = [
        f"<tr><td><b>{esc(why.split(':')[0])}</b><br><code>{esc(k)}</code></td><td>{esc(e)}</td>"
        f'<td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>'
        for k, (e, a, why, _ph) in STEP9_DRAFTS.items()
        if re.match(rf"{prefix}\d", why)
    ]
    return "\n".join(rows)


plist = (APP / "ios" / "Runner" / "Info.plist").read_text(encoding="utf-8")
m = re.search(r"<key>NSLocationWhenInUseUsageDescription</key>\s*<string>(.*?)</string>", plist, re.S)
ios_prompt = m.group(1) if m else "(missing)"

sections = "\n".join(
    f"<h2>{name}</h2><table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th>"
    f"<th>Where / why</th></tr>{group(p)}</table>"
    for p, name in GROUPS.items()
)
count = len(STEP9_DRAFTS)

page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Step 9 drafts</title>
<style>body{{font:14px system-ui,sans-serif;margin:24px;max-width:1100px}}table{{border-collapse:collapse;width:100%;margin-bottom:28px}}
td,th{{border:1px solid #ccc;padding:6px 8px;vertical-align:middle;text-align:start}}th{{background:#eee}}
td[dir=rtl]{{font-size:15px}}</style></head><body>
<h1>Step 9: draft texts ({count}), waiting for your approval</h1>
<p>Starred is «المعلّمة» everywhere (the prototype's own term). Dates and times use Western digits in
both languages (09:00, 18:02), as the rest of the app. Placeholders in braces are filled by the app.</p>
{sections}
<h2>Outside the ARB files</h2>
<table><tr><th>Where</th><th>Text</th></tr>
<tr><td>iOS location prompt (Info.plist, English only until the iOS build is localised)</td><td>{esc(ios_prompt)}</td></tr>
</table>
</body></html>"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page, encoding="utf-8")
print(OUT.relative_to(REPO))
