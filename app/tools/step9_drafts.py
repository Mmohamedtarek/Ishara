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

from extract_strings import AR_CHANGED, STEP9_DRAFTS, STEP9B_DRAFTS
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


def row(k: str, e: str, a: str, why: str) -> str:
    return (f"<tr><td><b>{esc(why.split(':')[0])}</b><br><code>{esc(k)}</code></td><td>{esc(e)}</td>"
            f'<td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>')


def group(prefix: str) -> str:
    return "\n".join(row(k, e, a, why) for k, (e, a, why, _ph) in STEP9_DRAFTS.items()
                      if re.match(rf"{prefix}\d", why))


new_rows = "\n".join(row(k, e, a, why) for k, (e, a, why, _ph) in STEP9B_DRAFTS.items())
changed_rows = "\n".join(f'<tr><td><code>{esc(k)}</code></td><td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>'
                          for k, (a, why) in AR_CHANGED.items())


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
<h1>Step 9: texts</h1>
<h2>New texts from the step 9 review ({len(STEP9B_DRAFTS)}), approved 2026-10-17</h2>
<p>Approved with the step 10 brief. The age: minutes under 1 h, hours under 48 h, then days (ICU plurals); the
"out of date" line under a last known position older than 1 hour; the SMS / phone app messages with
"Copy message" (copies the same text the SMS would carry) and its toast.</p>
<table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th><th>Where / why</th></tr>
{new_rows}</table>
<h2>Approved 2026-10-15 ({count}), with your Arabic changes</h2>
<p>Starred = «المحفوظة» everywhere; «SOS» instead of «استغاثة» in every Arabic text; O6 and S3 as you wrote
them. Dates and times use Western digits in both languages. Placeholders in braces are filled by the app.</p>
{sections}
<h2>Earlier texts changed by the same answers</h2>
<table><tr><th>Key</th><th>Egyptian Arabic</th><th>Why</th></tr>
{changed_rows}
<tr><td><code>toastSosSpoken</code></td><td dir="rtl" lang="ar">اتنطقت رسالة SOS بصوت عالي.</td><td>your wording (step 7 text D2)</td></tr></table>
<h2>Outside the ARB files</h2>
<table><tr><th>Where</th><th>Text</th></tr>
<tr><td>iOS location prompt (Info.plist, English only until the iOS build is localised)</td><td>{esc(ios_prompt)}</td></tr>
</table>
</body></html>"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page, encoding="utf-8")
print(OUT.relative_to(REPO))
