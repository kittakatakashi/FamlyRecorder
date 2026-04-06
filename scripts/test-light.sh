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

if [[ -n "${CI_DESTINATION:-}" ]]; then
  destination="$CI_DESTINATION"
else
  booted_device_id="$(
    xcrun simctl list devices booted available \
      | sed -n 's/.*(\\([A-F0-9-]\\{36\\}\\)) (Booted)/\\1/p' \
      | head -n 1
  )"

  if [[ -n "$booted_device_id" ]]; then
    destination="id=$booted_device_id"
  else
    fallback_device_id="$(
      xcrun simctl list devices available \
        | sed -n 's/.*iPhone[^()]* (\\([A-F0-9-]\\{36\\}\\)) (Shutdown)/\\1/p' \
        | head -n 1
    )"

    if [[ -z "$fallback_device_id" ]]; then
      echo "No available iPhone simulator found." >&2
      exit 1
    fi

    destination="id=$fallback_device_id"
  fi
fi

xcodebuild test \
  -project "$project" \
  -scheme "$scheme" \
  -destination "$destination" \
  -only-testing:"$only_testing"
