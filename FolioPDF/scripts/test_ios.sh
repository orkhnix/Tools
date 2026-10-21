#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
if ! command -v xcodebuild >/dev/null; then
  echo "Run this script on macOS with Xcode and an iOS Simulator runtime." >&2
  exit 1
fi
if [[ -z "${SIMULATOR_ID:-}" ]]; then
  SIMULATOR_ID="$(xcrun simctl list devices available --json | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[x["udid"] for k,v in d["devices"].items() if ".iOS-" in k for x in v if x.get("isAvailable") and "iPhone" in x["name"]]; print(ids[0] if ids else "")')"
fi
if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No available iPhone Simulator. Install an iOS runtime in Xcode Settings." >&2
  exit 1
fi
mkdir -p build
test_action="${FOLIO_TEST_ACTION:-test}"
case "$test_action" in
  test|test-without-building) ;;
  *) echo "FOLIO_TEST_ACTION must be test or test-without-building." >&2; exit 1 ;;
esac
xcodebuild -project FolioPDF.xcodeproj -scheme FolioPDF -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 120 \
  -resultBundlePath "build/Tests-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO "$test_action"
