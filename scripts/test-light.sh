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
    xcrun simctl list -j devices available | python3 -c '
import json, sys
devices = json.load(sys.stdin).get("devices", {})
for runtime_devices in devices.values():
    for d in runtime_devices:
        if d.get("isAvailable") and d.get("state") == "Booted":
            print(d.get("udid", ""))
            raise SystemExit(0)
print("")
'
  )"

  if [[ -n "$booted_device_id" ]]; then
    destination="id=$booted_device_id"
  else
    fallback_device_id="$(
      xcrun simctl list -j devices available | python3 -c '
import json, sys
devices = json.load(sys.stdin).get("devices", {})
for runtime_devices in devices.values():
    for d in runtime_devices:
        if d.get("isAvailable") and d.get("name", "").startswith("iPhone"):
            print(d.get("udid", ""))
            raise SystemExit(0)
print("")
'
    )"

    if [[ -z "$fallback_device_id" ]]; then
      runtime_id="$(
        xcrun simctl list -j runtimes available | python3 -c '
import json, sys
for r in json.load(sys.stdin).get("runtimes", []):
    if not r.get("isAvailable"):
        continue
    ident = r.get("identifier", "")
    if "iOS" in ident and "Simulator" in ident:
        print(ident)
        raise SystemExit(0)
print("")
'
      )"
      device_type_id="$(
        xcrun simctl list -j devicetypes | python3 -c '
import json, sys
for d in json.load(sys.stdin).get("devicetypes", []):
    if d.get("name", "").startswith("iPhone"):
        print(d.get("identifier", ""))
        raise SystemExit(0)
print("")
'
      )"

      if [[ -z "$runtime_id" ]]; then
        echo "No iOS simulator runtime is available. Attempting to download iOS platform..." >&2
        xcodebuild -downloadPlatform iOS
        runtime_id="$(
          xcrun simctl list -j runtimes available | python3 -c '
import json, sys
for r in json.load(sys.stdin).get("runtimes", []):
    if not r.get("isAvailable"):
        continue
    ident = r.get("identifier", "")
    if "iOS" in ident and "Simulator" in ident:
        print(ident)
        raise SystemExit(0)
print("")
'
        )"
      fi

      if [[ -z "$runtime_id" || -z "$device_type_id" ]]; then
        echo "No available iPhone simulator found, and failed to resolve runtime/device type for creating one." >&2
        xcrun simctl list devices
        xcrun simctl list runtimes
        xcrun simctl list devicetypes
        exit 1
      fi

      existing_ci_id="$(
        CI_SIM_NAME="$ci_sim_name" xcrun simctl list -j devices | python3 -c '
import json, os, sys
name = os.environ.get("CI_SIM_NAME", "")
devices = json.load(sys.stdin).get("devices", {})
for runtime_devices in devices.values():
    for d in runtime_devices:
        if d.get("name") == name:
            print(d.get("udid", ""))
            raise SystemExit(0)
print("")
'
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
