#!/usr/bin/env bash
# Builds the Android APK and installs it on emulators or physical devices.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hub_url=""
emulator_ids=()
physical_ids=()
reverse_ports=()
release=false
local_pilot=false
cloud_auth=false
env_file="$repo_dir/.env-local"
explicit_env=false
build_only=false
app_activity="io.energylens.energylens_mobile/.MainActivity"
boot_timeout=180

usage() {
  cat <<'EOF_USAGE'
Usage:
  scripts/deploy-android.sh --hub-url 'https://HUB_IP:PORT#sha256=LEAF_CERT_SHA256' --emulator AVD_OR_SERIAL [--emulator AVD_OR_SERIAL] [--reverse PORT]
  scripts/deploy-android.sh --local-pilot [--emulator AVD_OR_SERIAL] [--physical SERIAL] [--release] [--reverse PORT]
  scripts/deploy-android.sh --cloud [--env-file PATH] [--emulator AVD_OR_SERIAL] [--physical SERIAL] [--release] [--reverse PORT]

--emulator takes an AVD name (booted when no running emulator has it) or a
running emulator-NNNN serial. Emulators get a Debug build unless --release is
given. --physical takes a serial from "adb devices -l" and always builds
Release; install on a physical device only after the same Release build has
passed on the emulators. Hub mode is emulator and Debug only.
--reverse PORT runs "adb reverse tcp:PORT tcp:PORT" on every target before launch.
Local configuration is loaded from .env-local when present; --env-file selects
another file. Add --build-only to build the APK without installing or launching.
EOF_USAGE
}

