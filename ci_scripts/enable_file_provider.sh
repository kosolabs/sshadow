#!/bin/zsh
#
# Enables SSHadow's File Provider extension on a CI runner. New providers
# start disabled until the user turns them on in System Settings (General >
# Login Items & Extensions > File Providers), and there's no API to do that.
# fileproviderd keeps the setting in Domains.plist and only creates the file
# when it first sees the extension, so this creates it first, enabled. Run it
# before building or launching the app.

set -euo pipefail

EXTENSION_ID="com.kosolabs.SSHadow.Extension"
DIR="$HOME/Library/Application Support/FileProvider/$EXTENSION_ID"

if [[ -e "$DIR/Domains.plist" ]]; then
  echo "❌ $DIR/Domains.plist already exists, so fileproviderd has seen the extension"
  plutil -p "$DIR/Domains.plist"
  exit 1
fi

mkdir -p "$DIR"
cat >"$DIR/Domains.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSFileProviderDomainDefaultIdentifier</key>
    <dict>
        <key>Connected</key>
        <false/>
        <key>Enabled</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

plutil -lint "$DIR/Domains.plist"
echo "✅ Enabled $EXTENSION_ID"
