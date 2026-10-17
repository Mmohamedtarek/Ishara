#!/usr/bin/env python3
"""Step 10 drafts page for the user's approval: app/tools/out/step10/drafts.html.

Every new text of step 10 (EN + Egyptian Arabic, from extract_strings.py
STEP10_DRAFTS). Usage: python3 app/tools/step10_drafts.py
"""
import html

from extract_strings import STEP10_DRAFTS
from proto_common import REPO

OUT = REPO / "app" / "tools" / "out" / "step10" / "drafts.html"


def esc(s: str) -> str:
    return html.escape(s)


rows = "\n".join(
    f"<tr><td><b>{esc(why.split(':')[0])}</b><br><code>{esc(k)}</code></td><td>{esc(e)}</td>"
    f'<td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>'
    for k, (e, a, why, _ph) in STEP10_DRAFTS.items()
)
page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Step 10 drafts</title>
<style>body{{font:14px system-ui,sans-serif;margin:24px;max-width:1100px}}table{{border-collapse:collapse;width:100%;margin-bottom:28px}}
td,th{{border:1px solid #ccc;padding:6px 8px;vertical-align:middle;text-align:start}}th{{background:#eee}}
td[dir=rtl]{{font-size:15px}}</style></head><body>
<h1>Step 10a: texts ({len(STEP10_DRAFTS)}), approved 2026-10-17</h1>
<table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th><th>Where / why</th></tr>
{rows}</table>
</body></html>"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page, encoding="utf-8")
print(OUT.relative_to(REPO))
