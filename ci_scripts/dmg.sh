#!/bin/zsh

set -euo pipefail

# Archives the app, exports a Developer ID build, packages it as a DMG, signs
# and notarizes it, and saves it to build/SSHadow.dmg. Intermediate artifacts
# are kept in build/ for debugging. Runs locally via `just dmg` or in GitHub
# Actions.
#
# Requires a "Developer ID Application" certificate + private key in the
# keychain, and these environment variables (see .env.example):
#   APP_STORE_CONNECT_API_KEY_ID       Key ID of an App Store Connect API key
#   APP_STORE_CONNECT_API_ISSUER_ID    Issuer ID for that key
#   APP_STORE_CONNECT_API_PRIVATE_KEY  base64 of the AuthKey_<key id>.p8 contents

cd "${0:a:h}/.."

APP_NAME="SSHadow"
TEAM_ID="A5S59GAS97"

git fetch --unshallow 2>/dev/null || true
BUILD_NUMBER="$(git rev-list --count HEAD)"
STAGING_DIR="build/staging"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
APP_PATH="build/${APP_NAME}.app"
DMG_PATH="build/${APP_NAME}.dmg"

KEY_DIR="$(mktemp -d)"
trap 'rm -rf "$KEY_DIR"' EXIT
API_KEY_PATH="$KEY_DIR/AuthKey_${APP_STORE_CONNECT_API_KEY_ID}.p8"
base64 --decode <<<"$APP_STORE_CONNECT_API_PRIVATE_KEY" >"$API_KEY_PATH"

mkdir -p build

cat >build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.kosolabs.SSHadow</key>
        <string>SSHadow Developer ID</string>
        <key>com.kosolabs.SSHadow.Extension</key>
        <string>SSHadow Extension Developer ID</string>
    </dict>
</dict>
</plist>
EOF

echo "Archiving ${APP_NAME} (build ${BUILD_NUMBER})..."
xcodebuild archive \
  -scheme "$APP_NAME" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "Exporting Developer ID build of ${APP_NAME}..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath build \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$API_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"

echo "Building DMG..."
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
trap 'rm -rf "$STAGING_DIR"' EXIT

hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "Signing DMG..."
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"

echo "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
  --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo "✅ Notarized DMG saved to ${DMG_PATH}"
