#!/usr/bin/env bash
# Real snapshots of the old key-value store (before step 10), written by
# each version's own store classes, taken from git: step 6 (432af54),
# step 7 (3e72281), step 8 (dc355a1), step 9 (7aba72f). The drivers in
# test/ do typical user actions; the dumps go to
# app/ishara_app/test/storage/legacy_snapshots/ for the migration tests.
#   bash app/tools/legacy_snapshots/make.sh
# Changes to the copied code: imports point at the copy; sign_catalogue.dart
# is reduced to its SpokenLanguage enum line; device_id.dart loses its
# Riverpod provider (generated code). Nothing else.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cp "$HERE/pubspec.yaml" "$W/"
mkdir -p "$W/lib" "$W/test" "$W/out"
cp "$HERE"/test/*.dart "$W/test/"
declare -A C=([v6]=432af54 [v7]=3e72281 [v8]=dc355a1 [v9]=7aba72f)
FILES="core/storage/key_value_store.dart core/profile/onboarding_store.dart
core/conversation/conversation_repository.dart core/device/device_id.dart
features/learn/data/activity_repository.dart
features/learn/domain/activity_event.dart features/learn/domain/local_day.dart
core/phrases/saved_phrases_repository.dart core/settings/settings_store.dart
features/sos/data/emergency_contacts_repository.dart core/logging/log.dart
core/errors/failure.dart"
cd "$REPO"
for v in "${!C[@]}"; do
  c=${C[$v]}
  for f in $FILES; do
    if git cat-file -e "${c}:app/ishara_app/lib/${f}" 2>/dev/null; then
      mkdir -p "$W/lib/$v/$(dirname "$f")"
      git show "${c}:app/ishara_app/lib/${f}" |
        sed "s#package:ishara_app/#package:snapgen/$v/#g" > "$W/lib/$v/$f"
    fi
  done
  mkdir -p "$W/lib/$v/core/catalogue"
  git show "${c}:app/ishara_app/lib/core/catalogue/sign_catalogue.dart" |
    grep '^enum SpokenLanguage' > "$W/lib/$v/core/catalogue/sign_catalogue.dart"
  d="$W/lib/$v/core/device/device_id.dart"
  if [ -f "$d" ]; then
    python3 - "$d" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"import .package:snapgen/v\d/core/profile/profile_providers.dart.;\n", "", s)
s = re.sub(r"import .package:riverpod_annotation/riverpod_annotation.dart.;\n", "", s)
s = re.sub(r"part .*?;\n", "", s)
s = s[: s.index("@Riverpod")] if "@Riverpod" in s else s
open(p, "w").write(s)
PY
  fi
done
cd "$W"
flutter pub get > /dev/null
flutter test
cp out/*.json "$REPO/app/ishara_app/test/storage/legacy_snapshots/"
ls "$REPO/app/ishara_app/test/storage/legacy_snapshots/"
