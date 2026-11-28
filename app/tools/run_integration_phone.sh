#!/usr/bin/env bash
# Every integration_test/ file on the phone, one at a time (they aren't in
# CI). Logs in app/tools/out/integration/ (git-ignored).
#   ANDROID_SERIAL=<your phone's serial, from `adb devices`> app/tools/run_integration_phone.sh
# (no serial is written in the repo: it is public)
# backend_test.dart needs the Firebase emulators on this laptop, started with
# the global Firebase CLI (firebase-tools 15.33.0):
#   cd firebase && firebase emulators:start --only auth,firestore --project demo-ishara
# and adb reverse (done here); without them it is skipped here.
# sos_test runs with tools/sos_watch.sh (MODE=none: the phone's real
# location); its screenshots are deleted at the end (they can show the
# real location).
set -u
: "${ANDROID_SERIAL:?set ANDROID_SERIAL}"
HERE=$(cd "$(dirname "$0")" && pwd)
APP="$HERE/../ishara_app"
OUT="$HERE/out/integration"
mkdir -p "$OUT"
cd "$APP"
wake() { adb shell input keyevent KEYCODE_WAKEUP; adb shell wm dismiss-keyguard; }
for f in onboarding talk learn avatar history settings flow; do
  wake
  timeout 1500 flutter test "integration_test/${f}_test.dart" -d "$ANDROID_SERIAL" > "$OUT/$f.log" 2>&1
  echo "$f: $(grep -E 'All tests passed|Some tests failed' "$OUT/$f.log" | tail -1)"
done
if curl -s -o /dev/null "http://127.0.0.1:9099/"; then
  adb reverse tcp:9099 tcp:9099 > /dev/null && adb reverse tcp:8080 tcp:8080 > /dev/null
  wake
  timeout 1500 flutter test integration_test/backend_test.dart -d "$ANDROID_SERIAL" \
    --dart-define=BACKEND=emulator > "$OUT/backend.log" 2>&1
  echo "backend: $(grep -E 'All tests passed|Some tests failed' "$OUT/backend.log" | tail -1)"
else
  echo "backend: skipped (Firebase emulators not running)"
fi
adb uninstall io.github.mmohamedtarek.ishara > /dev/null 2>&1 || true
wake
W="$OUT/sos_watch"; rm -rf "$W"; mkdir -p "$W"
timeout 900 flutter test integration_test/sos_test.dart -d "$ANDROID_SERIAL" > "$OUT/sos.log" 2>&1 &
T=$!
MODE=none timeout 900 "$HERE/sos_watch.sh" "$OUT/sos.log" "$W" > "$W/watch.log" 2>&1 &
WATCH=$!
wait $T
sleep 3
kill $WATCH 2> /dev/null || true
rm -f "$W"/*.png
echo "sos: $(grep -E 'All tests passed|Some tests failed' "$OUT/sos.log" | tail -1)"
echo ALL DONE
