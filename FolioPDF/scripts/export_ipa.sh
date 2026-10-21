#!/usr/bin/env bash
# Run on a Mac with Xcode and an Apple signing identity/provisioning setup.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
if ! command -v xcodebuild >/dev/null; then
  echo "Xcode on macOS is required. No IPA was created." >&2
  exit 1
fi
if [[ -z "${TEAM_ID:-}" || -z "${BUNDLE_ID:-}" ]]; then
  echo "Set TEAM_ID to your Apple team ID and BUNDLE_ID to your unique app identifier." >&2
  exit 1
fi
export_method="${EXPORT_METHOD:-debugging}"
case "$export_method" in
  debugging|release-testing|app-store-connect) ;;
  *) echo "EXPORT_METHOD must be debugging, release-testing, or app-store-connect." >&2; exit 1 ;;
esac
mkdir -p build
export TEAM_ID
export FOLIO_EXPORT_METHOD="$export_method"
/usr/bin/python3 - <<'PY'
import os, plistlib
with open('build/ExportOptions.plist', 'wb') as out:
    plistlib.dump({'method': os.environ['FOLIO_EXPORT_METHOD'], 'teamID': os.environ['TEAM_ID'],
                  'signingStyle': 'automatic', 'destination': 'export',
                  'manageAppVersionAndBuildNumber': False}, out)
PY
xcodebuild -project FolioPDF.xcodeproj -scheme FolioPDF -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/FolioPDF.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/FolioPDF.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
if ! find build/export -maxdepth 1 -name '*.ipa' -print -quit | /usr/bin/grep -q .; then
  echo "Export did not produce an IPA. Review the Xcode export log." >&2
  exit 1
fi
echo "Export succeeded:"
find build/export -maxdepth 1 -name '*.ipa' -print
