#!/usr/bin/env bash
# Launch the traced release build on the connected device, type a query,
# and print QuickDex timing trace lines from logcat. Used by `make perf`.
#
# The device is a personal phone: only QuickDex's own log lines are read (by pid),
# the device log is never cleared, and keystrokes are only sent while QuickDex
# is the focused window.
set -euo pipefail
PKG=app.quickdex

if ! adb shell dumpsys power | grep -q 'mWakefulness=Awake'; then
  echo "perf: device screen is off; unlock the phone and rerun tool/perf.sh" >&2
  exit 1
fi

adb shell am force-stop "$PKG"
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
PID=""
for _ in $(seq 1 20); do
  PID=$(adb shell pidof "$PKG" | tr -d '\r' || true)
  if [ -n "$PID" ]; then break; fi
  sleep 0.25
done
if [ -z "$PID" ]; then
  echo "perf: $PKG is not running" >&2
  exit 1
fi

applog() { adb logcat -d --pid="$PID" -s flutter; }

for _ in $(seq 1 60); do
  if applog | grep -q 'startup.load.done'; then break; fi
  sleep 0.5
done
if ! applog | grep 'startup.load.done'; then
  echo "perf: no startup.load.done within 30s" >&2
  exit 1
fi

# Wait for the first frame's search, then make sure QuickDex has focus before typing.
for _ in $(seq 1 20); do
  if applog | grep -q 'search.query.done'; then break; fi
  sleep 0.5
done
if ! adb shell dumpsys window | grep -E 'mCurrentFocus=.*'"$PKG" >/dev/null; then
  echo "perf: $PKG is not the focused window (screen locked?); not sending keystrokes" >&2
  exit 1
fi

adb shell input text mrmime
for _ in $(seq 1 20); do
  if [ "$(applog | grep -c 'search.query.done')" -ge 7 ]; then break; fi
  sleep 0.5
done
applog | grep 'search.query.done'
