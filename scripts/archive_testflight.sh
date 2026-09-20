#!/usr/bin/env bash
set -euo pipefail

# Archives Wissh for App Store Connect and exports an .ipa ready for
# TestFlight upload. Pass --upload to send it to App Store Connect through
# the Apple ID signed into Xcode.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

team_id="${WISSH_DEVELOPMENT_TEAM:-NLCK9L8N9G}"
upload=0
if [[ "${1:-}" == "--upload" ]]; then
  upload=1
elif [[ -n "${1:-}" ]]; then
  echo "Usage: scripts/archive_testflight.sh [--upload]" >&2
  exit 2
fi

archive_path=".local/archives/Wissh-$(date +%Y%m%d-%H%M%S).xcarchive"
export_path=".local/archives/export-$(date +%Y%m%d-%H%M%S)"
export_options="$(mktemp -t wissh-export-options).plist"
trap 'rm -f "$export_options"' EXIT

destination="export"
if [[ "$upload" -eq 1 ]]; then
  destination="upload"
fi

cat >"$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>${destination}</string>
	<key>teamID</key>
	<string>${team_id}</string>
</dict>
</plist>
PLIST

mkdir -p .local/archives

xcodebuild archive \
  -project Wissh.xcodeproj \
  -scheme Wissh \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team_id"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_path" \
  -allowProvisioningUpdates

if [[ "$upload" -eq 1 ]]; then
  echo "Uploaded to App Store Connect. Manage the build in TestFlight."
else
  echo "Exported .ipa in $export_path"
  echo "Upload it with the Transporter app, or re-run with --upload."
fi
