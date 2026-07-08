#!/bin/zsh

set -euo pipefail

# Only archive builds produce a .xcarchive; skip for plain build/test actions
# (ci_post_xcodebuild.sh runs after every action).
if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  exit 0
fi

# Requires these Xcode Cloud workflow environment variables (App Store Connect ->
# Xcode Cloud -> workflow -> Environment, added as Secret):
#   APP_STORE_CONNECT_API_KEY_ID       Key ID of an App Store Connect API key
#   APP_STORE_CONNECT_API_ISSUER_ID    Issuer ID for that key
#   APP_STORE_CONNECT_API_PRIVATE_KEY  base64 of the AuthKey_<key id>.p8 contents
# and a "Developer ID Application" certificate available under Xcode Cloud's
# managed signing certificates, since App Store signing can't notarize outside
# the App Store.

APP_NAME="${CI_PRODUCT:-SSHadow}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

API_KEY_PATH="$WORK_DIR/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
base64 --decode <<<"$APP_STORE_CONNECT_API_PRIVATE_KEY" >"$API_KEY_PATH"

cat >"$WORK_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${CI_DEVELOPMENT_TEAM}</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo "Exporting Developer ID build of ${APP_NAME}..."
EXPORT_DIR="$WORK_DIR/export"
xcodebuild -exportArchive \
  -archivePath "$CI_ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$WORK_DIR/ExportOptions.plist"

echo "Building DMG..."
STAGING_DIR="$WORK_DIR/staging"
mkdir -p "$STAGING_DIR"
cp -R "$EXPORT_DIR/${APP_NAME}.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$WORK_DIR/${APP_NAME}.dmg"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

mkdir -p "$CI_ARTIFACTS_DIR"
cp "$DMG_PATH" "$CI_ARTIFACTS_DIR/${APP_NAME}.dmg"

echo "✅ Notarized ${APP_NAME}.dmg saved to Xcode Cloud artifacts"
