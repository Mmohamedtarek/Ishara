#!/usr/bin/env bash
# Beside integration_test/sos_test.dart on the emulator (step 9, SOS check):
# grants location while in use once the app is installed, sets the fix,
# then records what Android opened for SMS and the dialer (the activity on
# top, its intent, a screenshot) and brings the app back. Sends nothing.
#   app/tools/sos_watch.sh <log of the flutter test run> [out dir]
set -euo pipefail
LOG=$1
OUT=${2:-$(dirname "$0")/out/step9/sos}
PKG=io.github.mmohamedtarek.ishara
mkdir -p "$OUT"

until adb shell pm list packages | grep -q "package:$PKG\$"; do sleep 1; done
adb shell pm grant $PKG android.permission.ACCESS_FINE_LOCATION
adb shell pm grant $PKG android.permission.ACCESS_COARSE_LOCATION
# Cairo, Tahrir Square, every second like a live GPS, until the run ends.
# MODE=geo: `adb emu geo fix` (longitude first; the emulator reports only a
# changed position, so it alternates by 0.1 m). MODE=test: Android's own
# test provider on gps (when geo fix doesn't reach the fused provider).
# MODE=none: a real phone, no fake position.
MODE=${MODE:-geo}
if [ "$MODE" = test ]; then
  adb shell appops set com.android.shell android:mock_location allow
  adb shell cmd location providers add-test-provider gps --requiresSatellite || true
  adb shell cmd location providers set-test-provider-enabled gps true
fi
fix() { # $1 = latitude
  if [ "$MODE" = none ]; then
    return 0 # a phone: its own GPS
  elif [ "$MODE" = test ]; then
    adb shell cmd location providers set-test-provider-location gps \
      --location "$1,31.235712" --accuracy 5 > /dev/null
  else
    adb emu geo fix 31.235712 "$1" > /dev/null
  fi
}
( while ! grep -qE "SOS done|All tests passed|Some tests failed" "$LOG"; do
    fix 30.044420; sleep 1
    fix 30.044421; sleep 1
  done
  if [ "$MODE" = test ]; then
    adb shell cmd location providers remove-test-provider gps || true
  fi ) &
echo "granted, fix streaming"

look() { # $1 = name
  sleep 5
  adb shell dumpsys activity activities |
    grep -m3 -E "topResumedActivity|mResumedActivity|ResumedActivity" > "$OUT/$1_top.txt" || true
  adb shell dumpsys activity recents | grep -m4 -E "Intent \{|realActivity" > "$OUT/$1_intent.txt" || true
  adb shell screencap -p /sdcard/ishara_$1.png && adb pull -q /sdcard/ishara_$1.png "$OUT/$1.png"
  adb shell rm -f /sdcard/ishara_$1.png
  echo "$1: $(cat "$OUT/$1_top.txt" | head -1)"
  # an "Open with" chooser would keep the app behind it: close it
  if grep -q ResolverActivity "$OUT/$1_top.txt"; then adb shell input keyevent KEYCODE_BACK; fi
  sleep 2
  adb shell am start -n $PKG/.MainActivity > /dev/null
}

until grep -q "SOS open sms" "$LOG"; do sleep 0.5; done
look sms
until grep -q "SOS open dialer" "$LOG"; do sleep 0.5; done
look dialer
