#!/bin/zsh
set -euo pipefail

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

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

xcodebuild test \
  -project FamlyRecorder.xcodeproj \
  -scheme FamlyRecorder \
  -destination "$destination" \
  -only-testing:FamlyRecorderTests
