#!/usr/bin/env bash
# Builds the app's bundled fonts (offline, no Google Fonts CDN) from the google/fonts repo.
# Google ships variable fonts only; Flutter matches static weights reliably, so this cuts one
# static TTF per weight the prototype loads (design/prototype.html line 9):
#   Figtree 400-900 (UI), Cairo 400/500/700/900 (Arabic), Bricolage Grotesque 600/700/800 (titles).
# Bricolage is pinned at opsz 24 / wdth 100 (the prototype's titles are 17-42 px; CSS picks opsz
# from the font size, Flutter can't). Licences (OFL) are copied next to the fonts.
#
# Usage: app/tools/make_fonts.sh        (needs curl and python3; installs fonttools in a temp venv)
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/../ishara_app" && pwd)"
OUT="$APP_DIR/assets/fonts"
BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet 'fonttools==4.*'
PY="$WORK/venv/bin/python"

fetch() { curl -fsSL "$BASE/$1" -o "$WORK/$2"; }
fetch 'figtree/Figtree%5Bwght%5D.ttf' figtree.ttf
fetch 'cairo/Cairo%5Bslnt,wght%5D.ttf' cairo.ttf
fetch 'bricolagegrotesque/BricolageGrotesque%5Bopsz,wdth,wght%5D.ttf' bricolage.ttf

rm -rf "$OUT" && mkdir -p "$OUT"
for f in figtree cairo bricolagegrotesque; do fetch "$f/OFL.txt" "OFL-$f.txt"; cp "$WORK/OFL-$f.txt" "$OUT/OFL-$f.txt"; done

cut() { # cut <src> <family> <weight> <extra axes...>
  local src="$1" fam="$2" w="$3"; shift 3
  "$PY" -m fontTools.varLib.instancer "$WORK/$src" "wght=$w" "$@" --static --quiet -o "$OUT/$fam-$w.ttf"
}
for w in 400 500 600 700 800 900; do cut figtree.ttf Figtree "$w"; done
for w in 400 500 700 900; do cut cairo.ttf Cairo "$w" slnt=0; done
for w in 600 700 800; do cut bricolage.ttf BricolageGrotesque "$w" opsz=24 wdth=100; done

ls -l "$OUT"
