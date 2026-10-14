#!/usr/bin/env bash
# Adapted from kernel-app/scripts/run-kernel-app.sh's explicit-target deploy
# workflow. This script is self-contained and has no Kernel runtime dependency.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hub_url=""
postal_code=""
device_ids=()
iphone_ids=()
local_pilot=false
team_id=""

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy-ios-simulator.sh --hub-url 'https://HUB_IP:PORT#sha256=LEAF_CERT_SHA256' [--postal-code ZIP] --device SIMULATOR_ID [--device SIMULATOR_ID]
  scripts/deploy-ios-simulator.sh --local-pilot [--postal-code ZIP] [--device SIMULATOR_ID] [--iphone DEVICE_ID] [--team TEAM_ID]

The Hub mode builds and launches on explicitly named, booted simulators. Set
ENERGYLENS_HUB_TOKEN in the calling shell to bootstrap a pilot token into the
simulator Keychain. The local-pilot mode builds with Xcode and can deploy to
booted simulators (Debug) or paired iPhones (signed Release). An iPhone uses
the signing team configured in Runner.xcodeproj unless --team overrides it.
Use --iphone only for owner-requested physical acceptance. List targets with
"xcrun simctl list devices available" and "xcrun devicectl list devices".
EOF
}

while (($#)); do
  case "$1" in
    --hub-url)
      (($# >= 2)) || { usage >&2; exit 2; }
      hub_url="$2"; shift 2 ;;
    --device|--simulator)
      (($# >= 2)) || { usage >&2; exit 2; }
      device_ids+=("$2"); shift 2 ;;
    --iphone)
      (($# >= 2)) || { usage >&2; exit 2; }
      iphone_ids+=("$2"); shift 2 ;;
    --local-pilot)
      local_pilot=true; shift ;;
    --team)
      (($# >= 2)) || { usage >&2; exit 2; }
      team_id="$2"; shift 2 ;;
    --postal-code)
      (($# >= 2)) || { usage >&2; exit 2; }
      postal_code="$2"; shift 2 ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage >&2; exit 2 ;;
  esac
done

if [[ "$local_pilot" == true ]]; then
  [[ -z "$hub_url" ]] || { echo '--hub-url cannot be combined with --local-pilot.' >&2; exit 2; }
  ((${#device_ids[@]} + ${#iphone_ids[@]} > 0)) || { echo 'Pass at least one --device or --iphone.' >&2; exit 2; }
else
  hub_url_pattern='^https://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+(#sha256=[0-9a-f]{64})?$'
  [[ "$hub_url" =~ $hub_url_pattern ]] || {
    echo 'Pass an HTTPS hub IPv4 address and port, with #sha256=<64 lowercase hex digits> for a self-signed certificate.' >&2
    exit 2
  }
  ((${#device_ids[@]} > 0)) || { echo 'Pass at least one --device.' >&2; exit 2; }
  ((${#iphone_ids[@]} == 0)) || { echo '--iphone requires --local-pilot.' >&2; exit 2; }
  [[ -z "$team_id" ]] || { echo '--team requires --local-pilot.' >&2; exit 2; }
fi
[[ -z "$team_id" || "$team_id" =~ ^[A-Za-z0-9]+$ ]] || { echo 'Pass an alphanumeric Apple team ID.' >&2; exit 2; }
[[ -z "$postal_code" || "$postal_code" =~ ^[0-9]{5}$ ]] || {
  echo 'Pass a five-digit ZIP code with --postal-code.' >&2
  exit 2
}
command -v flutter >/dev/null || { echo 'Flutter is required.' >&2; exit 1; }
command -v xcrun >/dev/null || { echo 'Xcode command tools are required.' >&2; exit 1; }

cd "$repo_dir"
if [[ "$local_pilot" == true ]]; then
  command -v xcodebuild >/dev/null || { echo 'Xcode is required.' >&2; exit 1; }
  build_args=(--dart-define=ENERGYLENS_LOCAL_PILOT=true)
  if [[ -n "$postal_code" ]]; then
    build_args+=("--dart-define=ENERGYLENS_POSTAL_CODE=$postal_code")
  fi
  flutter build ios --config-only --release "${build_args[@]}"
  if ((${#device_ids[@]} > 0)); then
    xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
      -configuration Debug -sdk iphonesimulator \
      -destination 'generic/platform=iOS Simulator' \
      ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
    app_path="$repo_dir/build/ios/Debug-iphonesimulator/Runner.app"
    [[ -d "$app_path" ]] || { echo "Simulator app missing: $app_path" >&2; exit 1; }
    if lipo -archs "$app_path/Runner" | grep -q x86_64; then
      arch -x86_64 /usr/bin/true >/dev/null 2>&1 || {
        echo 'This simulator build needs Rosetta 2 for its Intel-only ML Kit libraries.' >&2
        exit 1
      }
    fi
    for device_id in "${device_ids[@]}"; do
      xcrun simctl install "$device_id" "$app_path"
      xcrun simctl launch --terminate-running-process "$device_id" \
        io.energylens.energylensMobile
    done
  fi
  if ((${#iphone_ids[@]} > 0)); then
    command -v codesign >/dev/null || { echo 'Xcode code signing tools are required.' >&2; exit 1; }
    if [[ -z "$team_id" ]]; then
      team_id="$(xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
        -configuration Release -sdk iphoneos -showBuildSettings 2>/dev/null \
        | awk '/^[[:space:]]*DEVELOPMENT_TEAM = / { print $3; exit }')"
    fi
    [[ "$team_id" =~ ^[A-Za-z0-9]+$ ]] || {
      echo 'Runner has no signing team; pass --team TEAM_ID.' >&2
      exit 1
    }
    signing_args=(CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES ENABLE_MODULE_VERIFIER=NO)
    signing_args+=("DEVELOPMENT_TEAM=$team_id")
    xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
      -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
      -derivedDataPath "$repo_dir/build/xcode-device" \
      "${signing_args[@]}" build
    app_path="$repo_dir/build/xcode-device/Build/Products/Release-iphoneos/Runner.app"
    [[ -d "$app_path" ]] || { echo "Signed iPhone app missing: $app_path" >&2; exit 1; }
    codesign --verify --deep --strict "$app_path" || {
      echo "iPhone app code signature is invalid: $app_path" >&2
      exit 1
    }
    open -a Xcode ios/Runner.xcworkspace
    for device_id in "${iphone_ids[@]}"; do
      if ! xcrun devicectl device install app --timeout 60 --device "$device_id" "$app_path"; then
        echo "Install failed for $device_id. Unlock and trust the phone, enable Developer Mode, and check its wireless connection in Xcode Devices and Simulators." >&2
        exit 1
      fi
      xcrun devicectl device process launch --timeout 30 --terminate-existing --device "$device_id" \
        io.energylens.energylensMobile
    done
  fi
  exit 0
fi

build_args=("--dart-define=ENERGYLENS_HUB_URL=$hub_url")
if [[ -n "$postal_code" ]]; then
  build_args+=("--dart-define=ENERGYLENS_POSTAL_CODE=$postal_code")
fi
flutter build ios --simulator --debug "${build_args[@]}"
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
