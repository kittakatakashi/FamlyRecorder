#!/bin/zsh
set -euo pipefail

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

scheme="${SCHEME:-FamlyRecorder}"
project="${PROJECT:-FamlyRecorder.xcodeproj}"
only_testing="${ONLY_TESTING:-FamlyRecorderTests}"
ci_sim_name="${CI_SIMULATOR_NAME:-FamlyRecorder-CI}"

if [[ -n "${CI_DESTINATION:-}" ]]; then
  destination="$CI_DESTINATION"
else
  booted_device_id="$(
    xcrun simctl list devices available \
      | sed -n 's/.*(\\([A-F0-9-]\\{36\\}\\)).*(Booted).*/\\1/p' \
      | head -n 1
  )"

  if [[ -n "$booted_device_id" ]]; then
    destination="id=$booted_device_id"
  else
    fallback_device_id="$(
      xcrun simctl list devices available \
        | sed -n 's/.*iPhone[^()]* (\\([A-F0-9-]\\{36\\}\\)).*(available).*/\\1/p' \
        | head -n 1
    )"

    if [[ -z "$fallback_device_id" ]]; then
      runtime_id="$(
        xcrun simctl list runtimes available \
          | sed -n 's/^iOS .* - \\(com\\.apple\\.CoreSimulator\\.SimRuntime\\.iOS[-0-9.]*\\) (.*/\\1/p' \
          | head -n 1
      )"
      device_type_id="$(
        xcrun simctl list devicetypes \
          | sed -n 's/^iPhone.*(\\(com\\.apple\\.CoreSimulator\\.SimDeviceType\\.[^)]*\\)).*/\\1/p' \
          | head -n 1
      )"

      if [[ -z "$runtime_id" || -z "$device_type_id" ]]; then
        echo "No available iPhone simulator found, and failed to resolve runtime/device type for creating one." >&2
        exit 1
      fi

      existing_ci_id="$(
        xcrun simctl list devices \
          | sed -n "s/.*${ci_sim_name} (\\([A-F0-9-]\\{36\\}\\)).*/\\1/p" \
          | head -n 1
      )"
      if [[ -n "$existing_ci_id" ]]; then
        xcrun simctl delete "$existing_ci_id" || true
      fi

      fallback_device_id="$(xcrun simctl create "$ci_sim_name" "$device_type_id" "$runtime_id")"
      if [[ -z "$fallback_device_id" ]]; then
        echo "Failed to create iPhone simulator for CI." >&2
        exit 1
      fi
    fi

    destination="id=$fallback_device_id"
  fi
fi

xcodebuild test \
  -project "$project" \
  -scheme "$scheme" \
  -destination "$destination" \
  -only-testing:"$only_testing"
