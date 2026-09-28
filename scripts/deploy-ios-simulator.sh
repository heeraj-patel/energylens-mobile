#!/usr/bin/env bash
# Adapted from kernel-app/scripts/run-kernel-app.sh's explicit-target deploy
# workflow. This script is self-contained and has no Kernel runtime dependency.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hub_url=""
device_ids=()

usage() {
  cat <<'EOF'
Usage: scripts/deploy-ios-simulator.sh --hub-url http://HUB_IP:PORT --device SIMULATOR_ID [--device SIMULATOR_ID]

Builds EnergyLens for iOS Simulator with ENERGYLENS_HUB_URL, then installs
and launches it on each explicitly named simulator. Set ENERGYLENS_HUB_TOKEN
in the calling shell to bootstrap the pilot token into simulator Keychain at
launch. The token is never passed to Flutter's build or stored in this script.
EOF
}

while (($#)); do
  case "$1" in
    --hub-url)
      (($# >= 2)) || { usage >&2; exit 2; }
      hub_url="$2"; shift 2 ;;
    --device)
      (($# >= 2)) || { usage >&2; exit 2; }
      device_ids+=("$2"); shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage >&2; exit 2 ;;
  esac
done

[[ "$hub_url" =~ ^http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]] || {
  echo 'Pass an HTTP hub IPv4 address and port with --hub-url.' >&2
  exit 2
}
((${#device_ids[@]} > 0)) || { echo 'Pass at least one --device.' >&2; exit 2; }
command -v flutter >/dev/null || { echo 'Flutter is required.' >&2; exit 1; }
command -v xcrun >/dev/null || { echo 'Xcode command tools are required.' >&2; exit 1; }

cd "$repo_dir"
flutter build ios --simulator --debug "--dart-define=ENERGYLENS_HUB_URL=$hub_url"
app_path="$repo_dir/build/ios/iphonesimulator/Runner.app"
if lipo -archs "$app_path/Runner" | grep -q x86_64; then
  arch -x86_64 /usr/bin/true >/dev/null 2>&1 || {
    echo 'This build needs Rosetta 2 to run its Intel-only ML Kit simulator libraries.' >&2
    echo 'Install Rosetta, then run this script again.' >&2
    exit 1
  }
fi

for device_id in "${device_ids[@]}"; do
  xcrun simctl install "$device_id" "$app_path"
  if [[ -n "${ENERGYLENS_HUB_TOKEN:-}" ]]; then
    data_path="$(xcrun simctl get_app_container "$device_id" io.energylens.energylensMobile data)"
    pairing_file="$data_path/tmp/energylens-pairing.json"
    mkdir -p "$data_path/tmp"
    ENERGYLENS_HUB_TOKEN="$ENERGYLENS_HUB_TOKEN" python3 -c \
      'import json,os,sys; json.dump({"address":sys.argv[1],"token":os.environ["ENERGYLENS_HUB_TOKEN"]},open(sys.argv[2],"w"))' \
      "$hub_url" "$pairing_file"
    chmod 600 "$pairing_file"
  fi
  xcrun simctl launch --terminate-running-process "$device_id" \
    io.energylens.energylensMobile
done
