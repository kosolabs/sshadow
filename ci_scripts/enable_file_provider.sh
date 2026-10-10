#!/bin/zsh
#
# Enables SSHadow's File Provider extension on a CI runner. New providers
# start disabled until the user turns them on in System Settings (General >
# Login Items & Extensions > File Providers), and there's no API to do that,
# so this flips the flag fileproviderd stores and restarts it.
#
# Usage: enable_file_provider.sh path/to/SSHadow.app

set -euo pipefail

APP="${1:a}"
EXTENSION_ID="com.kosolabs.SSHadow.Extension"
PLIST="$HOME/Library/Application Support/FileProvider/$EXTENSION_ID/Domains.plist"

pluginkit -a "$APP/Contents/PlugIns/Extension.appex"

for _ in {1..100}; do
  [[ -f "$PLIST" ]] && break
  sleep 0.1
done
if [[ ! -f "$PLIST" ]]; then
  echo "❌ fileproviderd never created $PLIST"
  exit 1
fi

echo "Before:"
plutil -p "$PLIST"

plutil -replace NSFileProviderDomainDefaultIdentifier \
  -json '{"Enabled": true, "Connected": false}' "$PLIST"

# SIGKILL so fileproviderd doesn't save its in-memory state over the change.
# launchd starts it again on demand.
killall -KILL fileproviderd || true

echo "After:"
plutil -p "$PLIST"
echo "✅ Enabled $EXTENSION_ID"
