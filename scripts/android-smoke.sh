#!/usr/bin/env bash
# Captures launch, rotation, cold-restart and logcat evidence from an Android device.
set -euo pipefail

serial=""
out_dir=""
app_id="io.energylens.energylens_mobile"
app_activity="$app_id/.MainActivity"
launch_wait=20
rotate_wait=5
failures=()

usage() {
  cat <<'EOF_USAGE'
Usage:
  scripts/android-smoke.sh --serial SERIAL --out DIR

Runs against a device that already has the app installed. Launches the app,
checks it stays alive in portrait and landscape and after a cold restart, and
writes launch-portrait.png, launch-landscape.png, launch-time.txt, logcat.txt
and device.txt to DIR. Exits 1 when a check fails or logcat shows a
FATAL EXCEPTION, an ANR in io.energylens, or a Flutter EXCEPTION CAUGHT BY block.
EOF_USAGE
}

while (($#)); do
  case "$1" in
    --serial)
      (($# >= 2)) || { usage >&2; exit 2; }
      serial="$2"; shift 2 ;;
    --out)
      (($# >= 2)) || { usage >&2; exit 2; }
      out_dir="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage >&2; exit 2 ;;
  esac
done
[[ -n "$serial" && -n "$out_dir" ]] || { usage >&2; exit 2; }

command -v adb >/dev/null || { echo 'adb is required.' >&2; exit 1; }
adb devices | awk '$2 == "device" { print $1 }' | grep -qx -- "$serial" || {
  echo "Device $serial is not connected and authorized; check adb devices -l." >&2
  exit 1
}
mkdir -p "$out_dir"

# Records a failure when the app process is not running.
check_alive() {
  [[ -n "$(adb -s "$serial" shell pidof "$app_id" | tr -d '\r')" ]] || failures+=("$1: $app_id is not running")
}

# Force-stops the app and launches it, printing the reported TotalTime.
cold_launch() {
  adb -s "$serial" shell am force-stop "$app_id"
  adb -s "$serial" shell am start -W -n "$app_activity" | tr -d '\r' | awk '/^TotalTime:/ { print $2 }'
}

adb -s "$serial" logcat -c
total_time="$(cold_launch)"
echo "TotalTime: ${total_time:-unknown} ms" | tee "$out_dir/launch-time.txt"
sleep "$launch_wait"
check_alive 'after launch'
adb -s "$serial" exec-out screencap -p >"$out_dir/launch-portrait.png"

adb -s "$serial" shell settings put system accelerometer_rotation 0
adb -s "$serial" shell settings put system user_rotation 1
sleep "$rotate_wait"
check_alive 'in landscape'
adb -s "$serial" exec-out screencap -p >"$out_dir/launch-landscape.png"
adb -s "$serial" shell settings put system user_rotation 0

cold_launch >/dev/null
sleep "$rotate_wait"
check_alive 'after cold restart'

adb -s "$serial" logcat -d >"$out_dir/logcat.txt"
grep -q 'FATAL EXCEPTION' "$out_dir/logcat.txt" && failures+=('logcat contains FATAL EXCEPTION')
grep -q "ANR in io.energylens" "$out_dir/logcat.txt" && failures+=('logcat contains ANR in io.energylens')
grep -q '══╡ EXCEPTION CAUGHT BY' "$out_dir/logcat.txt" && failures+=('logcat contains a Flutter EXCEPTION CAUGHT BY block')

{
  for prop in ro.product.model ro.build.version.release ro.build.version.sdk ro.product.cpu.abi; do
    echo "$prop=$(adb -s "$serial" shell getprop "$prop" | tr -d '\r')"
  done
  adb -s "$serial" shell wm size | tr -d '\r'
  adb -s "$serial" shell wm density | tr -d '\r'
} >"$out_dir/device.txt"

if ((${#failures[@]} > 0)); then
  printf 'FAIL %s: %s\n' "$serial" "${failures[@]}" >&2
  exit 1
fi
echo "PASS $serial: TotalTime ${total_time:-unknown} ms, evidence in $out_dir"
