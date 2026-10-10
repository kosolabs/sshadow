#!/bin/zsh
#
# Makes the given SSHadow.app the only registered copy, so File Provider pairs
# the app with its own extension. Archiving also registers the archive's
# intermediate copy, and File Provider rejects the app under test if it
# isn't the parent of the registered extension.
#
# Usage: register_app.sh path/to/SSHadow.app

set -euo pipefail

APP="${1:a}"
APPEX="$APP/Contents/PlugIns/Extension.appex"
EXTENSION_ID="com.kosolabs.SSHadow.Extension"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Support/lsregister

registered_extensions() {
  pluginkit -mAvvv -i "$EXTENSION_ID" | awk -F' = ' '/^ *Path = /{print $2}'
}

registered_extensions | while IFS= read -r appex; do
  [[ "$appex" == "$APPEX" ]] && continue
  pluginkit -r "$appex"
  echo "Unregistered extension: $appex"
done

$LSREGISTER -dump \
  | awk -F'path: *' '/^[[:space:]]*path:.*SSHadow\.app/{p=$2; sub(/ \([0-9a-fx]+\)$/,"",p); print p}' \
  | sort -u \
  | while IFS= read -r app; do
    [[ "$app" == "$APP" ]] && continue
    $LSREGISTER -u "$app" 2>/dev/null || true
    echo "Unregistered app: $app"
  done

$LSREGISTER -f "$APP"
pluginkit -a "$APPEX"

# Registration is asynchronous.
for _ in {1..150}; do
  [[ "$(registered_extensions)" == "$APPEX" ]] && break
  sleep 0.1
done
if [[ "$(registered_extensions)" != "$APPEX" ]]; then
  echo "❌ Expected only $APPEX to be registered, found:"
  pluginkit -mAvvv -i "$EXTENSION_ID"
  exit 1
fi
echo "✅ Registered $APP"
