#!/usr/bin/env python3
"""Talk voice drafts page for the user's approval: app/tools/out/talk_voice/drafts.html.

Every new text of the talk voice work (2026-10-26, hold to talk) (EN + Egyptian Arabic, from extract_strings.py
TALKVOICE_DRAFTS). Usage: python3 app/tools/talk_voice_drafts.py
"""
import html

from extract_strings import TALKVOICE_DRAFTS, TALKVOICE_NS_DRAFTS
from proto_common import REPO

OUT = REPO / "app" / "tools" / "out" / "talk_voice" / "drafts.html"


def esc(s: str) -> str:
    return html.escape(s)


def table(d):
    return "\n".join(
        f"<tr><td><b>{esc(why.split(':')[0])}</b><br><code>{esc(k)}</code></td><td>{esc(e)}</td>"
        f'<td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>'
        for k, (e, a, why, _ph) in d.items()
    )


ns_rows = table(TALKVOICE_NS_DRAFTS)
rows = "\n".join(
    f"<tr><td><b>{esc(why.split(':')[0])}</b><br><code>{esc(k)}</code></td><td>{esc(e)}</td>"
    f'<td dir="rtl" lang="ar">{esc(a)}</td><td>{esc(why)}</td></tr>'
    for k, (e, a, why, _ph) in TALKVOICE_DRAFTS.items()
)
page = f"""<!doctype html><html><head><meta charset="utf-8"><title>Talk voice drafts</title>
<style>body{{font:14px system-ui,sans-serif;margin:24px;max-width:1100px}}table{{border-collapse:collapse;width:100%;margin-bottom:28px}}
td,th{{border:1px solid #ccc;padding:6px 8px;vertical-align:middle;text-align:start}}th{{background:#eee}}
td[dir=rtl]{{font-size:15px}}</style></head><body>
<h1>Talk voice: hold to talk, texts ({len(TALKVOICE_DRAFTS)}), approved 2026-10-26</h1>
<table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th><th>Where / why</th></tr>
{rows}</table>
<h1>Words with no sign: texts ({len(TALKVOICE_NS_DRAFTS)}), approved 2026-10-27 (NS2: «مالهمش» for 3–10)</h1>
<table><tr><th>ID / key</th><th>English</th><th>Egyptian Arabic</th><th>Where / why</th></tr>
{ns_rows}</table>
</body></html>"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(page, encoding="utf-8")
print(OUT.relative_to(REPO))
