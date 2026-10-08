#!/usr/bin/env bash
# Copies the AI team's Mobile Kit into the app's assets. This is the ONLY way kit files enter the app.
#   app/Ishara-Mobile-Kit/{model,mock,test}/  ->  app/ishara_app/assets/kit/{model,mock,test}/
# The copy is exact (stale files are removed). Afterwards:
#   * every copied directory must be declared under `assets:` in pubspec.yaml (checked here);
#   * test/kit/kit_sync_test.dart fails if any asset differs from the kit (sha256), so run the tests.
#
# New model from the AI team: replace app/Ishara-Mobile-Kit/, run this script, run `flutter test`.
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$APP_ROOT/Ishara-Mobile-Kit"
APP="$APP_ROOT/ishara_app"
DEST="$APP/assets/kit"
PARTS=(model mock test)

for p in "${PARTS[@]}"; do
  [[ -d "$KIT/$p" ]] || { echo "error: $KIT/$p is missing" >&2; exit 1; }
done

rm -rf "$DEST"
mkdir -p "$DEST"
for p in "${PARTS[@]}"; do
  cp -R "$KIT/$p" "$DEST/$p"
done

# Every directory that holds files must be listed in pubspec.yaml (Flutter asset dirs aren't recursive).
missing=0
while IFS= read -r dir; do
  rel="assets/kit/${dir#"$DEST"/}/"
  if ! grep -qE "^[[:space:]]*-[[:space:]]+${rel//\//\\/}[[:space:]]*$" "$APP/pubspec.yaml"; then
    echo "error: pubspec.yaml does not declare $rel" >&2
    missing=1
  fi
done < <(find "$DEST" -mindepth 1 -type d -exec sh -c 'ls -p "$1" | grep -qv /' _ {} \; -print | sort)

count=$(find "$DEST" -type f | wc -l)
echo "Synced $count kit files into ${DEST#"$APP_ROOT"/}."
if [[ $missing -ne 0 ]]; then
  echo "Add the directories above to the assets: list in pubspec.yaml." >&2
  exit 1
fi
echo "Now run: (cd app/ishara_app && flutter test test/kit)"