while (($#)); do
  case "$1" in
    --hub-url)
      (($# >= 2)) || { usage >&2; exit 2; }
      hub_url="$2"; shift 2 ;;
    --emulator)
      (($# >= 2)) || { usage >&2; exit 2; }
      emulator_ids+=("$2"); shift 2 ;;
    --physical)
      (($# >= 2)) || { usage >&2; exit 2; }
      physical_ids+=("$2"); shift 2 ;;
    --reverse)
      (($# >= 2)) || { usage >&2; exit 2; }
      reverse_ports+=("$2"); shift 2 ;;
    --release)
      release=true; shift ;;
    --local-pilot)
      local_pilot=true; shift ;;
    --cloud)
      cloud_auth=true; shift ;;
    --env-file)
      (($# >= 2)) || { usage >&2; exit 2; }
      env_file="$2"; explicit_env=true; shift 2 ;;
    --build-only)
      build_only=true; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage >&2; exit 2 ;;
  esac
done

if [[ -f "$env_file" ]]; then
  # This is the same operator-controlled shell environment format as the Cloud
  # launcher. Only the public build-setting allowlist below enters the app.
  set -a
  source "$env_file"
  set +a
elif [[ "$explicit_env" == true ]]; then
  echo 'The selected environment file is unavailable.' >&2
  exit 2
fi
if [[ "$local_pilot" == false && "$cloud_auth" == false && -z "$hub_url" ]]; then
  if [[ "${ENERGYLENS_LOCAL_PILOT:-false}" == true ]]; then
    local_pilot=true
  elif [[ -n "${ENERGYLENS_CLOUD_API_URL:-}" ]]; then
    cloud_auth=true
  fi
fi
if [[ "$local_pilot" == false && "$cloud_auth" == false && -z "$hub_url" ]]; then
  hub_url="${ENERGYLENS_HUB_URL:-}"
fi
[[ "$local_pilot" != true || "$cloud_auth" != true ]] || {
  echo '--cloud and --local-pilot cannot be combined.' >&2; exit 2;
}
build_args=()
for setting in ENERGYLENS_HUB_URL ENERGYLENS_DESIGN_TOUR \
    ENERGYLENS_DESIGN_TOUR_DWELL_SECONDS ENERGYLENS_CLOUD_API_URL \
    ENERGYLENS_CLOUD_LOCAL_AUTH_ENABLED ENERGYLENS_CLOUD_DEV_AUTH_ENABLED \
    ENERGYLENS_APP_ENV ENERGYLENS_CLOUD_DEV_CERT_SHA256 \
    ENERGYLENS_CLOUD_LOCAL_AUTH_LINK_ORIGIN ENERGYLENS_OIDC_ISSUER \
    ENERGYLENS_OIDC_AUDIENCE ENERGYLENS_OIDC_CLIENT_ID \
    ENERGYLENS_OIDC_REDIRECT_URL; do
  [[ -z "${!setting:-}" ]] || build_args+=("--dart-define=$setting=${!setting}")
done
if [[ "$cloud_auth" == true ]]; then
  [[ -z "$hub_url" ]] || { echo '--hub-url cannot be combined with --cloud.' >&2; exit 2; }
  python3 - <<'PY'
import os
from urllib.parse import urlsplit

url = urlsplit(os.environ.get('ENERGYLENS_CLOUD_API_URL', ''))
if (url.scheme != 'https' or not url.hostname or url.username or url.password
        or url.path not in ('', '/') or url.query or url.fragment
        or url.hostname == 'invalid' or url.hostname.endswith('.invalid')):
    raise SystemExit('Configure a real HTTPS ENERGYLENS_CLOUD_API_URL in .env-local.')
local = os.environ.get('ENERGYLENS_CLOUD_LOCAL_AUTH_ENABLED') == 'true'
dev = (os.environ.get('ENERGYLENS_CLOUD_DEV_AUTH_ENABLED') == 'true'
       and os.environ.get('ENERGYLENS_APP_ENV') == 'dev')
oidc = all(os.environ.get(key) for key in (
    'ENERGYLENS_OIDC_ISSUER', 'ENERGYLENS_OIDC_AUDIENCE',
    'ENERGYLENS_OIDC_CLIENT_ID', 'ENERGYLENS_OIDC_REDIRECT_URL'))
if not (local or dev or oidc):
    raise SystemExit('Configure an authentication profile in .env-local before building Cloud mode.')
PY
fi

if [[ "$local_pilot" == true || "$cloud_auth" == true ]]; then
  [[ -z "$hub_url" ]] || { echo '--hub-url cannot be combined with --local-pilot.' >&2; exit 2; }
  [[ "$build_only" == true ]] || ((${#emulator_ids[@]} + ${#physical_ids[@]} > 0)) || { echo 'Pass at least one --emulator or --physical.' >&2; exit 2; }
else
  hub_url_pattern='^https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+(#sha256=[0-9a-f]{64})?$'
  [[ "$hub_url" =~ $hub_url_pattern ]] || {
    echo 'Pass an HTTPS hub IPv4 address and port, with #sha256=<64 lowercase hex digits> for a self-signed certificate.' >&2
    exit 2
  }
  ((${#physical_ids[@]} == 0)) || { echo '--physical requires --local-pilot or --cloud.' >&2; exit 2; }
  [[ "$build_only" == true ]] || ((${#emulator_ids[@]} > 0)) || { echo 'Pass at least one --emulator.' >&2; exit 2; }
  [[ "$release" == false ]] || { echo '--release requires --local-pilot or --cloud.' >&2; exit 2; }
fi
for port in ${reverse_ports[@]+"${reverse_ports[@]}"}; do
  [[ "$port" =~ ^[0-9]+$ ]] || { echo 'Pass a numeric port with --reverse.' >&2; exit 2; }
done
if ((${#physical_ids[@]} > 0)); then release=true; fi

command -v flutter >/dev/null || { echo 'Flutter is required.' >&2; exit 1; }
command -v adb >/dev/null || { echo 'adb is required.' >&2; exit 1; }
for id in ${emulator_ids[@]+"${emulator_ids[@]}"}; do
  [[ "$id" =~ ^emulator-[0-9]+$ ]] || command -v emulator >/dev/null || {
    echo 'The Android emulator is required to boot an AVD.' >&2
    exit 1
  }
done

cd "$repo_dir"
build_args+=("--dart-define=ENERGYLENS_LOCAL_PILOT=$local_pilot")
if [[ "$local_pilot" == false && "$cloud_auth" == false ]]; then
  build_args+=("--dart-define=ENERGYLENS_HUB_URL=$hub_url")
fi
if [[ "$release" == true ]]; then
  flutter build apk --release "${build_args[@]}"
  apk_path="$repo_dir/build/app/outputs/flutter-apk/app-release.apk"
else
  flutter build apk --debug "${build_args[@]}"
  apk_path="$repo_dir/build/app/outputs/flutter-apk/app-debug.apk"
fi
[[ -f "$apk_path" ]] || { echo "APK missing: $apk_path" >&2; exit 1; }

if [[ "$build_only" == true ]]; then exit 0; fi

# Prints the serial of a running emulator whose AVD name is $1, if any.
find_emulator_serial() {
  local serial name
  while read -r serial; do
    name="$(adb -s "$serial" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
    if [[ "$name" == "$1" ]]; then echo "$serial"; return 0; fi
  done < <(adb devices | awk '/^emulator-[0-9]+[[:space:]]+device/ { print $1 }')
  return 1
}

targets=()
mkdir -p "$repo_dir/build"
for id in ${emulator_ids[@]+"${emulator_ids[@]}"}; do
  if [[ "$id" =~ ^emulator-[0-9]+$ ]]; then
    serial="$id"
  elif ! serial="$(find_emulator_serial "$id")"; then
    nohup emulator -avd "$id" -no-snapshot-save -gpu swiftshader_indirect \
      -camera-back virtualscene -camera-front emulated >"$repo_dir/build/android-emulator-$id.log" 2>&1 &
    deadline=$((SECONDS + boot_timeout))
    until serial="$(find_emulator_serial "$id")"; do
      ((SECONDS < deadline)) || { echo "Emulator $id did not appear within ${boot_timeout}s." >&2; exit 1; }
      sleep 2
    done
  fi
  deadline=$((SECONDS + boot_timeout))
  timeout "$boot_timeout" adb -s "$serial" wait-for-device || {
    echo "Emulator $serial is not reachable." >&2; exit 1;
  }
  until [[ "$(adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]; do
    ((SECONDS < deadline)) || { echo "Emulator $serial did not finish booting within ${boot_timeout}s." >&2; exit 1; }
    sleep 2
  done
  targets+=("$serial")
done
for serial in ${physical_ids[@]+"${physical_ids[@]}"}; do
  adb devices | awk '$2 == "device" { print $1 }' | grep -qx -- "$serial" || {
    echo "Physical device $serial is not connected and authorized; check adb devices -l." >&2
    exit 1
  }
  targets+=("$serial")
done

for serial in "${targets[@]}"; do
  adb -s "$serial" install -r "$apk_path" || {
    echo "Install failed for $serial. Check that USB debugging is authorized; for INSTALL_FAILED_UPDATE_INCOMPATIBLE, uninstall io.energylens.energylens_mobile first." >&2
    exit 1
  }
  for port in ${reverse_ports[@]+"${reverse_ports[@]}"}; do
    adb -s "$serial" reverse "tcp:$port" "tcp:$port"
  done
  adb -s "$serial" shell am start -W -n "$app_activity"
done
