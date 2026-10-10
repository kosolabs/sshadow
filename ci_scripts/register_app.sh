#!/bin/zsh
#
# Makes the given SSHadow.app the only registered copy, so File Provider pairs
# the app with its own extension. Archiving leaves other copies (the archive
# and its intermediate build) that get registered, and File Provider drops the
# extension whenever the registration for its bundle ID changes. CI only: it
# deletes those copies and unregisters every other SSHadow.app.
#
# Usage: register_app.sh path/to/SSHadow.app

set -euo pipefail

if [[ -z "${CI:-}" ]]; then
  echo "❌ register_app.sh deletes and unregisters other copies of SSHadow, so it only runs in CI"
  exit 1
fi

APP="${1:a}"
APPEX="$APP/Contents/PlugIns/Extension.appex"
EXTENSION_ID="com.kosolabs.SSHadow.Extension"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister

# Prints "path uuid" for each registered copy of the extension.
registrations() {
  pluginkit -mAvvv -i "$EXTENSION_ID" | awk -F' = ' '
    /^[[:space:]]*Path = /{path=$2}
    /^[[:space:]]*UUID = /{print path, $2}'
}

$LSREGISTER -dump \
  | awk -F'path: *' '/^[[:space:]]*path:/{p=$2; sub(/ \([0-9a-fx]+\)$/,"",p); print p}' \
  | grep '/SSHadow\.app$' \
  | sort -u \
  | while IFS= read -r app; do
    [[ "$app" == "$APP" ]] && continue
    pluginkit -r "$app/Contents/PlugIns/Extension.appex" 2>/dev/null || true
    $LSREGISTER -u "$app" 2>/dev/null || true
    echo "Unregistered: $app"
  done

# Delete the build's other copies so nothing can register them again.
rm -rf "${APP:h}/SSHadow.xcarchive"
for dir in "$HOME"/Library/Developer/Xcode/DerivedData/*/Build/Intermediates.noindex/ArchiveIntermediates(N); do
  rm -rf "$dir"
  echo "Deleted: $dir"
done

$LSREGISTER -f "$APP"

# Wait until only this copy is registered and its registration stops changing.
stable=0
last=""
for _ in {1..60}; do
  current="$(registrations)"
  if [[ "$current" == "$APPEX "* && "$current" != *$'\n'* && "$current" == "$last" ]]; then
    (( ++stable ))
    (( stable >= 5 )) && break
  else
    stable=0
  fi
  last="$current"
  sleep 1
done
if (( stable < 5 )); then
  echo "❌ Expected only $APPEX to be registered, found:"
  pluginkit -mAvvv -i "$EXTENSION_ID"
  exit 1
fi
echo "✅ Registered $last"
